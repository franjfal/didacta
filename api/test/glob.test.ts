/**
 * The path matcher is the base of the permission model, so it is tested for
 * what it must *refuse* at least as hard as for what it allows.
 */
import { describe, expect, it } from 'vitest';

import { compileGlob, GlobSet, normalisePath } from '../src/glob';

describe('compileGlob', () => {
  const matches = (pattern: string, path: string) =>
    compileGlob(pattern).test(path);

  it('matches a literal path', () => {
    expect(matches('content/a/b/es.tex', 'content/a/b/es.tex')).toBe(true);
    expect(matches('content/a/b/es.tex', 'content/a/b/va.tex')).toBe(false);
  });

  it('* does not cross a slash', () => {
    // The rule the whole model rests on. If `*` crossed `/`, a policy meant
    // to grant one directory would grant its entire tree.
    expect(matches('content/*', 'content/analysis')).toBe(true);
    expect(matches('content/*', 'content/analysis/normed')).toBe(false);
    expect(matches('content/*/es.tex', 'content/a/es.tex')).toBe(true);
    expect(matches('content/*/es.tex', 'content/a/b/es.tex')).toBe(false);
  });

  it('** crosses slashes', () => {
    expect(matches('content/**', 'content/a')).toBe(true);
    expect(matches('content/**', 'content/a/b/c/es.tex')).toBe(true);
    expect(matches('**', 'anything/at/all')).toBe(true);
  });

  it('**/ also matches with nothing in between', () => {
    // `content/**/es.tex` demanding an intermediate directory is never what
    // someone writing it means.
    expect(matches('content/**/es.tex', 'content/es.tex')).toBe(true);
    expect(matches('content/**/es.tex', 'content/a/es.tex')).toBe(true);
    expect(matches('content/**/es.tex', 'content/a/b/c/es.tex')).toBe(true);
    expect(matches('content/**/es.tex', 'problems/a/es.tex')).toBe(false);
  });

  it('{a,b} matches one alternative', () => {
    const pattern = 'content/**/{va,en}.tex';
    expect(matches(pattern, 'content/a/b/va.tex')).toBe(true);
    expect(matches(pattern, 'content/a/b/en.tex')).toBe(true);
    // The point of the translator role: the original is not writable.
    expect(matches(pattern, 'content/a/b/es.tex')).toBe(false);
  });

  it('? matches one character but not a slash', () => {
    expect(matches('content/a?c', 'content/abc')).toBe(true);
    expect(matches('content/a?c', 'content/ac')).toBe(false);
    expect(matches('a?c', 'a/c')).toBe(false);
  });

  it('a dot in a pattern means a dot', () => {
    // Not "any character": a pattern comes from a file in a repository and
    // must not be able to smuggle in regex of its own.
    expect(matches('content/es.tex', 'content/esXtex')).toBe(false);
    expect(matches('content/es.tex', 'content/es.tex')).toBe(true);
  });

  it('regex metacharacters are literal', () => {
    for (const [pattern, path] of [
      ['a+b', 'a+b'],
      ['a(b)c', 'a(b)c'],
      ['a|b', 'a|b'],
      ['a[b]c', 'a[b]c'],
      ['a$b', 'a$b'],
      ['a^b', 'a^b'],
    ] as const) {
      expect(matches(pattern, path)).toBe(true);
    }
    // And they do not act as regex: `a+b` must not match `aab`.
    expect(matches('a+b', 'aab')).toBe(false);
    expect(matches('a|b', 'a')).toBe(false);
  });

  it('anchors at both ends', () => {
    // An unanchored pattern would make `content/a` grant `xcontent/ay`.
    expect(matches('content/a', 'xcontent/a')).toBe(false);
    expect(matches('content/a', 'content/ax')).toBe(false);
  });

  it('refuses a pattern it cannot represent', () => {
    // Loud at load time beats loose at request time.
    expect(() => compileGlob('')).toThrow();
    expect(() => compileGlob('content/{va,en')).toThrow(/unbalanced \{/);
    expect(() => compileGlob('content/va}')).toThrow(/unbalanced \}/);
    expect(() => compileGlob('content/\0')).toThrow(/null byte/);
  });
});

describe('normalisePath', () => {
  it('strips leading and trailing slashes', () => {
    expect(normalisePath('/content/a/')).toBe('content/a');
    expect(normalisePath('content/a')).toBe('content/a');
  });

  it('rejects traversal rather than resolving it', () => {
    // `content/../../etc/passwd` is not a mistake to be helpfully corrected.
    expect(normalisePath('content/../secret')).toBeNull();
    expect(normalisePath('../secret')).toBeNull();
    expect(normalisePath('content/./a')).toBeNull();
    expect(normalisePath('..')).toBeNull();
  });

  it('rejects empty segments', () => {
    expect(normalisePath('content//a')).toBeNull();
    expect(normalisePath('')).toBeNull();
    expect(normalisePath('/')).toBeNull();
  });

  it('rejects null bytes and backslashes', () => {
    expect(normalisePath('content/a\0b')).toBeNull();
    // A backslash is not a separator here, and treating it as content would
    // let a Windows-style path slip past a pattern written with `/`.
    expect(normalisePath('content\\a')).toBeNull();
  });

  it('rejects an absurdly long path', () => {
    expect(normalisePath('a/'.repeat(600))).toBeNull();
  });
});

describe('GlobSet', () => {
  it('an empty set matches nothing', () => {
    // What makes "no rule" mean "no access".
    const set = new GlobSet([]);
    expect(set.size).toBe(0);
    expect(set.matches('content/a')).toBe(false);
    expect(set.matches('**')).toBe(false);
  });

  it('matches when any pattern matches', () => {
    const set = new GlobSet(['content/**', 'problems/**']);
    expect(set.matches('content/a/b')).toBe(true);
    expect(set.matches('problems/a/b')).toBe(true);
    expect(set.matches('courses/a/b')).toBe(false);
  });

  it('normalises before matching', () => {
    const set = new GlobSet(['content/**']);
    expect(set.matches('/content/a/')).toBe(true);
  });

  it('a traversal attempt never matches, whatever the patterns say', () => {
    const set = new GlobSet(['**']);
    expect(set.matches('../../etc/passwd')).toBe(false);
    expect(set.matches('content/../../../etc/passwd')).toBe(false);
  });
});
