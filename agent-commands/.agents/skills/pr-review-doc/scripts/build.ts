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

// The signature as the page shows it, with each short alias's value beside its
// name, so the layout can size cards for it. Mirrors `inlineValue` in viewer.js.
function withAliasValues(signature: string, definitions: z.output<(typeof tabs)[6]["schema"]>["types"], before = false) {
  return definitions.reduce((code, definition) => {
    const value = (before && definition.previous ? definition.previous : definition).type;
    if (!definition.inline || !value || value.includes("\n") || value.length > 72) return code;
    const name = definition.name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return code.replace(new RegExp(`\\b${name}\\b`, "g"), (match, offset) =>
      /\b(?:type|interface|class)\s+$/.test(code.slice(0, offset)) ? match : `${match} = ${value}`,
    );
  }, signature);
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

// Longest-common-subsequence line diff, removals before additions. Signatures
// are short, so the quadratic table is fine.
function lineDiff(a: string[], b: string[]) {
  const same = (i: number, j: number) => a[i].trimEnd() === b[j].trimEnd();
  const len = Array.from({ length: a.length + 1 }, () => new Array<number>(b.length + 1).fill(0));
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      len[i][j] = same(i, j) ? len[i + 1][j + 1] + 1 : Math.max(len[i + 1][j], len[i][j + 1]);
    }
  }
  const out: { t: "+" | "-" | " "; o?: number; n?: number }[] = [];
  let [i, j] = [0, 0];
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && same(i, j)) out.push({ t: " ", o: i++, n: j++ });
    else if (i < a.length && (j === b.length || len[i + 1][j] >= len[i][j + 1])) out.push({ t: "-", o: i++ });
    else out.push({ t: "+", n: j++ });
  }
  return out;
}

// A node's signature as highlighted lines; with a previous signature, as a
// diff whose lines are marked "+", "-" or " ".
async function signatureLines(signature: string, previous: string | undefined, lang: string | undefined) {
  const after = signature.split("\n");
  const afterHtml = await highlight(signature, lang);
  if (!previous) return after.map((text, n) => ({ text, html: afterHtml[n] }));
  const before = previous.split("\n");
  const beforeHtml = await highlight(previous, lang);
  return lineDiff(before, after).map(({ t, o, n }) =>
    t === "-" ? { t, text: before[o!], html: beforeHtml[o!] } : { t, text: after[n!], html: afterHtml[n!] },
  );
}

// Graph tabs get their layout and highlighted signatures.
const pages = await Promise.all(
  built.map(async (tab) => {
    if (tab.id !== "architecture" && tab.id !== "interfaces") return tab;
    const graph = tab.data as z.output<(typeof tabs)[4]["schema"]>;
    const typeData = tab.id === "interfaces" ? tab.data as z.output<(typeof tabs)[6]["schema"]> : null;
    for (const definition of typeData?.types ?? []) {
      const oid = definition.source.side === "base" ? pr.mergeBaseOid : pr.headOid;
      if (!show(oid, definition.source.path).split("\n")[definition.source.line - 1]) {
        throw new Error(`${definition.id}: type source does not exist at ${oid}:${definition.source.path}:${definition.source.line}`);
      }
    }
    const nodes = await Promise.all(
      graph.nodes.map(async (node) => {
        const path = diff.get(node.refs[0]?.hunk ?? "")?.path ?? node.group ?? "";
        const references = typeData?.nodes.find(candidate => candidate.id === node.id)?.types ?? [];
        const definitions = typeData?.types.filter(type => references.some(ref => ref.id === type.id)) ?? [];
        const lines = node.signature && (await signatureLines(node.signature, node.previousSignature, langFor(path)));
        const sizedLines = lines?.map((line) => ({ ...line, text: withAliasValues(line.text, definitions, "t" in line && line.t === "-") }));
        return { ...node, lines, sizedLines };
      }),
    );
    // Layout sizes cards by the lines they show, signs included.
    const sized = nodes.map((node) => ({
      ...node,
      signature: node.sizedLines?.map((line) => ("t" in line ? `${line.t} ` : "") + line.text).join("\n"),
    }));
    return {
      ...tab,
      data: {
        ...graph,
        nodes: nodes.map(({ lines, sizedLines, previousSignature, ...node }) => ({
          ...node,
          signature: lines?.map(({ text, ...line }) => line),
        })),
        layout: await layout({ ...graph, nodes: sized }),
      },
    };
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
