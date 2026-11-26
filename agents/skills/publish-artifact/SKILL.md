---
name: publish-artifact
description: Publish an HTML page, report or other file at a URL the user can open. Use when the user asks to publish, share, host or upload an artifact, or when a visual report would be easier to read in a browser than in the terminal.
---

# Publish artifact

Use the `artifact` CLI. If `command -v artifact` finds nothing, this machine
has no artifact backend; say so instead of hosting the file another way.

```bash
# A directory: every file is uploaded, hidden files are skipped, and the
# printed URL serves its index.html.
artifact publish ./report

# A single file: the URL points at the file itself.
artifact publish ./summary.html

# Update an artifact in place: reuse the ID from its URL.
artifact publish -id report-1a2b3c4d ./report
```

`artifact publish` prints the URL on stdout; give it to the user as is.

- Make pages self-contained: inline CSS and JS or keep assets in the same
  directory, and link them with relative paths.
- The CLI holds no credentials. Never look for or ask for an upload token.
- Artifacts are visible to anyone who can reach the URL. Don't publish
  secrets, credentials or private data the user hasn't asked to share.
- There is no listing or delete command. Republish with `-id` to replace a file.
- Files are deleted about six months after they were last published;
  republishing with `-id` keeps an artifact longer. Don't use artifacts as
  permanent storage.
