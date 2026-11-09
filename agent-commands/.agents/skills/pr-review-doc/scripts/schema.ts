import { Marked } from "marked";
import { z } from "zod";

export type Pr = {
  owner: string;
  repo: string;
  number: number;
  url: string;
  title: string;
  body: string;
  author: string;
  baseRefName: string;
  headRefName: string;
  headOid: string;
  mergeBaseOid: string;
  additions: number;
  deletions: number;
  repoDir: string;
};

export type File = {
  path: string;
  oldPath: string;
  status: "added" | "deleted" | "modified" | "renamed";
  binary: boolean;
  hunks: string[];
};

// o and n are the old and new file line numbers.
export type Line = { t: "+" | "-" | " "; o?: number; n?: number; text: string };

export type Hunk = { id: string; path: string; header: string; context: string; lines: Line[] };

export const escapeHtml = (s: string) =>
  s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");

// Raw HTML is escaped because tab text can quote PR content.
const marked = new Marked({ renderer: { html: ({ text }) => escapeHtml(text) } });
const markdown = z
  .string()
  .min(1)
  .transform((text) => marked.parse(text, { async: false }));

const text = z.string().min(1);
const changed = z.enum(["added", "modified", "removed", "unchanged"]);
const severity = z.enum(["high", "medium", "low"]);

// Filled by build.ts before parsing, so code references can be checked and
// resolved against the diff.
export const diff = new Map<string, Hunk>();

// A slice of a hunk, by new-file line numbers (old ones for pure deletions).
// Resolves to indices into the hunk's lines.
const ref = z
  .strictObject({ hunk: z.string(), lines: z.tuple([z.number().int(), z.number().int()]).optional() })
  .transform((value, ctx) => {
    const hunk = diff.get(value.hunk);
    if (!hunk) {
      ctx.addIssue({ code: "custom", message: `unknown hunk ${value.hunk}` });
      return z.NEVER;
    }
    if (!value.lines) return { hunk: value.hunk, from: 0, to: hunk.lines.length - 1 };
    const [start, end] = value.lines;
    const pick = (side: "n" | "o") =>
      hunk.lines.flatMap((line, i) => (line[side] != null && line[side] >= start && line[side] <= end ? [i] : []));
    const picked = pick("n").length ? pick("n") : pick("o");
    if (!picked.length) {
      ctx.addIssue({ code: "custom", message: `lines ${start}-${end} are not in ${value.hunk} (${hunk.header})` });
      return z.NEVER;
    }
    // Take the deletions a picked addition replaces.
    let from = picked[0];
    while (from > 0 && hunk.lines[from - 1].t === "-") from--;
    return { hunk: value.hunk, from, to: picked.at(-1)! };
  });
const refs = z.array(ref).default([]);

const graph = z
  .strictObject({
    summary: markdown.optional(),
    nodes: z
      .array(
        z.strictObject({
          id: text,
          label: text,
          kind: text.optional(),
          group: text.optional(),
          changed,
          description: markdown,
          signature: text.optional(),
          pseudocode: z.array(z.string()).default([]),
          refs,
        }),
      )
      .min(1),
    edges: z.array(z.strictObject({ from: text, to: text, label: text.optional() })).default([]),
  })
  .superRefine(({ nodes, edges }, ctx) => {
    const ids = new Set(nodes.map((node) => node.id));
    if (ids.size !== nodes.length) ctx.addIssue({ code: "custom", message: "node ids must be unique" });
    for (const edge of edges) {
      for (const end of [edge.from, edge.to]) {
        if (!ids.has(end)) ctx.addIssue({ code: "custom", message: `edge refers to unknown node ${end}` });
      }
    }
  });

const findings = <Kind extends z.ZodType>(kind: Kind) =>
  z.strictObject({
    summary: markdown.optional(),
    items: z.array(z.strictObject({ title: text, kind, severity, note: markdown, refs })),
  });

// Tabs in display order. Required tabs must exist; the others appear only
// when their JSON file exists. Tabs without items are left out. The
// Pseudocode tab is built from review.json, after the Review tab.
export const tabs = [
  {
    id: "at-a-glance",
    title: "At a glance",
    required: true,
    schema: z.strictObject({
      tldr: markdown,
      problem: markdown,
    }),
  },
  {
    id: "review",
    title: "Review",
    required: true,
    schema: z.strictObject({
      sections: z
        .array(
          z.strictObject({
            title: text,
            why: markdown,
            hunks: z.array(z.string().regex(/^h\d+$/)).min(1),
            // Shown in the Pseudocode tab, above the section's hunks.
            pseudocode: z.array(z.string()).default([]),
          }),
        )
        .min(1),
    }),
  },
  { id: "architecture", title: "Architecture", required: false, schema: graph },
  {
    id: "data-model",
    title: "Data model",
    required: false,
    schema: z.strictObject({
      summary: markdown.optional(),
      entities: z
        .array(
          z.strictObject({
            name: text,
            kind: text.optional(),
            changed,
            description: markdown,
            fields: z
              .array(
                z.strictObject({
                  name: text,
                  type: text,
                  previousType: text.optional(),
                  change: changed,
                  note: text.optional(),
                }),
              )
              .default([]),
            usage: markdown.optional(),
            refs,
          }),
        )
        .min(1),
    }),
  },
  { id: "interfaces", title: "Interfaces", required: false, schema: graph },
  {
    id: "code-smells",
    title: "Code smells",
    required: true,
    schema: findings(
      z.enum(["try-catch", "loose-types", "tiny-functions", "data-mapping", "client-fetching", "async-waterfall", "other"]),
    ),
  },
  { id: "performance", title: "Performance", required: false, schema: findings(text.optional()) },
  { id: "risks", title: "Risks", required: true, schema: findings(text.optional()) },
] as const;
