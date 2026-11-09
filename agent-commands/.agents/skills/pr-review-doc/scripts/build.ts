// Usage: bun build.ts <workdir> [--tabs at-a-glance,review]
// Validates the tab JSON in <workdir>/tabs, highlights the diff and writes a
// self-contained <workdir>/index.html.
import { existsSync } from "node:fs";
import { basename, join } from "node:path";
import { parseArgs } from "node:util";
import { bundledLanguagesInfo, createHighlighter, stringifyTokenStyle } from "shiki";
import { z } from "zod";
import { layout } from "./graph";
import { diff, escapeHtml, tabs, type File, type Hunk, type Pr } from "./schema";

const { positionals, values } = parseArgs({ allowPositionals: true, options: { tabs: { type: "string" } } });
const [workdir] = positionals;
if (!workdir) throw new Error("Usage: bun build.ts <workdir> [--tabs a,b]");
const only = values.tabs?.split(",");
const wanted = (id: string) => !only || only.includes(id);
const { pr, files, hunks }: { pr: Pr; files: File[]; hunks: Hunk[] } = await Bun.file(join(workdir, "pr.json")).json();
const hunkIds = new Set(hunks.map((h) => h.id));
for (const hunk of hunks) diff.set(hunk.id, hunk);

const problems: string[] = [];
const built = [];
for (const tab of tabs) {
  // The Pseudocode tab is read from review.json.
  if (!wanted(tab.id) && !(tab.id === "review" && wanted("pseudocode"))) continue;
  const path = join(workdir, "tabs", `${tab.id}.json`);
  if (!existsSync(path)) {
    if (tab.required) problems.push(`${path}: missing required tab`);
    continue;
  }
  const result = tab.schema.safeParse(await Bun.file(path).json());
  if (!result.success) {
    problems.push(`${path}:\n${z.prettifyError(result.error)}`);
    continue;
  }
  if (tab.id === "review") {
    const { sections } = result.data as z.output<(typeof tabs)[1]["schema"]>;
    const placed = sections.flatMap((s) => s.hunks);
    for (const id of placed) if (!hunkIds.has(id)) problems.push(`${path}: unknown hunk ${id}`);
    for (const id of new Set(placed.filter((id, i) => placed.indexOf(id) !== i))) {
      problems.push(`${path}: hunk ${id} is placed more than once`);
    }
    const unplaced = hunks.filter((h) => !placed.includes(h.id)).map((h) => h.id);
    if (unplaced.length) problems.push(`${path}: hunks not placed in any section: ${unplaced.join(", ")}`);
    if (wanted("review")) built.push({ id: tab.id, title: tab.title, data: result.data });
    if (wanted("pseudocode") && sections.some((s) => s.pseudocode.length)) {
      built.push({ id: "pseudocode", title: "Pseudocode", data: result.data });
    }
    continue;
  }
  if ("items" in result.data && !result.data.items.length) {
    console.log(`${tab.id}: no items, so the tab is left out`);
    continue;
  }
  built.push({ id: tab.id, title: tab.title, data: result.data });
}
if (problems.length) {
  console.error(problems.join("\n\n"));
  process.exit(1);
}

const themes = { light: "github-light-default", dark: "github-dark-default" };
const highlighter = await createHighlighter({ themes: Object.values(themes), langs: [] });

function langFor(path: string) {
  const name = basename(path).toLowerCase();
  const ext = name.split(".").pop()!;
  return bundledLanguagesInfo.find((l) => l.id === ext || l.aliases?.includes(ext))?.id;
}

function show(oid: string, path: string) {
  const proc = Bun.spawnSync(["git", "show", `${oid}:${path}`], { cwd: pr.repoDir });
  return proc.exitCode === 0 ? proc.stdout.toString() : "";
}

// Highlights whole files, so constructs spanning hunk boundaries colour
// correctly, and returns the HTML of each line by line number.
async function highlight(code: string, lang: string | undefined) {
  const lines = code.split("\n");
  if (!lang || lines.length > 10_000) return lines.map(escapeHtml);
  await highlighter.loadLanguage(lang as Parameters<typeof highlighter.loadLanguage>[0]);
  return highlighter
    .codeToTokens(code, { lang, themes, defaultColor: false })
    .tokens.map((line) =>
      line.map((t) => `<span style="${stringifyTokenStyle(t.htmlStyle ?? {})}">${escapeHtml(t.content)}</span>`).join(""),
    );
}

// Graph tabs get their layout and highlighted signatures.
const pages = await Promise.all(
  built.map(async (tab) => {
    if (tab.id !== "architecture" && tab.id !== "interfaces") return tab;
    const graph = tab.data as z.output<(typeof tabs)[2]["schema"]>;
    const nodes = await Promise.all(
      graph.nodes.map(async (node) => {
        const path = node.group ?? diff.get(node.refs[0]?.hunk ?? "")?.path ?? "";
        return { ...node, signature: node.signature && (await highlight(node.signature, langFor(path))) };
      }),
    );
    return { ...tab, data: { ...graph, nodes, layout: await layout(graph) } };
  }),
);

const rendered = Object.fromEntries(
  (
    await Promise.all(
      files
        .filter((file) => file.hunks.length)
        .map(async (file) => {
          const lang = langFor(file.path);
          const oldLines = file.status === "added" ? [] : await highlight(show(pr.mergeBaseOid, file.oldPath), lang);
          const newLines = file.status === "deleted" ? [] : await highlight(show(pr.headOid, file.path), lang);
          return file.hunks.map((id) => {
            const hunk = hunks.find((h) => h.id === id)!;
            return [
              id,
              {
                ...hunk,
                // Identifies the hunk's content, so review marks survive
                // rebuilds but not changes.
                key: Bun.hash(hunk.path + JSON.stringify(hunk.lines)).toString(36),
                lines: hunk.lines.map(({ text, ...line }) => ({
                  ...line,
                  html: (line.t === "-" ? oldLines[line.o! - 1] : newLines[line.n! - 1]) ?? escapeHtml(text),
                })),
              },
            ] as const;
          });
        }),
    )
  ).flat(),
);

const { repoDir, mergeBaseOid, body, ...page } = pr;
const data = JSON.stringify({ pr: page, hunks: rendered, tabs: pages }).replaceAll("<", "\\u003c");
const dir = join(import.meta.dir, "..", "template");
const [template, style, script] = await Promise.all(
  ["index.html", "viewer.css", "viewer.js"].map((name) => Bun.file(join(dir, name)).text()),
);
// Data goes in last so diff text can never be mistaken for a placeholder.
await Bun.write(
  join(workdir, "index.html"),
  template
    .replace("/* STYLE */", () => style)
    .replace("/* SCRIPT */", () => script)
    .replace("/* DATA */", () => data),
);
console.log(`http://127.0.0.1:7457/pr/${pr.owner}/${pr.repo}/${pr.number}`);
// elkjs keeps the event loop alive.
process.exit(0);
