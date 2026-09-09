/**
 * The handler, end to end: identity, then policy, then GitHub.
 *
 * The order is the design, so these tests are mostly about proving there is no
 * path to the repository that skips a check. GitHub is stubbed -- what is
 * under test is the gate in front of it, and the stub records whether it was
 * reached at all, which is the assertion that matters.
 */
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

import worker from '../src/index';
import type { Env } from '../src/index';
import { POLICY_VERSION } from '../src/policy';

const PROJECT = 'didacta-test';
const KID = 'handler-key';
const OWNER = 'javier@uv.es';
const TRANSLATOR = 'traductora@uv.es';

let signingKey: CryptoKey;
let jwkSet: unknown;

const POLICY = JSON.stringify({
  version: POLICY_VERSION,
  roles: {
    owner: { read: ['**'], write: ['**'], admin: true },
    translator: { read: ['**'], write: ['content/**/{va,en}.tex'] },
  },
  users: [
    { email: OWNER, role: 'owner' },
    { email: TRANSLATOR, role: 'translator' },
  ],
  public: { read: ['generated/**'] },
});

const env: Env = {
  FIREBASE_PROJECT_ID: PROJECT,
  CONTENT_OWNER: 'franjfal',
  CONTENT_REPO: 'didacta_db',
  CONTENT_BRANCH: 'main',
  ALLOWED_ORIGINS: 'https://didacta.example',
  GITHUB_TOKEN: 'test-token-not-a-real-one',
  REQUIRE_VERIFIED_EMAIL: 'true',
};

/** Every GitHub call the stub saw, so a skipped gate is visible. */
let seen: { url: string; method: string; auth: string | null }[] = [];

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function token(
  email: string | null,
  extra: Record<string, unknown> = {},
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(
    new TextEncoder().encode(
      JSON.stringify({ alg: 'RS256', typ: 'JWT', kid: KID }),
    ),
  );
  const payload = base64Url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: `https://securetoken.google.com/${PROJECT}`,
        aud: PROJECT,
        sub: 'uid-1',
        iat: now - 10,
        exp: now + 3600,
        email_verified: true,
        ...(email === null ? {} : { email }),
        ...extra,
      }),
    ),
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    signingKey,
    new TextEncoder().encode(`${header}.${payload}`),
  );
  return `${header}.${payload}.${base64Url(new Uint8Array(signature))}`;
}

beforeAll(async () => {
  const pair = (await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  )) as CryptoKeyPair;
  signingKey = pair.privateKey;
  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  jwkSet = { keys: [{ ...jwk, kid: KID, alg: 'RS256', use: 'sig' }] };
});

beforeEach(() => {
  seen = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === 'string' ? input : String(input);
      const method = init?.method ?? 'GET';
      const auth =
        init?.headers === undefined
          ? null
          : ((init.headers as Record<string, string>).authorization ?? null);

      if (url.includes('/jwk/')) {
        return new Response(JSON.stringify(jwkSet), {
          status: 200,
          headers: { 'cache-control': 'max-age=3600' },
        });
      }

      seen.push({ url, method, auth });

      if (url.includes('/commits/')) {
        return new Response(JSON.stringify({ sha: 'headsha' }), { status: 200 });
      }
      if (url.includes('/contents/access.json')) {
        return new Response(
          JSON.stringify({
            type: 'file',
            encoding: 'base64',
            content: btoa(POLICY),
            sha: 'policysha',
            size: POLICY.length,
          }),
          { status: 200 },
        );
      }
      if (method === 'PUT') {
        return new Response(
          JSON.stringify({
            content: { sha: 'newsha' },
            commit: { sha: 'commitsha' },
          }),
          { status: 200 },
        );
      }
      const text = 'contenido de la unidad';
      return new Response(
        JSON.stringify({
          type: 'file',
          encoding: 'base64',
          content: btoa(text),
          sha: 'filesha',
          size: text.length,
        }),
        { status: 200 },
      );
    }),
  );
});

async function call(
  path: string,
  options: { auth?: string; method?: string; body?: unknown; origin?: string } = {},
): Promise<Response> {
  const headers: Record<string, string> = {};
  if (options.auth !== undefined) headers.authorization = `Bearer ${options.auth}`;
  if (options.body !== undefined) headers['content-type'] = 'application/json';
  if (options.origin !== undefined) headers.origin = options.origin;
  return worker.fetch(
    new Request(`https://api.example${path}`, {
      method: options.method ?? 'GET',
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    }),
    env,
  );
}

/** GitHub calls that are not the policy load or the head check. */
function contentCalls() {
  return seen.filter(
    (call) => !call.url.includes('access.json') && !call.url.includes('/commits/'),
  );
}

describe('health', () => {
  it('says what is configured without revealing it', async () => {
    const response = await call('/v1/health');
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.githubToken).toBe(true);
    // The value itself must never appear.
    expect(JSON.stringify(body)).not.toContain('test-token-not-a-real-one');
  });

  it('needs no token, so a misconfiguration is diagnosable', async () => {
    expect((await call('/v1/health')).status).toBe(200);
    expect(seen).toHaveLength(0);
  });
});

describe('reading', () => {
  it('a public path needs no login', async () => {
    const response = await call('/v1/file?path=generated/units.json');
    expect(response.status).toBe(200);
  });

  it('a private path without a token is 401, and GitHub is never called', async () => {
    const response = await call('/v1/file?path=content/a/es.tex');
    expect(response.status).toBe(401);
    // The assertion that matters: the gate ran before anything reached the
    // repository.
    expect(contentCalls()).toHaveLength(0);
  });

  it('an address not in the policy is 403, and GitHub is never called', async () => {
    const response = await call('/v1/file?path=content/a/es.tex', {
      auth: await token('desconocida@example.com'),
    });
    expect(response.status).toBe(403);
    expect(contentCalls()).toHaveLength(0);
  });

  it('a forged token is 401, and GitHub is never called', async () => {
    const response = await call('/v1/file?path=content/a/es.tex', {
      auth: 'not.a.token',
    });
    expect(response.status).toBe(401);
    expect(contentCalls()).toHaveLength(0);
  });

  it('an authorised read reaches GitHub with the secret, not the user token', async () => {
    const response = await call('/v1/file?path=content/a/es.tex', {
      auth: await token(OWNER),
    });
    expect(response.status).toBe(200);
    const body = (await response.json()) as { text: string; sha: string };
    expect(body.text).toBe('contenido de la unidad');
    expect(body.sha).toBe('filesha');

    const github = contentCalls();
    expect(github).toHaveLength(1);
    // The Worker's own credential, never the caller's.
    expect(github[0]?.auth).toBe('Bearer test-token-not-a-real-one');
  });

  it('traversal is refused', async () => {
    const response = await call('/v1/file?path=../../etc/passwd', {
      auth: await token(OWNER),
    });
    expect(response.status).toBe(403);
    expect(contentCalls()).toHaveLength(0);
  });

  it('a missing ?path= is a 400, not a crash', async () => {
    expect((await call('/v1/file', { auth: await token(OWNER) })).status).toBe(
      400,
    );
  });
});

describe('writing', () => {
  it('a translator may write a translation', async () => {
    const response = await call('/v1/file', {
      method: 'PUT',
      auth: await token(TRANSLATOR),
      body: { path: 'content/a/va.tex', text: 'nou', sha: 'filesha' },
    });
    expect(response.status).toBe(200);
    expect(contentCalls().some((c) => c.method === 'PUT')).toBe(true);
  });

  it('a translator may not write the original, and GitHub is never called', async () => {
    const response = await call('/v1/file', {
      method: 'PUT',
      auth: await token(TRANSLATOR),
      body: { path: 'content/a/es.tex', text: 'no', sha: 'filesha' },
    });
    expect(response.status).toBe(403);
    expect(contentCalls().filter((c) => c.method === 'PUT')).toHaveLength(0);
  });

  it('a public read grant does not become a write grant', async () => {
    const response = await call('/v1/file', {
      method: 'PUT',
      body: { path: 'generated/units.json', text: '{}' },
    });
    expect(response.status).toBe(401);
    expect(contentCalls().filter((c) => c.method === 'PUT')).toHaveLength(0);
  });

  it('an unverified address may not write', async () => {
    // Firebase mints tokens for unverified addresses, and an unverified
    // address is one anybody can claim.
    const response = await call('/v1/file', {
      method: 'PUT',
      auth: await token(OWNER, { email_verified: false }),
      body: { path: 'content/a/es.tex', text: 'x', sha: 'filesha' },
    });
    expect(response.status).toBe(403);
    expect(contentCalls().filter((c) => c.method === 'PUT')).toHaveLength(0);
  });

  it('the commit is attributed to the signed-in user', async () => {
    // Attribution in git is the audit trail this whole design leans on.
    await call('/v1/file', {
      method: 'PUT',
      auth: await token(OWNER),
      body: { path: 'content/a/es.tex', text: 'x', sha: 'filesha' },
    });
    const put = (fetch as unknown as ReturnType<typeof vi.fn>).mock.calls.find(
      (args: unknown[]) => (args[1] as RequestInit | undefined)?.method === 'PUT',
    );
    const body = JSON.parse((put?.[1] as RequestInit).body as string) as {
      author?: { email?: string };
      message?: string;
    };
    expect(body.author?.email).toBe(OWNER);
    expect(body.message).toContain('content/a/es.tex');
  });

  it('a body that is not JSON is a 400', async () => {
    const response = await worker.fetch(
      new Request('https://api.example/v1/file', {
        method: 'PUT',
        headers: { authorization: `Bearer ${await token(OWNER)}` },
        body: 'not json',
      }),
      env,
    );
    expect(response.status).toBe(400);
  });

  it('a missing text field is a 400', async () => {
    const response = await call('/v1/file', {
      method: 'PUT',
      auth: await token(OWNER),
      body: { path: 'content/a/es.tex' },
    });
    expect(response.status).toBe(400);
  });
});

describe('me', () => {
  it('tells a signed-in user their role', async () => {
    const response = await call('/v1/me', { auth: await token(TRANSLATOR) });
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.signedIn).toBe(true);
    expect(body.role).toBe('translator');
    expect(body.admin).toBe(false);
  });

  it('tells an anonymous caller it is anonymous rather than failing', async () => {
    const body = (await (await call('/v1/me')).json()) as Record<string, unknown>;
    expect(body.signedIn).toBe(false);
    expect(body.role).toBeNull();
  });
});

describe('policy endpoint', () => {
  it('is admin-only, because it is a list of addresses', async () => {
    expect((await call('/v1/policy', { auth: await token(TRANSLATOR) })).status)
      .toBe(403);
    expect((await call('/v1/policy')).status).toBe(403);
    expect((await call('/v1/policy', { auth: await token(OWNER) })).status).toBe(
      200,
    );
  });
});

describe('CORS', () => {
  it('echoes only an allowed origin', async () => {
    const allowed = await call('/v1/health', {
      origin: 'https://didacta.example',
    });
    expect(allowed.headers.get('access-control-allow-origin')).toBe(
      'https://didacta.example',
    );
  });

  it('never answers a wildcard', async () => {
    // A wildcard would let any page a signed-in user visits read their
    // repository.
    const other = await call('/v1/health', { origin: 'https://evil.example' });
    expect(other.headers.get('access-control-allow-origin')).toBeNull();
    expect(other.headers.get('access-control-allow-origin')).not.toBe('*');
  });

  it('answers a preflight', async () => {
    const response = await worker.fetch(
      new Request('https://api.example/v1/file', {
        method: 'OPTIONS',
        headers: { origin: 'https://didacta.example' },
      }),
      env,
    );
    expect(response.status).toBe(204);
    expect(response.headers.get('access-control-allow-methods')).toContain('PUT');
  });
});

describe('configuration', () => {
  it('an unconfigured Worker refuses rather than running with a hole', async () => {
    const response = await worker.fetch(
      new Request('https://api.example/v1/me'),
      { ...env, GITHUB_TOKEN: '' },
    );
    expect(response.status).toBe(503);
  });

  it('a policy that will not parse refuses everything', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.includes('/jwk/')) {
          return new Response(JSON.stringify(jwkSet), { status: 200 });
        }
        if (url.includes('/commits/')) {
          return new Response(JSON.stringify({ sha: 'other' }), { status: 200 });
        }
        return new Response(
          JSON.stringify({
            type: 'file',
            encoding: 'base64',
            content: btoa('{ not valid'),
            sha: 'x',
            size: 11,
          }),
          { status: 200 },
        );
      }),
    );
    const response = await call('/v1/me', { auth: await token(OWNER) });
    expect(response.status).toBe(503);
    expect(await response.text()).toContain('access.json');
  });
});

describe('unknown routes', () => {
  it('are 404, not 500', async () => {
    expect((await call('/v1/whatever')).status).toBe(404);
    expect((await call('/')).status).toBe(404);
  });

  it('an unsupported method on a real route is 405', async () => {
    const response = await call('/v1/file', {
      method: 'DELETE',
      auth: await token(OWNER),
    });
    expect(response.status).toBe(405);
  });
});
