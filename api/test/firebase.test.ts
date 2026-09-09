/**
 * Token verification, tested against real signatures.
 *
 * A real RSA key pair is generated here and tokens are really signed with it,
 * so the signature check is genuinely exercised rather than stubbed. The
 * attacks each test stands for are named: this is the one file where a passing
 * test that does not actually verify anything would be worst.
 */
import { beforeAll, describe, expect, it } from 'vitest';

import {
  AuthError,
  KeyStore,
  bearerToken,
  base64UrlToBytes,
  parseMaxAge,
  verifyIdToken,
} from '../src/firebase';

const PROJECT = 'didacta-test';
const KID = 'test-key-1';

let signingKey: CryptoKey;
let jwkSet: { keys: unknown[] };
/** A second, unrelated pair: the attacker's own key. */
let attackerKey: CryptoKey;

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function encodeJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

async function makeToken(
  claims: Record<string, unknown>,
  options: {
    header?: Record<string, unknown>;
    key?: CryptoKey;
    signature?: string;
  } = {},
): Promise<string> {
  const header = options.header ?? { alg: 'RS256', typ: 'JWT', kid: KID };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT,
    sub: 'uid-123',
    iat: now - 30,
    exp: now + 3600,
    auth_time: now - 30,
    email: 'javier@uv.es',
    email_verified: true,
    ...claims,
  };
  const head = `${encodeJson(header)}.${encodeJson(payload)}`;
  if (options.signature !== undefined) {
    return `${head}.${options.signature}`;
  }
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    options.key ?? signingKey,
    new TextEncoder().encode(head),
  );
  return `${head}.${base64Url(new Uint8Array(signature))}`;
}

/** A KeyStore serving our generated key instead of Google's. */
function storeFor(set: unknown, cacheControl = 'max-age=3600'): KeyStore {
  const fetcher = (async () =>
    new Response(JSON.stringify(set), {
      status: 200,
      headers: { 'cache-control': cacheControl },
    })) as unknown as typeof fetch;
  return new KeyStore('https://example.invalid/jwk', fetcher);
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
  const publicJwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  jwkSet = { keys: [{ ...publicJwk, kid: KID, alg: 'RS256', use: 'sig' }] };

  const other = (await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  )) as CryptoKeyPair;
  attackerKey = other.privateKey;
});

describe('a valid token', () => {
  it('verifies and yields the identity', async () => {
    const identity = await verifyIdToken(
      await makeToken({}),
      PROJECT,
      storeFor(jwkSet),
    );
    expect(identity.uid).toBe('uid-123');
    expect(identity.email).toBe('javier@uv.es');
    expect(identity.emailVerified).toBe(true);
  });

  it('reports an unverified address as unverified', async () => {
    // Whether to require this is the policy's business, but the API must not
    // quietly claim an address is proven when Firebase says it is not.
    const identity = await verifyIdToken(
      await makeToken({ email_verified: false }),
      PROJECT,
      storeFor(jwkSet),
    );
    expect(identity.emailVerified).toBe(false);
  });

  it('tolerates a token with no email at all', async () => {
    const identity = await verifyIdToken(
      await makeToken({ email: undefined }),
      PROJECT,
      storeFor(jwkSet),
    );
    expect(identity.email).toBeNull();
  });
});

describe('signature', () => {
  it('a token signed with another key is refused', async () => {
    // The whole point. Without the signature check, anyone mints identities.
    const token = await makeToken({}, { key: attackerKey });
    await expect(
      verifyIdToken(token, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(/signature does not verify/);
  });

  it('a tampered payload is refused', async () => {
    const token = await makeToken({});
    const [head, , signature] = token.split('.') as [string, string, string];
    const forged = encodeJson({
      iss: `https://securetoken.google.com/${PROJECT}`,
      aud: PROJECT,
      sub: 'uid-123',
      iat: Math.floor(Date.now() / 1000) - 30,
      exp: Math.floor(Date.now() / 1000) + 3600,
      email: 'attacker@example.com',
    });
    await expect(
      verifyIdToken(`${head}.${forged}.${signature}`, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(/signature does not verify/);
  });

  it('an empty signature is refused', async () => {
    const token = await makeToken({}, { signature: '' });
    await expect(
      verifyIdToken(token, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(AuthError);
  });
});

describe('algorithm', () => {
  it('alg: none is refused', async () => {
    // The classic JWT break: a verifier that trusts the token's own
    // declaration accepts an unsigned token.
    const token = await makeToken(
      {},
      { header: { alg: 'none', typ: 'JWT', kid: KID }, signature: '' },
    );
    await expect(
      verifyIdToken(token, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(/algorithm is none/);
  });

  it('HS256 is refused', async () => {
    // Otherwise the public key can be used as an HMAC secret -- the other
    // classic break.
    const token = await makeToken(
      {},
      { header: { alg: 'HS256', typ: 'JWT', kid: KID }, signature: 'x' },
    );
    await expect(
      verifyIdToken(token, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(/not RS256/);
  });

  it('a missing kid is refused', async () => {
    const token = await makeToken({}, { header: { alg: 'RS256', typ: 'JWT' } });
    await expect(
      verifyIdToken(token, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(/no kid/);
  });

  it('an unknown kid is refused after one refresh', async () => {
    const token = await makeToken(
      {},
      { header: { alg: 'RS256', typ: 'JWT', kid: 'not-a-real-key' } },
    );
    await expect(
      verifyIdToken(token, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(/unknown signing key/);
  });
});

describe('issuer and audience', () => {
  it('a token from another Firebase project is refused', async () => {
    // Without this check, any Firebase project in the world can mint
    // identities for this API.
    const token = await makeToken({
      iss: 'https://securetoken.google.com/someone-elses-project',
      aud: 'someone-elses-project',
    });
    await expect(
      verifyIdToken(token, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(/issuer/);
  });

  it('a right issuer with a wrong audience is refused', async () => {
    const token = await makeToken({ aud: 'another-project' });
    await expect(
      verifyIdToken(token, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(/audience/);
  });

  it('an unconfigured project refuses everything', async () => {
    // A misconfigured Worker must not accept every token; an empty expected
    // audience would do exactly that.
    await expect(
      verifyIdToken(await makeToken({}), '', storeFor(jwkSet)),
    ).rejects.toThrow(/misconfigured|FIREBASE_PROJECT_ID/);
  });
});

describe('time', () => {
  it('an expired token is refused', async () => {
    const past = Math.floor(Date.now() / 1000) - 7200;
    const token = await makeToken({ iat: past, exp: past + 3600 });
    await expect(
      verifyIdToken(token, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(/expired/);
  });

  it('a little clock skew is tolerated', async () => {
    // Expired 30 seconds ago: within the allowance, because refusing a
    // just-expired token on a slightly fast clock is a support call.
    const now = Math.floor(Date.now() / 1000);
    const token = await makeToken({ iat: now - 3600, exp: now - 30 });
    const identity = await verifyIdToken(token, PROJECT, storeFor(jwkSet));
    expect(identity.uid).toBe('uid-123');
  });

  it('a token from the future is refused', async () => {
    const future = Math.floor(Date.now() / 1000) + 7200;
    const token = await makeToken({ iat: future, exp: future + 3600 });
    await expect(
      verifyIdToken(token, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(/issued in the future/);
  });

  it('a future auth_time is refused', async () => {
    const now = Math.floor(Date.now() / 1000);
    const token = await makeToken({ auth_time: now + 7200 });
    await expect(
      verifyIdToken(token, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(/auth_time/);
  });

  it('non-numeric time claims are refused', async () => {
    for (const claims of [{ exp: 'soon' }, { iat: null }]) {
      const token = await makeToken(claims);
      await expect(
        verifyIdToken(token, PROJECT, storeFor(jwkSet)),
      ).rejects.toThrow(/not a number/);
    }
  });
});

describe('shape', () => {
  it('a token that is not three parts is refused', async () => {
    for (const bad of ['', 'a', 'a.b', 'a.b.c.d']) {
      await expect(
        verifyIdToken(bad, PROJECT, storeFor(jwkSet)),
      ).rejects.toThrow(AuthError);
    }
  });

  it('a token with no sub is refused', async () => {
    const token = await makeToken({ sub: '' });
    await expect(
      verifyIdToken(token, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(/no sub/);
  });

  it('an unparseable payload is refused', async () => {
    const head = encodeJson({ alg: 'RS256', typ: 'JWT', kid: KID });
    await expect(
      verifyIdToken(`${head}.!!!.sig`, PROJECT, storeFor(jwkSet)),
    ).rejects.toThrow(AuthError);
  });
});

describe('the client message', () => {
  it('is vaguer than the log message', async () => {
    // "Your audience claim was wrong" is a probing aid; the detail belongs in
    // the log, not the response.
    const token = await makeToken({ aud: 'another-project' });
    try {
      await verifyIdToken(token, PROJECT, storeFor(jwkSet));
      expect.unreachable('should have thrown');
    } catch (error) {
      expect(error).toBeInstanceOf(AuthError);
      const auth = error as AuthError;
      expect(auth.message).toContain('audience');
      expect(auth.clientMessage).not.toContain('audience');
    }
  });
});

describe('KeyStore', () => {
  it('refuses a key set with no usable RSA keys', async () => {
    const store = storeFor({ keys: [{ kty: 'EC', kid: 'x' }] });
    await expect(store.keyFor('x')).rejects.toThrow(/no usable RSA keys/);
  });

  it('refuses a key set that is not a key set', async () => {
    await expect(storeFor({ nope: true }).keyFor('x')).rejects.toThrow(
      /no `keys` array/,
    );
  });

  it('surfaces a fetch failure as a service problem, not a bad token', async () => {
    const fetcher = (async () =>
      new Response('nope', { status: 503 })) as unknown as typeof fetch;
    const store = new KeyStore('https://example.invalid/jwk', fetcher);
    try {
      await store.keyFor('x');
      expect.unreachable('should have thrown');
    } catch (error) {
      // The client is told the service could not check, not that their
      // credentials are bad -- they are not.
      expect((error as AuthError).clientMessage).toContain('right now');
    }
  });

  it('fetches once for repeated lookups of a known key', async () => {
    let calls = 0;
    const fetcher = (async () => {
      calls += 1;
      return new Response(JSON.stringify(jwkSet), {
        status: 200,
        headers: { 'cache-control': 'max-age=3600' },
      });
    }) as unknown as typeof fetch;
    const store = new KeyStore('https://example.invalid/jwk', fetcher);
    await store.keyFor(KID);
    await store.keyFor(KID);
    expect(calls).toBe(1);
  });

  it('an unknown kid triggers exactly one extra fetch, not a storm', async () => {
    let calls = 0;
    const fetcher = (async () => {
      calls += 1;
      return new Response(JSON.stringify(jwkSet), {
        status: 200,
        headers: { 'cache-control': 'max-age=3600' },
      });
    }) as unknown as typeof fetch;
    const store = new KeyStore('https://example.invalid/jwk', fetcher);
    await expect(store.keyFor('nope')).rejects.toThrow();
    expect(calls).toBe(2);
  });
});

describe('parseMaxAge', () => {
  it('reads max-age and clamps it', () => {
    expect(parseMaxAge('max-age=1800', 60)).toBe(1800);
    // Never longer than a day, so a rotation is picked up regardless.
    expect(parseMaxAge('max-age=999999', 60)).toBe(86_400);
    // Never shorter than a minute, so a small header cannot turn every
    // request into a key fetch.
    expect(parseMaxAge('max-age=1', 60)).toBe(60);
    expect(parseMaxAge(null, 3600)).toBe(3600);
    expect(parseMaxAge('no-store', 3600)).toBe(3600);
  });
});

describe('bearerToken', () => {
  it('reads a bearer header', () => {
    expect(bearerToken('Bearer abc.def.ghi')).toBe('abc.def.ghi');
    expect(bearerToken('bearer abc')).toBe('abc');
  });

  it('rejects anything else', () => {
    for (const header of [null, '', 'abc', 'Basic abc', 'Bearer', 'Bearer a b']) {
      expect(bearerToken(header)).toBeNull();
    }
  });
});

describe('base64UrlToBytes', () => {
  it('decodes base64url, which atob does not', () => {
    // `-` and `_` instead of `+` and `/`, and no padding.
    const bytes = base64UrlToBytes('SGVsbG8_d29ybGQ-');
    expect(new TextDecoder().decode(bytes)).toBe('Hello?world>');
  });
});
