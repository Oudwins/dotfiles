---
name: publish-artifact
description: Publish an HTML page, report or other file at a URL the user can open, and list, pull, or follow comments on published artifacts. Use when the user asks to publish, share, host or upload an artifact, to list or download one, to read or watch its comments, or when a visual report would be easier to read in a browser than in the terminal.
---

# Publish artifact

Use the `artifact` CLI. This machine's Nix config picks its backend: `s3`
(an artifacts site) or `claude` (Claude Artifacts on claude.ai). Use the
default; set `ARTIFACT_BACKEND=s3|claude` only if the user asks for the other
one. It never falls back from one backend to the other.

```bash
# A directory: every file is uploaded, hidden files are skipped, relative
# paths are kept, and the URL serves its index.html.
artifact publish ./report

# A single file: on s3 the URL points at the file itself; on claude it must
# be an HTML page.
artifact publish ./summary.html

# Update an artifact in place and keep its URL: pass its ID or URL.
artifact publish -id https://.../report-1a2b3c4d/ ./report

# Artifacts from every machine (on claude: yours and ones shared with you).
artifact list
artifact list -json

# Download the original files, keeping directories. DEST must be new or empty.
artifact pull <id-or-url> ./dest

# claude only: comment threads (open ones; -all adds resolved ones), with
# author, text, time, thread ID and what each is attached to.
artifact comments list <id-or-url> [-all] [-json]

# claude only: print new versions, comments (and whether they were sent to
# Claude) and resolved threads as they happen. -count N exits after N events;
# -no-comments watches versions only; -json prints one object per line.
artifact watch <id-or-url> [-interval 30] [-count N] [-no-comments] [-json]
```

`artifact publish` prints the URL on stdout; give it to the user as is.
Diagnostics go to stderr.

- Make pages self-contained: inline CSS and JS or keep assets in the same
  directory, and link them with relative paths.
- Artifacts are visible to everyone who can reach them: anyone with the URL
  on s3, the user's whole organization on claude. Don't publish secrets,
  credentials or private data the user hasn't asked to share.
- There is no delete command. Republish with `-id` to replace files.
- `-id` only takes an ID or URL you were given, never one you make up;
  publish without it to start a new artifact.
- `watch` only reports. It never pulls, republishes, replies or starts
  anything; act on events only as the user asks.

## s3

- The CLI holds no credentials. Never look for or ask for an upload token.
- Files are deleted about six months after they were last published;
  republishing with `-id` keeps an artifact longer. Don't use artifacts as
  permanent storage.
- `comments` and `watch` fail with "not supported".

## claude

- A directory needs a top-level `index.html`. Claude serves only common web
  file types (HTML, CSS, JS, JSON, text, images, fonts, audio, video, PDF,
  WASM), at most 255 files and 15 MB per publish; the CLI names the file
  that breaks a limit.
- Every publish is shared with the user's organization, with comment
  access. If sharing fails, the artifact still exists: the URL is printed
  and the command fails. Retry with the `publish -id <url> <path>` command
  it prints, which doesn't create a second artifact.
- `Could not upload. Please log in to Claude using: artifact -claude-login`
  means the user must log in. Tell them to run `artifact -claude-login`
  themselves; it opens a browser. Never run it for them, and never read or
  ask for its credentials.
