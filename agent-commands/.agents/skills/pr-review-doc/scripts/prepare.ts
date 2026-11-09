// Usage: bun prepare.ts <pr-url> --repo <checkout-dir>
// Writes <workdir>/pr.json with the PR metadata and its diff split into
// hunks, then prints the workdir and a hunk listing for the tab authors.
import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import type { File, Hunk, Line, Pr } from "./schema";

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { repo: { type: "string", default: "." } },
});
const [prUrl] = positionals;
const match = prUrl?.match(/github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)/);
if (!match) throw new Error("Usage: bun prepare.ts <github pr url> --repo <checkout dir>");
const [, owner, repo, number] = match;
const repoDir = resolve(values.repo);

function run(cmd: string[]) {
  const proc = Bun.spawnSync(cmd, { cwd: repoDir });
  if (proc.exitCode !== 0) throw new Error(`${cmd.join(" ")}\n${proc.stderr.toString()}`);
  return proc.stdout.toString();
}

const view = JSON.parse(
  run([
    "gh", "pr", "view", prUrl, "--json",
    "title,url,body,author,baseRefName,headRefName,baseRefOid,headRefOid,additions,deletions",
  ]),
);
for (const oid of [view.baseRefOid, view.headRefOid]) {
  if (Bun.spawnSync(["git", "cat-file", "-e", `${oid}^{commit}`], { cwd: repoDir }).exitCode !== 0) {
    throw new Error(`Commit ${oid} is missing in ${repoDir}; fetch the PR's base and head first.`);
  }
}
// GitHub diffs a PR against the merge base, so line numbers match its threads.
const mergeBaseOid = run(["git", "merge-base", view.baseRefOid, view.headRefOid]).trim();

const pr: Pr = {
  owner, repo, number: Number(number),
  url: view.url, title: view.title, body: view.body, author: view.author.login,
  baseRefName: view.baseRefName, headRefName: view.headRefName,
  headOid: view.headRefOid, mergeBaseOid,
  additions: view.additions, deletions: view.deletions, repoDir,
};

const diff = run([
  "git", "-c", "core.quotePath=false", "diff", "--no-color", "--no-ext-diff", "--find-renames", "-U3",
  mergeBaseOid, view.headRefOid,
]);

const files: File[] = [];
const hunks: Hunk[] = [];
let file: File | undefined;
let hunk: Hunk | undefined;
let oldLine = 0;
let newLine = 0;
for (const text of diff.split("\n")) {
  if (text.startsWith("diff --git ")) {
    const [, a, b] = text.match(/^diff --git a\/(.*) b\/(.*)$/) ?? [];
    file = { path: b, oldPath: a, status: "modified", binary: false, hunks: [] };
    files.push(file);
    hunk = undefined;
  } else if (!file) {
    continue;
  } else if (!hunk) {
    if (text.startsWith("new file mode")) file.status = "added";
    else if (text.startsWith("deleted file mode")) file.status = "deleted";
    else if (text.startsWith("rename from ")) { file.oldPath = text.slice(12); file.status = "renamed"; }
    else if (text.startsWith("rename to ")) file.path = text.slice(10);
    else if (text.startsWith("Binary files ")) file.binary = true;
  }
  const header = text.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@ ?(.*)$/);
  if (file && header) {
    oldLine = Number(header[1]);
    newLine = Number(header[2]);
    hunk = { id: `h${hunks.length + 1}`, path: file.path, header: text, context: header[3], lines: [] };
    hunks.push(hunk);
    file.hunks.push(hunk.id);
  } else if (hunk && /^[ +-]/.test(text)) {
    const line: Line =
      text[0] === "+" ? { t: "+", n: newLine++, text: text.slice(1) }
      : text[0] === "-" ? { t: "-", o: oldLine++, text: text.slice(1) }
      : { t: " ", o: oldLine++, n: newLine++, text: text.slice(1) };
    hunk.lines.push(line);
  }
}

const workdir = join(homedir(), ".cache", "pr-review", owner, repo, number);
mkdirSync(join(workdir, "tabs"), { recursive: true });
await Bun.write(join(workdir, "pr.json"), JSON.stringify({ pr, files, hunks }, null, 2));

console.log(`workdir: ${workdir}\n`);
for (const f of files) {
  const lines = f.hunks.flatMap((id) => hunks.find((h) => h.id === id)!.lines);
  const added = lines.filter((l) => l.t === "+").length;
  const removed = lines.filter((l) => l.t === "-").length;
  const from = f.status === "renamed" ? ` (from ${f.oldPath})` : "";
  console.log(`${f.path}${from} [${f.status}${f.binary ? ", binary" : ""}] +${added} -${removed}`);
  for (const id of f.hunks) {
    const h = hunks.find((h) => h.id === id)!;
    console.log(`  ${h.id}\t${h.header}`);
  }
}
