/**
 * The access policy.
 *
 * Lives in the content repository as `access.json`, not in a provider's
 * console. That is the whole point: a permission change is then a commit --
 * reviewable, attributable, revertible -- instead of a click nobody can audit
 * afterwards.
 *
 * Shape:
 *
 * ```json
 * {
 *   "version": 1,
 *   "roles": {
 *     "owner":      { "read": ["**"], "write": ["**"], "admin": true },
 *     "translator": { "read": ["**"], "write": ["content/**\/{va,en}.tex"] }
 *   },
 *   "users": [
 *     { "email": "someone@uv.es", "role": "owner" },
 *     { "email": "other@uv.es",   "role": "translator" }
 *   ],
 *   "public": { "read": ["generated/**"] }
 * }
 * ```
 *
 * Three rules it enforces, each because the opposite is a way to leak
 * material:
 *
 * **Deny by default.** A user with no entry gets nothing. A role with no
 * `write` list cannot write. There is no wildcard that appears when a field is
 * missing.
 *
 * **Write implies nothing about read.** They are separate lists, so a rule
 * that grants writing `va.tex` does not thereby grant reading everything else.
 *
 * **A malformed policy denies rather than opens.** If the file will not parse,
 * the Worker refuses every authenticated request and says so, instead of
 * falling back to permissive defaults. A policy nobody can parse is not a
 * policy.
 */

import { GlobSet, normalisePath } from './glob';

export type Action = 'read' | 'write';

export interface PolicyRole {
  read: GlobSet;
  write: GlobSet;
  /** May read the policy itself and list who has access. */
  admin: boolean;
}

export interface PolicyDecision {
  allowed: boolean;
  /** Why, for the log and for the 403 body. A refusal that says nothing is
   *  impossible to debug and impossible to trust. */
  reason: string;
  role?: string;
}

export class PolicyError extends Error {}

/** The version of `access.json` this code understands. */
export const POLICY_VERSION = 1;

export class Policy {
  private constructor(
    private readonly roles: Map<string, PolicyRole>,
    private readonly users: Map<string, string>,
    private readonly publicRead: GlobSet,
    readonly raw: unknown,
  ) {}

  /**
   * Parses a policy document. Throws [PolicyError] on anything it does not
   * fully understand -- including an unknown version, because a field that
   * changed meaning is worse than a file that fails to load.
   */
  static parse(text: string): Policy {
    let document: unknown;
    try {
      document = JSON.parse(text);
    } catch (error) {
      throw new PolicyError(`access.json is not valid JSON: ${String(error)}`);
    }
    if (typeof document !== 'object' || document === null) {
      throw new PolicyError('access.json must be an object');
    }
    const object = document as Record<string, unknown>;

    if (object.version !== POLICY_VERSION) {
      throw new PolicyError(
        `access.json is version ${String(object.version)}; this API understands ` +
          `${POLICY_VERSION}`,
      );
    }

    const roles = new Map<string, PolicyRole>();
    const rolesRaw = object.roles;
    if (typeof rolesRaw !== 'object' || rolesRaw === null) {
      throw new PolicyError('access.json needs a `roles` object');
    }
    for (const [name, value] of Object.entries(
      rolesRaw as Record<string, unknown>,
    )) {
      if (typeof value !== 'object' || value === null) {
        throw new PolicyError(`role ${name} must be an object`);
      }
      const role = value as Record<string, unknown>;
      roles.set(name, {
        // Absent means empty, and empty matches nothing. This is where "deny
        // by default" actually lives.
        read: new GlobSet(stringArray(role.read, `roles.${name}.read`)),
        write: new GlobSet(stringArray(role.write, `roles.${name}.write`)),
        admin: role.admin === true,
      });
    }

    const users = new Map<string, string>();
    const usersRaw = object.users;
    if (!Array.isArray(usersRaw)) {
      throw new PolicyError('access.json needs a `users` array');
    }
    for (const entry of usersRaw) {
      if (typeof entry !== 'object' || entry === null) {
        throw new PolicyError('every entry of `users` must be an object');
      }
      const user = entry as Record<string, unknown>;
      const email = user.email;
      const role = user.role;
      if (typeof email !== 'string' || email.length === 0) {
        throw new PolicyError('a user entry has no `email`');
      }
      if (typeof role !== 'string' || !roles.has(role)) {
        throw new PolicyError(
          `user ${email} has role ${String(role)}, which is not defined`,
        );
      }
      // Lower-cased on both sides: an address is not case-sensitive in
      // practice, and a policy that grants `Javier@uv.es` must not be
      // sidestepped by signing in as `javier@uv.es`.
      users.set(email.toLowerCase(), role);
    }

    const publicRaw = object.public;
    let publicRead: string[] = [];
    if (publicRaw !== undefined) {
      if (typeof publicRaw !== 'object' || publicRaw === null) {
        throw new PolicyError('`public` must be an object');
      }
      publicRead = stringArray(
        (publicRaw as Record<string, unknown>).read,
        'public.read',
      );
    }

    return new Policy(roles, users, new GlobSet(publicRead), document);
  }

  get roleNames(): string[] {
    return [...this.roles.keys()].sort();
  }

  get userCount(): number {
    return this.users.size;
  }

  roleFor(email: string | null): string | null {
    if (email === null) return null;
    return this.users.get(email.toLowerCase()) ?? null;
  }

  isAdmin(email: string | null): boolean {
    const role = this.roleFor(email);
    return role !== null && (this.roles.get(role)?.admin ?? false);
  }

  /**
   * Whether anyone at all -- signed in or not -- may read this path.
   *
   * Exists so the generated catalogue of public material can be served without
   * a login, which is what keeps a plain GitHub Pages deployment possible.
   */
  isPublic(path: string): boolean {
    return this.publicRead.matches(path);
  }

  /** The decision, with its reason. */
  can(email: string | null, action: Action, path: string): PolicyDecision {
    const normalised = normalisePath(path);
    if (normalised === null) {
      return { allowed: false, reason: `not a usable path: ${path}` };
    }

    if (action === 'read' && this.publicRead.matches(normalised)) {
      return { allowed: true, reason: 'public' };
    }

    if (email === null) {
      return { allowed: false, reason: 'not signed in' };
    }

    const roleName = this.roleFor(email);
    if (roleName === null) {
      // Deliberately says the address is not in the policy: the alternative
      // is a user who cannot tell "I am not allowed" from "the service is
      // broken", and the fact is not a secret from the person it concerns.
      return {
        allowed: false,
        reason: `${email} is not in access.json`,
      };
    }

    const role = this.roles.get(roleName);
    if (role === undefined) {
      return { allowed: false, reason: `role ${roleName} is not defined` };
    }

    const set = action === 'write' ? role.write : role.read;
    if (set.matches(normalised)) {
      return { allowed: true, reason: `role ${roleName}`, role: roleName };
    }
    return {
      allowed: false,
      reason: `role ${roleName} may not ${action} ${normalised}`,
      role: roleName,
    };
  }

  /** What to tell a signed-in client about itself, for `GET /v1/me`. */
  describeUser(email: string | null): {
    email: string | null;
    role: string | null;
    admin: boolean;
  } {
    return {
      email,
      role: this.roleFor(email),
      admin: this.isAdmin(email),
    };
  }
}

function stringArray(value: unknown, where: string): string[] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) {
    throw new PolicyError(`${where} must be an array of patterns`);
  }
  return value.map((item) => {
    if (typeof item !== 'string' || item.length === 0) {
      throw new PolicyError(`${where} contains something that is not a pattern`);
    }
    return item;
  });
}
