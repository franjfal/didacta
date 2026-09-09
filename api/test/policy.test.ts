/**
 * The policy decides who sees what, so these tests are mostly about refusal:
 * every way a mistake could widen access rather than narrow it.
 */
import { readFileSync } from 'node:fs';

import { describe, expect, it } from 'vitest';

import { Policy, PolicyError, POLICY_VERSION } from '../src/policy';

const OWNER = 'javier@uv.es';
const TRANSLATOR = 'traductora@uv.es';
const STRANGER = 'nadie@example.com';

const document = JSON.stringify({
  version: POLICY_VERSION,
  roles: {
    owner: { read: ['**'], write: ['**'], admin: true },
    editor: {
      read: ['**'],
      write: ['content/**', 'problems/**', 'courses/**'],
    },
    translator: {
      read: ['**'],
      write: ['content/**/{va,en}.tex', 'problems/**/{va,en}.tex'],
    },
    reader: { read: ['content/**', 'generated/**'] },
  },
  users: [
    { email: OWNER, role: 'owner' },
    { email: TRANSLATOR, role: 'translator' },
    { email: 'lector@uv.es', role: 'reader' },
  ],
  public: { read: ['generated/**'] },
});

const policy = Policy.parse(document);

describe('parsing', () => {
  it('reads roles, users and the public list', () => {
    expect(policy.roleNames).toEqual([
      'editor',
      'owner',
      'reader',
      'translator',
    ]);
    expect(policy.userCount).toBe(3);
  });

  it('refuses an unknown version rather than guessing', () => {
    const other = JSON.stringify({ version: 99, roles: {}, users: [] });
    expect(() => Policy.parse(other)).toThrow(PolicyError);
    expect(() => Policy.parse(other)).toThrow(/version 99/);
  });

  it('refuses a user whose role is not defined', () => {
    // A typo in a role name must not silently become "no permissions" that
    // nobody notices, nor anything else.
    const other = JSON.stringify({
      version: POLICY_VERSION,
      roles: { owner: { read: ['**'] } },
      users: [{ email: 'a@b.c', role: 'ownr' }],
    });
    expect(() => Policy.parse(other)).toThrow(/not defined/);
  });

  it('refuses malformed documents', () => {
    for (const text of [
      'not json',
      '[]',
      JSON.stringify({ version: POLICY_VERSION }),
      JSON.stringify({ version: POLICY_VERSION, roles: {} }),
      JSON.stringify({ version: POLICY_VERSION, roles: {}, users: {} }),
      JSON.stringify({
        version: POLICY_VERSION,
        roles: { r: { read: 'not-an-array' } },
        users: [],
      }),
      JSON.stringify({
        version: POLICY_VERSION,
        roles: { r: { read: [42] } },
        users: [],
      }),
      JSON.stringify({
        version: POLICY_VERSION,
        roles: { r: {} },
        users: [{ role: 'r' }],
      }),
    ]) {
      expect(() => Policy.parse(text), text.slice(0, 40)).toThrow(PolicyError);
    }
  });

  it('refuses a pattern that will not compile', () => {
    const other = JSON.stringify({
      version: POLICY_VERSION,
      roles: { r: { read: ['content/{va,en'] } },
      users: [],
    });
    expect(() => Policy.parse(other)).toThrow();
  });
});

describe('deny by default', () => {
  it('an address not in the policy gets nothing', () => {
    const decision = policy.can(STRANGER, 'read', 'content/a/es.tex');
    expect(decision.allowed).toBe(false);
    expect(decision.reason).toContain('not in access.json');
  });

  it('nobody signed in gets nothing outside the public list', () => {
    expect(policy.can(null, 'read', 'content/a/es.tex').allowed).toBe(false);
    expect(policy.can(null, 'write', 'generated/units.json').allowed).toBe(
      false,
    );
  });

  it('a role with no write list cannot write', () => {
    // `reader` declares only `read`. An absent field must not become a
    // wildcard.
    const decision = policy.can('lector@uv.es', 'write', 'content/a/es.tex');
    expect(decision.allowed).toBe(false);
    expect(decision.role).toBe('reader');
  });

  it('a role with no read list cannot read', () => {
    const other = Policy.parse(
      JSON.stringify({
        version: POLICY_VERSION,
        roles: { writer: { write: ['**'] } },
        users: [{ email: 'w@uv.es', role: 'writer' }],
      }),
    );
    expect(other.can('w@uv.es', 'read', 'content/a').allowed).toBe(false);
    expect(other.can('w@uv.es', 'write', 'content/a').allowed).toBe(true);
  });
});

describe('the translator case', () => {
  it('may write a translation', () => {
    expect(
      policy.can(TRANSLATOR, 'write', 'content/analysis/normed/va.tex').allowed,
    ).toBe(true);
    expect(
      policy.can(TRANSLATOR, 'write', 'problems/analysis/normed/en.tex')
        .allowed,
    ).toBe(true);
  });

  it('may not touch the original', () => {
    // The combination the whole role exists for: create and edit va/en, never
    // the source.
    const decision = policy.can(
      TRANSLATOR,
      'write',
      'content/analysis/normed/es.tex',
    );
    expect(decision.allowed).toBe(false);
    expect(decision.reason).toContain('may not write');
  });

  it('may not write metadata or compositions', () => {
    for (const path of [
      'content/analysis/normed/unit.yaml',
      'courses/am-iii/2025-2026/year.yaml',
      'access.json',
      'didacta.yaml',
    ]) {
      expect(policy.can(TRANSLATOR, 'write', path).allowed, path).toBe(false);
    }
  });

  it('may still read everything', () => {
    expect(policy.can(TRANSLATOR, 'read', 'courses/am-iii/course.yaml').allowed)
      .toBe(true);
  });
});

describe('the editor case', () => {
  it('may write content but not the policy itself', () => {
    expect(policy.can('javier@uv.es', 'write', 'access.json').allowed).toBe(
      true,
    );
    const editor = Policy.parse(
      JSON.stringify({
        version: POLICY_VERSION,
        roles: {
          editor: { read: ['**'], write: ['content/**', 'problems/**'] },
        },
        users: [{ email: 'e@uv.es', role: 'editor' }],
      }),
    );
    expect(editor.can('e@uv.es', 'write', 'content/a/es.tex').allowed).toBe(
      true,
    );
    // Editing the policy is how a user grants themselves anything else, so it
    // has to be a separate permission.
    expect(editor.can('e@uv.es', 'write', 'access.json').allowed).toBe(false);
  });
});

describe('public reads', () => {
  it('the generated catalogue needs no login', () => {
    // What keeps a plain GitHub Pages deployment possible.
    const decision = policy.can(null, 'read', 'generated/units.json');
    expect(decision.allowed).toBe(true);
    expect(decision.reason).toBe('public');
    expect(policy.isPublic('generated/manifest.json')).toBe(true);
  });

  it('content is not public just because the catalogue is', () => {
    expect(policy.isPublic('content/a/es.tex')).toBe(false);
    expect(policy.can(null, 'read', 'content/a/es.tex').allowed).toBe(false);
  });

  it('public applies to reading only', () => {
    expect(policy.can(null, 'write', 'generated/units.json').allowed).toBe(
      false,
    );
  });

  it('a policy with no public list makes nothing public', () => {
    const closed = Policy.parse(
      JSON.stringify({
        version: POLICY_VERSION,
        roles: { owner: { read: ['**'], write: ['**'] } },
        users: [{ email: OWNER, role: 'owner' }],
      }),
    );
    expect(closed.isPublic('generated/units.json')).toBe(false);
    expect(closed.can(null, 'read', 'generated/units.json').allowed).toBe(
      false,
    );
  });
});

describe('addresses', () => {
  it('are matched case-insensitively', () => {
    // A policy granting `Javier@uv.es` must not be sidestepped by signing in
    // as `javier@uv.es`, nor the reverse.
    const mixed = Policy.parse(
      JSON.stringify({
        version: POLICY_VERSION,
        roles: { owner: { read: ['**'], write: ['**'] } },
        users: [{ email: 'Javier@UV.es', role: 'owner' }],
      }),
    );
    expect(mixed.can('javier@uv.es', 'write', 'content/a').allowed).toBe(true);
    expect(mixed.can('JAVIER@uv.ES', 'write', 'content/a').allowed).toBe(true);
  });
});

describe('paths', () => {
  it('traversal is refused for everyone, owner included', () => {
    for (const path of [
      '../secret',
      'content/../../etc/passwd',
      'content//a',
      '',
    ]) {
      const decision = policy.can(OWNER, 'read', path);
      expect(decision.allowed, path).toBe(false);
    }
  });

  it('an owner with ** still cannot escape the repository', () => {
    expect(policy.can(OWNER, 'write', '../../elsewhere').allowed).toBe(false);
  });
});

describe('admin', () => {
  it('only a role marked admin is one', () => {
    expect(policy.isAdmin(OWNER)).toBe(true);
    expect(policy.isAdmin(TRANSLATOR)).toBe(false);
    expect(policy.isAdmin(null)).toBe(false);
    expect(policy.isAdmin(STRANGER)).toBe(false);
  });

  it('describeUser says what a client may assume about itself', () => {
    expect(policy.describeUser(TRANSLATOR)).toEqual({
      email: TRANSLATOR,
      role: 'translator',
      admin: false,
    });
    expect(policy.describeUser(STRANGER)).toEqual({
      email: STRANGER,
      role: null,
      admin: false,
    });
  });
});

describe('reasons', () => {
  it('every refusal says why', () => {
    // A 403 that says nothing is impossible to debug and impossible to trust.
    for (const decision of [
      policy.can(null, 'read', 'content/a'),
      policy.can(STRANGER, 'read', 'content/a'),
      policy.can(TRANSLATOR, 'write', 'content/a/es.tex'),
      policy.can(OWNER, 'read', '../x'),
    ]) {
      expect(decision.allowed).toBe(false);
      expect(decision.reason.length).toBeGreaterThan(4);
    }
  });
});

describe('the shipped example', () => {
  it('parses with the real parser', () => {
    // access.example.json is what someone copies into their content
    // repository. A template that does not load is worse than no template,
    // and its `_comment` keys must be ignored rather than read as roles.
    const text = readFileSync('access.example.json', 'utf8');
    const example = Policy.parse(text);
    expect(example.roleNames).toEqual([
      'editor',
      'owner',
      'reader',
      'translator',
    ]);
    expect(example.userCount).toBe(1);
  });

  it('gives the example owner everything and a stranger nothing', () => {
    const text = readFileSync('access.example.json', 'utf8');
    const example = Policy.parse(text);
    expect(
      example.can('francisco.j.falco@uv.es', 'write', 'access.json').allowed,
    ).toBe(true);
    expect(example.can('nadie@example.com', 'read', 'content/a').allowed).toBe(
      false,
    );
    // And the catalogue is readable without signing in.
    expect(example.can(null, 'read', 'generated/units.json').allowed).toBe(true);
  });
});
