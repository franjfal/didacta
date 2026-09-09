/**
 * Didacta's authenticated edge.
 *
 * Three jobs, in this order, on every request that is not public:
 *
 *   1. **who is this** — verify the Firebase ID token (`firebase.ts`);
 *   2. **may they** — apply the policy the content repository itself carries
 *      (`policy.ts`);
 *   3. **do it** — talk to GitHub with a token the browser never sees
 *      (`github.ts`).
 *
 * The order is the design. Identity is established before the policy is
 * consulted, and the policy is consulted before anything touches GitHub, so
 * there is no path to the repository that skips a check.
 *
 * The API surface is deliberately tiny. Every route below is a named
 * operation on a path inside one repository; nothing forwards an arbitrary
 * GitHub path, and nothing takes the repository from the caller.
 *
 *   GET  /v1/health           is the Worker configured
 *   GET  /v1/me               who am I and what may I do
 *   GET  /v1/file?path=       read one file
 *   PUT  /v1/file             write one file (compare-and-set)
 *   GET  /v1/policy           the policy itself (admins only)
 */

import { AuthError, KeyStore, bearerToken, verifyIdToken } from './firebase';
import type { VerifiedIdentity } from './firebase';
import { GitHubError, branchHead, readFile, writeFile } from './github';
import type { RepoConfig } from './github';
import { Policy, PolicyError } from './policy';

export interface Env {
  /** The Firebase project whose tokens this API accepts. */
  FIREBASE_PROJECT_ID: string;
  /** Content repository, e.g. `franjfal`. */
  CONTENT_OWNER: string;
  /** e.g. `didacta_db`. */
  CONTENT_REPO: string;
  CONTENT_BRANCH: string;
  /** Origins allowed to call this API, comma-separated. */
  ALLOWED_ORIGINS: string;
  /** Secret. Never returned, never logged. */
  GITHUB_TOKEN: string;
  /** Optional: require Firebase to have verified the address. */
  REQUIRE_VERIFIED_EMAIL?: string;
}

/** Where the policy lives inside the content repository. */
const POLICY_PATH = 'access.json';

/**
 * Cached across requests when the isolate survives, which is most of the time
 * but is never promised. Both caches are best-effort and the miss path is the
 * correct one.
 */
const keyStore = new KeyStore();
let policyCache: { policy: Policy; head: string } | null = null;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const origin = request.headers.get('origin');
    const cors = corsHeaders(origin, env);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }

    try {
      return withHeaders(await route(request, env), cors);
    } catch (error) {
      return withHeaders(errorResponse(error), cors);
    }
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname;

  if (path === '/v1/health') {
    // Deliberately says whether each piece is configured without revealing
    // any of it: "misconfigured" is the failure people actually hit, and
    // finding out should not require reading Worker logs.
    return json({
      ok: true,
      firebaseProject: env.FIREBASE_PROJECT_ID.length > 0,
      repository:
        env.CONTENT_OWNER.length > 0 && env.CONTENT_REPO.length > 0
          ? `${env.CONTENT_OWNER}/${env.CONTENT_REPO}@${env.CONTENT_BRANCH}`
          : null,
      githubToken: env.GITHUB_TOKEN.length > 0,
      allowedOrigins: splitOrigins(env).length,
    });
  }

  const config = repoConfig(env);
  const policy = await loadPolicy(config);
  const identity = await identify(request, env);
  const email = identity?.email ?? null;

  if (path === '/v1/me') {
    return json({
      signedIn: identity !== null,
      uid: identity?.uid ?? null,
      emailVerified: identity?.emailVerified ?? false,
      ...policy.describeUser(email),
      roles: policy.roleNames,
    });
  }

  if (path === '/v1/policy') {
    // Who has access is itself sensitive: it is a list of addresses.
    if (!policy.isAdmin(email)) {
      return problem(403, 'only an admin may read the policy');
    }
    return json(policy.raw);
  }

  if (path === '/v1/file') {
    if (request.method === 'GET') {
      const wanted = url.searchParams.get('path');
      if (wanted === null) return problem(400, 'missing ?path=');

      const decision = policy.can(email, 'read', wanted);
      if (!decision.allowed) {
        return problem(identity === null ? 401 : 403, decision.reason);
      }
      const file = await readFile(config, wanted);
      return json(file);
    }

    if (request.method === 'PUT') {
      const body = await readJson(request);
      const wanted = typeof body.path === 'string' ? body.path : null;
      const text = typeof body.text === 'string' ? body.text : null;
      if (wanted === null || text === null) {
        return problem(400, 'need `path` and `text`');
      }

      const decision = policy.can(email, 'write', wanted);
      if (!decision.allowed) {
        return problem(identity === null ? 401 : 403, decision.reason);
      }
      if (identity === null) {
        return problem(401, 'not signed in');
      }
      if (requireVerified(env) && !identity.emailVerified) {
        return problem(403, 'this API requires a verified email address');
      }

      const written = await writeFile(config, {
        path: wanted,
        text,
        // The commit says who and why. Attribution in git is the audit trail
        // this design relies on -- a permission model whose effects cannot be
        // traced afterwards is not much of one.
        message:
          typeof body.message === 'string' && body.message.length > 0
            ? body.message
            : `Didacta: edit ${wanted}`,
        sha: typeof body.sha === 'string' ? body.sha : undefined,
        author: email === null
          ? undefined
          : { name: identity.name ?? email, email },
      });
      return json(written);
    }

    return problem(405, `${request.method} not allowed on /v1/file`);
  }

  return problem(404, `no such endpoint: ${path}`);
}

/**
 * Verifies the token if there is one. Returns null for an anonymous caller
 * rather than refusing, because some paths are public -- the policy decides,
 * not this function.
 */
async function identify(
  request: Request,
  env: Env,
): Promise<VerifiedIdentity | null> {
  const token = bearerToken(request.headers.get('authorization'));
  if (token === null) return null;
  return verifyIdToken(token, env.FIREBASE_PROJECT_ID, keyStore);
}

/**
 * Loads the policy, revalidated against the branch head.
 *
 * Keyed on the commit rather than on a timer, so granting someone access takes
 * effect on the next request after the commit lands instead of after a cache
 * expires. Revoking access is the case that matters: a TTL means a removed
 * user keeps working for the length of it.
 */
async function loadPolicy(config: RepoConfig): Promise<Policy> {
  const head = await branchHead(config);
  if (policyCache !== null && policyCache.head === head) {
    return policyCache.policy;
  }
  const file = await readFile(config, POLICY_PATH);
  const policy = Policy.parse(file.text);
  policyCache = { policy, head };
  return policy;
}

function repoConfig(env: Env): RepoConfig {
  for (const [name, value] of [
    ['CONTENT_OWNER', env.CONTENT_OWNER],
    ['CONTENT_REPO', env.CONTENT_REPO],
    ['GITHUB_TOKEN', env.GITHUB_TOKEN],
  ] as const) {
    if (typeof value !== 'string' || value.length === 0) {
      // Refusing loudly beats running with a hole in it.
      throw new ConfigError(`${name} is not configured`);
    }
  }
  return {
    owner: env.CONTENT_OWNER,
    repo: env.CONTENT_REPO,
    branch: env.CONTENT_BRANCH || 'main',
    token: env.GITHUB_TOKEN,
  };
}

function requireVerified(env: Env): boolean {
  return (env.REQUIRE_VERIFIED_EMAIL ?? 'true') !== 'false';
}

class ConfigError extends Error {}

// --------------------------------------------------------------------------
// HTTP
// --------------------------------------------------------------------------

function splitOrigins(env: Env): string[] {
  return (env.ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
}

/**
 * CORS, allowing only the origins named in configuration.
 *
 * Never `*`: this API answers with private material and accepts writes, and a
 * wildcard would let any page a signed-in user visits read their repository
 * with their token.
 */
function corsHeaders(origin: string | null, env: Env): Record<string, string> {
  const allowed = splitOrigins(env);
  const base: Record<string, string> = {
    vary: 'Origin',
    'access-control-allow-methods': 'GET, PUT, OPTIONS',
    'access-control-allow-headers': 'authorization, content-type',
    'access-control-max-age': '86400',
  };
  if (origin !== null && allowed.includes(origin)) {
    base['access-control-allow-origin'] = origin;
  }
  return base;
}

function withHeaders(
  response: Response,
  extra: Record<string, string>,
): Response {
  const merged = new Response(response.body, response);
  for (const [name, value] of Object.entries(extra)) {
    merged.headers.set(name, value);
  }
  return merged;
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      // Answers depend on who is asking, so no shared cache may keep them.
      'cache-control': 'private, no-store',
    },
  });
}

function problem(status: number, detail: string): Response {
  return json({ error: detail, status }, status);
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  const type = request.headers.get('content-type') ?? '';
  if (!type.includes('application/json')) {
    throw new BadRequest('body must be application/json');
  }
  let parsed: unknown;
  try {
    parsed = await request.json();
  } catch {
    throw new BadRequest('body is not valid JSON');
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    throw new BadRequest('body must be a JSON object');
  }
  return parsed as Record<string, unknown>;
}

class BadRequest extends Error {}

/**
 * Turns an error into a response.
 *
 * Each branch decides what the client is told. The rule: enough to act on,
 * never enough to probe with, and never anything derived from the GitHub
 * token.
 */
function errorResponse(error: unknown): Response {
  if (error instanceof AuthError) {
    return problem(401, error.clientMessage);
  }
  if (error instanceof PolicyError) {
    // A repository whose policy will not parse must refuse everything. Saying
    // so plainly is the only way anyone will fix it.
    return problem(503, `the repository's access.json is not usable: ${error.message}`);
  }
  if (error instanceof GitHubError) {
    return problem(error.status, error.message);
  }
  if (error instanceof BadRequest) {
    return problem(400, error.message);
  }
  if (error instanceof ConfigError) {
    return problem(503, error.message);
  }
  // Anything unexpected: nothing about it goes to the client, because we do
  // not know what it contains.
  console.error('unhandled', error);
  return problem(500, 'unexpected error');
}
