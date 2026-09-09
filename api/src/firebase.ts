/**
 * Verifying a Firebase ID token.
 *
 * The Worker trusts nothing the browser says about who it is. It takes the
 * `Authorization: Bearer <id token>` header, checks the signature against
 * Google's published keys, and only then believes the email inside.
 *
 * Done here rather than with the Firebase Admin SDK because that SDK needs
 * Node built-ins and a service-account private key. A Worker has neither, and
 * verifying an RS256 JWT is a few hundred lines of well-understood work with
 * WebCrypto -- whereas a service-account key in a Worker secret would be a far
 * more valuable thing to leak than what it protects.
 *
 * Every check below exists because skipping it is a known way in:
 *
 * - **`alg` must be RS256.** A token declaring `alg: none` is otherwise
 *   accepted with no signature at all. This is the classic JWT break.
 * - **The key must come from the `kid` in the header, and that key must be in
 *   Google's set.** Otherwise an attacker signs with their own key and names
 *   it.
 * - **`iss` and `aud` must name this project.** Otherwise a token minted by
 *   any other Firebase project in the world is accepted.
 * - **`exp` must be in the future and `iat` not in the future.** Otherwise an
 *   old token works forever.
 * - **`sub` must be non-empty.** Firebase guarantees it; a token without one
 *   is not one of theirs.
 *
 * What it does *not* do, and what that means: it does not check whether the
 * account was disabled or the password changed since the token was minted.
 * Firebase tokens last an hour, so that is the window. Closing it needs a call
 * to Google's admin API on every request, which costs a round trip per request
 * to shorten a one-hour window -- worth doing if these permissions ever guard
 * something that cannot wait an hour, and not before.
 */

/** Google's public keys for Firebase ID tokens, as a JWK set. */
const JWK_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

/** Allow a little clock skew in both directions. */
const CLOCK_SKEW_SECONDS = 60;

export interface VerifiedIdentity {
  /** Firebase's stable user id. Stable across email changes. */
  uid: string;
  /** May be absent: a Firebase account does not have to have one. */
  email: string | null;
  /** Whether Firebase considers the address proven. */
  emailVerified: boolean;
  name: string | null;
  /** When this token expires, as a Unix timestamp. */
  expiresAt: number;
}

export class AuthError extends Error {
  constructor(
    message: string,
    /** What to tell the client. Deliberately vaguer than `message`, which
     *  goes to the log: "why exactly your token failed" is a probing aid. */
    readonly clientMessage = 'invalid or expired credentials',
  ) {
    super(message);
  }
}

interface Jwk {
  kid?: string;
  kty?: string;
  alg?: string;
  n?: string;
  e?: string;
  use?: string;
}

/**
 * Caches Google's keys for as long as their `Cache-Control` allows.
 *
 * Not in a module-level variable that assumes it survives: a Worker isolate is
 * recycled whenever the platform likes, so this is a best-effort cache and the
 * miss path has to be correct on its own.
 */
export class KeyStore {
  private keys = new Map<string, CryptoKey>();
  private expiresAt = 0;

  constructor(
    private readonly url: string = JWK_URL,
    /**
     * Resolved when it is used, not captured now. A default of `fetch` binds
     * whatever the global was at construction, and this store is built at
     * module scope -- so it would hold a stale reference for the life of the
     * isolate, which is both untestable and the kind of module-level capture
     * that misbehaves in a Worker.
     */
    private readonly fetcher?: typeof fetch,
    private readonly now: () => number = () => Date.now() / 1000,
  ) {}

  async keyFor(kid: string): Promise<CryptoKey> {
    if (this.now() >= this.expiresAt) {
      await this.refresh();
    }
    const key = this.keys.get(kid);
    if (key !== undefined) return key;

    // An unknown `kid` may simply mean Google rotated keys since the last
    // fetch, so refresh once before refusing -- but only once, so a token
    // naming a nonsense kid cannot make us hammer Google.
    await this.refresh();
    const retried = this.keys.get(kid);
    if (retried === undefined) {
      throw new AuthError(`token names an unknown signing key: ${kid}`);
    }
    return retried;
  }

  private async refresh(): Promise<void> {
    const request = this.fetcher ?? fetch;
    const response = await request(this.url, {
      // Google's keys are public and change rarely; letting the platform
      // cache them is what keeps this off the hot path.
      cf: { cacheTtl: 3600, cacheEverything: true },
    } as RequestInit);
    if (!response.ok) {
      throw new AuthError(
        `could not fetch Google's signing keys: HTTP ${response.status}`,
        'could not verify credentials right now',
      );
    }

    const body = (await response.json()) as { keys?: Jwk[] };
    if (!Array.isArray(body.keys)) {
      throw new AuthError("Google's key set has no `keys` array");
    }

    const imported = new Map<string, CryptoKey>();
    for (const jwk of body.keys) {
      // Only RSA keys for RS256 signatures. Anything else in the set is not
      // something we are willing to verify with.
      if (jwk.kty !== 'RSA' || typeof jwk.kid !== 'string') continue;
      if (jwk.alg !== undefined && jwk.alg !== 'RS256') continue;
      try {
        imported.set(
          jwk.kid,
          await crypto.subtle.importKey(
            'jwk',
            { kty: 'RSA', n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
            { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
            false,
            ['verify'],
          ),
        );
      } catch {
        // One unusable key must not poison the rest of the set.
        continue;
      }
    }

    if (imported.size === 0) {
      throw new AuthError("Google's key set contained no usable RSA keys");
    }

    this.keys = imported;
    this.expiresAt =
      this.now() + parseMaxAge(response.headers.get('cache-control'), 3600);
  }
}

/** Seconds from a `Cache-Control` header, clamped to something sane. */
export function parseMaxAge(header: string | null, fallback: number): number {
  if (header === null) return fallback;
  const match = /max-age\s*=\s*(\d+)/i.exec(header);
  if (match === null) return fallback;
  const seconds = Number(match[1]);
  if (!Number.isFinite(seconds)) return fallback;
  // Never cache for more than a day, so a rotation is picked up even if
  // Google says otherwise; never for less than a minute, so a short header
  // cannot turn every request into a fetch.
  return Math.min(Math.max(seconds, 60), 86_400);
}

/**
 * Verifies a Firebase ID token and returns who it says the caller is.
 *
 * @param token the raw JWT, without the `Bearer ` prefix
 * @param projectId the Firebase project this API belongs to
 */
export async function verifyIdToken(
  token: string,
  projectId: string,
  keys: KeyStore,
  now: () => number = () => Date.now() / 1000,
): Promise<VerifiedIdentity> {
  if (projectId.length === 0) {
    // A misconfigured Worker must refuse everything rather than accept
    // everything, which is what an empty expected audience would do.
    throw new AuthError('the Worker has no FIREBASE_PROJECT_ID configured',
      'the service is misconfigured');
  }

  const parts = token.split('.');
  if (parts.length !== 3) {
    throw new AuthError('token is not a three-part JWT');
  }
  const [headerPart, payloadPart, signaturePart] = parts as [
    string,
    string,
    string,
  ];

  const header = decodeJson(headerPart, 'header') as {
    alg?: unknown;
    kid?: unknown;
    typ?: unknown;
  };

  // The classic break: a token declaring `alg: none` carries no signature,
  // and a verifier that reads the algorithm from the token accepts it.
  if (header.alg !== 'RS256') {
    throw new AuthError(`token algorithm is ${String(header.alg)}, not RS256`);
  }
  if (typeof header.kid !== 'string' || header.kid.length === 0) {
    throw new AuthError('token header has no kid');
  }

  const key = await keys.keyFor(header.kid);

  const signature = base64UrlToBytes(signaturePart);
  const signed = new TextEncoder().encode(`${headerPart}.${payloadPart}`);
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    signature,
    signed,
  );
  if (!valid) {
    throw new AuthError('token signature does not verify');
  }

  const payload = decodeJson(payloadPart, 'payload') as Record<string, unknown>;

  const issuer = `https://securetoken.google.com/${projectId}`;
  if (payload.iss !== issuer) {
    throw new AuthError(
      `token issuer is ${String(payload.iss)}, expected ${issuer}`,
    );
  }
  // Without this, a token minted by any other Firebase project verifies here.
  if (payload.aud !== projectId) {
    throw new AuthError(
      `token audience is ${String(payload.aud)}, expected ${projectId}`,
    );
  }

  const seconds = now();
  const exp = numberClaim(payload.exp, 'exp');
  if (exp + CLOCK_SKEW_SECONDS < seconds) {
    throw new AuthError('token has expired', 'credentials have expired');
  }
  const iat = numberClaim(payload.iat, 'iat');
  if (iat - CLOCK_SKEW_SECONDS > seconds) {
    throw new AuthError('token was issued in the future');
  }
  // `auth_time` is when the user actually authenticated. A token claiming a
  // future authentication is not one Firebase minted.
  if (payload.auth_time !== undefined) {
    const authTime = numberClaim(payload.auth_time, 'auth_time');
    if (authTime - CLOCK_SKEW_SECONDS > seconds) {
      throw new AuthError('token claims a future auth_time');
    }
  }

  const sub = payload.sub;
  if (typeof sub !== 'string' || sub.length === 0) {
    throw new AuthError('token has no sub');
  }

  const email = typeof payload.email === 'string' ? payload.email : null;
  return {
    uid: sub,
    email,
    emailVerified: payload.email_verified === true,
    name: typeof payload.name === 'string' ? payload.name : null,
    expiresAt: exp,
  };
}

/** Pulls the token out of an `Authorization` header, or null. */
export function bearerToken(header: string | null): string | null {
  if (header === null) return null;
  const match = /^Bearer\s+(\S+)$/i.exec(header.trim());
  return match === null ? null : (match[1] as string);
}

function numberClaim(value: unknown, name: string): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new AuthError(`token claim ${name} is not a number`);
  }
  return value;
}

function decodeJson(part: string, what: string): unknown {
  try {
    const text = new TextDecoder().decode(base64UrlToBytes(part));
    return JSON.parse(text);
  } catch (error) {
    throw new AuthError(`token ${what} is not valid JSON: ${String(error)}`);
  }
}

/** base64url, which is not what `atob` expects. */
export function base64UrlToBytes(value: string): Uint8Array {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded + '='.repeat((4 - (padded.length % 4)) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}
