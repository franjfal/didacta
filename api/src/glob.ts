/**
 * Path matching for the access policy.
 *
 * This is a security boundary, so it is deliberately small and boring. A
 * pattern either matches a path or it does not; there is no partial credit and
 * no clever fallback. Everything the policy can express is here, and nothing
 * else is:
 *
 *   `*`        one path segment, not crossing `/`
 *   `**`       any number of segments, including none
 *   `{a,b}`    one of the alternatives
 *   `?`        one character, not `/`
 *
 * Written by translating to a regular expression rather than by walking the
 * string, because the translation is short enough to read in one go and the
 * walk was not. Every metacharacter that is not one of the four above is
 * escaped, so a pattern can never inject regex of its own -- the policy comes
 * from a file in a repository, and a `.` in it must mean a dot.
 *
 * The rule that matters most: **`*` does not cross `/`**. Without it,
 * `content/*` would match `content/analysis/normed-spaces/definition/es.tex`
 * and a policy meant to grant one directory would grant a whole tree.
 */

/** Characters that mean something to a regular expression and nothing here. */
const REGEX_SPECIAL = /[.+^$()|[\]\\]/g;

/**
 * Compiles one pattern. Throws on a pattern it cannot represent rather than
 * matching loosely: a policy line nobody can parse must fail loudly at load
 * time, not silently widen at request time.
 */
export function compileGlob(pattern: string): RegExp {
  if (pattern.length === 0) {
    throw new Error('empty pattern');
  }
  if (pattern.includes('\0')) {
    throw new Error(`pattern contains a null byte: ${JSON.stringify(pattern)}`);
  }

  let out = '';
  let depth = 0; // brace nesting, so an unclosed `{` is an error

  for (let i = 0; i < pattern.length; i += 1) {
    // `noUncheckedIndexedAccess` is on, and rightly: an index into a string
    // can be undefined. Inside the loop bounds it cannot be, and asserting
    // that here is clearer than widening the type of everything below.
    const char = pattern[i] as string;

    if (char === '*') {
      if (pattern[i + 1] === '*') {
        // `**` spans segments. Consume any `/` that follows so that
        // `content/**/es.tex` also matches `content/es.tex` -- otherwise the
        // pattern would demand at least one intermediate directory, which is
        // never what someone writing it means.
        i += 1;
        if (pattern[i + 1] === '/') {
          i += 1;
          out += '(?:[^\\0]*\\/)?';
        } else {
          out += '[^\\0]*';
        }
      } else {
        out += '[^\\/]*';
      }
      continue;
    }

    if (char === '?') {
      out += '[^\\/]';
      continue;
    }

    if (char === '{') {
      depth += 1;
      out += '(?:';
      continue;
    }

    if (char === '}') {
      depth -= 1;
      if (depth < 0) {
        throw new Error(`unbalanced } in pattern: ${JSON.stringify(pattern)}`);
      }
      out += ')';
      continue;
    }

    if (char === ',' && depth > 0) {
      out += '|';
      continue;
    }

    if (char === '/') {
      out += '\\/';
      continue;
    }

    out += char.replace(REGEX_SPECIAL, '\\$&');
  }

  if (depth !== 0) {
    throw new Error(`unbalanced { in pattern: ${JSON.stringify(pattern)}`);
  }

  return new RegExp(`^${out}$`);
}

/**
 * Normalises a path before matching.
 *
 * A policy is written against repository paths, so the shapes that mean the
 * same thing have to match the same way -- and the shapes that try to escape
 * the repository have to fail. `..` is rejected rather than resolved: a
 * request for `content/../../etc/passwd` is not a mistake to be helpfully
 * corrected.
 */
export function normalisePath(path: string): string | null {
  if (path.length === 0 || path.length > 1024) return null;
  if (path.includes('\0') || path.includes('\\')) return null;

  const trimmed = path.replace(/^\/+/, '').replace(/\/+$/, '');
  if (trimmed.length === 0) return null;

  const segments = trimmed.split('/');
  for (const segment of segments) {
    if (segment.length === 0) return null; // a `//` somewhere
    if (segment === '.' || segment === '..') return null;
  }
  return segments.join('/');
}

/** A compiled set of patterns, so a policy is parsed once per load. */
export class GlobSet {
  private readonly matchers: RegExp[];

  constructor(patterns: readonly string[]) {
    this.matchers = patterns.map(compileGlob);
  }

  get size(): number {
    return this.matchers.length;
  }

  /**
   * True when any pattern matches. An empty set matches nothing, which is what
   * makes "no rule" mean "no access" rather than "all access".
   */
  matches(path: string): boolean {
    const normalised = normalisePath(path);
    if (normalised === null) return false;
    return this.matchers.some((matcher) => matcher.test(normalised));
  }
}
