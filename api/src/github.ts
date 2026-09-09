/**
 * The authenticated GitHub layer.
 *
 * Holds the token a browser cannot. Two constraints shape everything here:
 *
 * **The caller never names the repository.** Owner, repo and branch come from
 * the Worker's own configuration, never from the request. A proxy that takes
 * them from the caller is an open proxy to every repository the token can
 * reach -- which, for a personal access token, is all of them.
 *
 * **The caller never names an API path.** Only the operations below exist.
 * Forwarding an arbitrary path would hand over the whole GitHub API, including
 * the endpoints that manage keys and collaborators.
 *
 * The token is only ever put into an outgoing `Authorization` header. It is
 * never returned, logged, or included in an error, which is why the error type
 * carries GitHub's status and a message of our own rather than its body
 * verbatim.
 */

export interface RepoConfig {
  owner: string;
  repo: string;
  branch: string;
  token: string;
}

export class GitHubError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

export interface FileContent {
  path: string;
  /** UTF-8 text. Binary files are refused rather than mangled. */
  text: string;
  /** GitHub's blob sha, needed to update the file without clobbering. */
  sha: string;
  size: number;
}

const API = 'https://api.github.com';

/**
 * A `User-Agent` is required by the GitHub API, and naming the service means a
 * rate-limit problem can be traced to it rather than to "some Worker".
 */
const USER_AGENT = 'didacta-api';

function headers(config: RepoConfig): HeadersInit {
  return {
    authorization: `Bearer ${config.token}`,
    accept: 'application/vnd.github+json',
    'x-github-api-version': '2022-11-28',
    'user-agent': USER_AGENT,
  };
}

/** Percent-encodes a path for the contents API, keeping the separators. */
function encodePath(path: string): string {
  return path
    .split('/')
    .map((segment) => encodeURIComponent(segment))
    .join('/');
}

export async function readFile(
  config: RepoConfig,
  path: string,
  fetcher: typeof fetch = fetch,
): Promise<FileContent> {
  const url =
    `${API}/repos/${config.owner}/${config.repo}/contents/${encodePath(path)}` +
    `?ref=${encodeURIComponent(config.branch)}`;
  const response = await fetcher(url, { headers: headers(config) });

  if (response.status === 404) {
    throw new GitHubError(`no such file: ${path}`, 404);
  }
  if (!response.ok) {
    throw new GitHubError(
      `GitHub refused to read ${path}`,
      response.status === 401 || response.status === 403 ? 502 : response.status,
    );
  }

  const body = (await response.json()) as {
    type?: string;
    content?: string;
    encoding?: string;
    sha?: string;
    size?: number;
  };

  if (body.type !== 'file') {
    // A directory comes back as an array and a submodule as something else;
    // neither is a file, and pretending otherwise produces nonsense.
    throw new GitHubError(`${path} is not a file`, 400);
  }
  if (body.encoding !== 'base64' || typeof body.content !== 'string') {
    throw new GitHubError(`${path} came back in an unexpected encoding`, 502);
  }

  const bytes = base64ToBytes(body.content);
  let text: string;
  try {
    // `fatal` on purpose: a `.pdf` returned as mojibake would look like a
    // successful read of a corrupt file.
    text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes);
  } catch {
    throw new GitHubError(`${path} is not UTF-8 text`, 415);
  }

  return {
    path,
    text,
    sha: typeof body.sha === 'string' ? body.sha : '',
    size: typeof body.size === 'number' ? body.size : bytes.length,
  };
}

export interface WriteResult {
  path: string;
  sha: string;
  commit: string;
}

export async function writeFile(
  config: RepoConfig,
  options: {
    path: string;
    text: string;
    message: string;
    /** The sha the client last read. Absent means "must not exist yet". */
    sha?: string;
    author?: { name: string; email: string };
  },
  fetcher: typeof fetch = fetch,
): Promise<WriteResult> {
  const url = `${API}/repos/${config.owner}/${config.repo}/contents/${encodePath(
    options.path,
  )}`;

  const payload: Record<string, unknown> = {
    message: options.message,
    content: bytesToBase64(new TextEncoder().encode(options.text)),
    branch: config.branch,
  };
  // Passing the sha is what makes a write a compare-and-set: two people
  // editing the same file get a 409 instead of one silently losing their work.
  if (options.sha !== undefined) payload.sha = options.sha;
  if (options.author !== undefined) {
    payload.author = options.author;
    payload.committer = options.author;
  }

  const response = await fetcher(url, {
    method: 'PUT',
    headers: { ...headers(config), 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });

  if (response.status === 409) {
    throw new GitHubError(
      `${options.path} changed since you read it; re-read and try again`,
      409,
    );
  }
  if (response.status === 422) {
    // GitHub uses 422 both for "sha required" and "sha did not match".
    throw new GitHubError(
      `${options.path} could not be written: it may already exist, or the ` +
        `version you edited is out of date`,
      409,
    );
  }
  if (!response.ok) {
    throw new GitHubError(
      `GitHub refused to write ${options.path}`,
      response.status === 401 || response.status === 403 ? 502 : response.status,
    );
  }

  const body = (await response.json()) as {
    content?: { sha?: string };
    commit?: { sha?: string };
  };
  return {
    path: options.path,
    sha: body.content?.sha ?? '',
    commit: body.commit?.sha ?? '',
  };
}

/** The commit the branch currently points at, for cache validation. */
export async function branchHead(
  config: RepoConfig,
  fetcher: typeof fetch = fetch,
): Promise<string> {
  const url =
    `${API}/repos/${config.owner}/${config.repo}/commits/` +
    `${encodeURIComponent(config.branch)}`;
  const response = await fetcher(url, { headers: headers(config) });
  if (!response.ok) {
    throw new GitHubError(
      `GitHub refused to report the branch head`,
      response.status === 401 || response.status === 403 ? 502 : response.status,
    );
  }
  const body = (await response.json()) as { sha?: string };
  if (typeof body.sha !== 'string') {
    throw new GitHubError('branch head came back without a sha', 502);
  }
  return body.sha;
}

export function base64ToBytes(value: string): Uint8Array {
  // GitHub wraps base64 at 60 characters, and `atob` rejects the newlines.
  const binary = atob(value.replace(/\s+/g, ''));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  // In chunks: `String.fromCharCode(...bytes)` blows the argument limit on
  // anything of a realistic size.
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary);
}
