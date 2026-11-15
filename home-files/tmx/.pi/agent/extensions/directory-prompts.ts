import { promises as fs } from "node:fs";
import path from "node:path";
import os from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type DirectoryPrompt = {
  name: string;
  dir: string;
  promptPath: string;
  description?: string;
  argumentHint?: string;
  source: "global" | "project" | "extra";
};

type Frontmatter = {
  attrs: Record<string, string>;
  body: string;
};

const PROMPT_FILE = "PROMPT.md";
const SKILL_FILE = "SKILL.md";
const PROMPT_FILES = [PROMPT_FILE, SKILL_FILE] as const;
const PROMPT_FILE_NAMES = new Set<string>(PROMPT_FILES);
const COMPANION_LIMIT = 100;
const IGNORED_DIRS = new Set([".git", "node_modules", "dist", "build", "coverage"]);

export default function directoryPrompts(pi: ExtensionAPI) {
  pi.on("resources_discover", async (event, ctx) => {
    const roots = getPromptRoots(event.cwd);
    const nativeNames = await discoverNativePromptNames(roots.map((root) => root.path));
    const prompts = await discoverDirectoryPrompts(roots, nativeNames);

    for (const prompt of prompts) {
      registerDirectoryPrompt(pi, prompt);
    }

    if (prompts.length > 0) {
      ctx.ui.notify(
        `Loaded ${prompts.length} directory prompt${prompts.length === 1 ? "" : "s"}`,
        "info",
      );
    }

    return {};
  });
}

function getPromptRoots(cwd: string): Array<{ path: string; source: DirectoryPrompt["source"] }> {
  const roots: Array<{ path: string; source: DirectoryPrompt["source"] }> = [
    { path: path.join(os.homedir(), ".pi", "agent", "prompts"), source: "global" },
    { path: path.join(cwd, ".pi", "prompts"), source: "project" },
  ];

  const extraRoots = process.env.PI_DIRECTORY_PROMPT_ROOTS
    ?.split(path.delimiter)
    .map((root) => root.trim())
    .filter(Boolean)
    .map((root) => ({ path: expandHome(root), source: "extra" as const })) ?? [];

  return [...roots, ...extraRoots];
}

async function discoverNativePromptNames(roots: string[]): Promise<Set<string>> {
  const names = new Set<string>();

  for (const root of roots) {
    let entries: Array<{ name: string; isFile(): boolean }>;
    try {
      entries = await fs.readdir(root, { withFileTypes: true }) as unknown as Array<{ name: string; isFile(): boolean }>;
    } catch (error) {
      if (isNotFound(error)) continue;
      throw error;
    }

    for (const entry of entries) {
      if (entry.isFile() && entry.name.endsWith(".md")) {
        names.add(path.basename(entry.name, ".md"));
      }
    }
  }

  return names;
}

async function discoverDirectoryPrompts(
  roots: Array<{ path: string; source: DirectoryPrompt["source"] }>,
  nativeNames: Set<string>,
): Promise<DirectoryPrompt[]> {
  const byName = new Map<string, DirectoryPrompt>();
  const collisions = new Set<string>();

  // Project prompts should beat global prompts when both define the same directory prompt.
  const orderedRoots = [...roots].sort((a, b) => sourcePriority(b.source) - sourcePriority(a.source));

  for (const root of orderedRoots) {
    let entries: Array<{ name: string; isDirectory(): boolean }>;
    try {
      entries = await fs.readdir(root.path, { withFileTypes: true }) as unknown as Array<{ name: string; isDirectory(): boolean }>;
    } catch (error) {
      if (isNotFound(error)) continue;
      throw error;
    }

    for (const entry of entries) {
      if (!entry.isDirectory() || entry.name.startsWith(".")) continue;

      const name = entry.name;
      const dir = path.join(root.path, name);
      const promptPath = await findPromptFile(dir);
      if (!promptPath) continue;

      if (nativeNames.has(name)) {
        console.warn(`Skipped directory prompt /${name} because a native prompt /${name} exists.`);
        continue;
      }

      if (byName.has(name)) {
        collisions.add(name);
        continue;
      }

      const { attrs } = parseFrontmatter(await fs.readFile(promptPath, "utf8"));
      byName.set(name, {
        name,
        dir,
        promptPath,
        description: attrs.description,
        argumentHint: attrs["argument-hint"],
        source: root.source,
      });
    }
  }

  for (const name of collisions) {
    console.warn(`Skipped duplicate directory prompt /${name}; using the highest-priority definition.`);
  }

  return [...byName.values()].sort((a, b) => a.name.localeCompare(b.name));
}

async function findPromptFile(dir: string): Promise<string | undefined> {
  for (const file of PROMPT_FILES) {
    const promptPath = path.join(dir, file);
    try {
      const stat = await fs.stat(promptPath);
      if (stat.isFile()) return promptPath;
    } catch (error) {
      if (isNotFound(error)) continue;
      throw error;
    }
  }
  return undefined;
}

function registerDirectoryPrompt(pi: ExtensionAPI, prompt: DirectoryPrompt): void {
  pi.registerCommand(prompt.name, {
    description: prompt.description ?? `Directory prompt from ${prompt.promptPath}`,
    handler: async (args) => {
      const raw = await fs.readFile(prompt.promptPath, "utf8");
      const { body } = parseFrontmatter(raw);
      const argv = splitArgs(args ?? "");
      const expanded = expandArguments(body.trim(), args ?? "", argv);
      const companionFiles = await listCompanionFiles(prompt.dir);
      const message = buildUserMessage(prompt, expanded, args ?? "", companionFiles);

      await Promise.resolve(pi.sendUserMessage(message));
    },
  });
}

function parseFrontmatter(markdown: string): Frontmatter {
  if (!markdown.startsWith("---\n")) return { attrs: {}, body: markdown };

  const end = markdown.indexOf("\n---", 4);
  if (end === -1) return { attrs: {}, body: markdown };

  const raw = markdown.slice(4, end).trim();
  const bodyStart = markdown.indexOf("\n", end + 4);
  const body = bodyStart === -1 ? "" : markdown.slice(bodyStart + 1);
  const attrs: Record<string, string> = {};

  for (const line of raw.split(/\r?\n/)) {
    const match = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!match) continue;
    attrs[match[1]] = unquote(match[2].trim());
  }

  return { attrs, body };
}

function expandArguments(body: string, rawArgs: string, argv: string[]): string {
  return body
    .replace(/\$ARGUMENTS\b/g, rawArgs)
    .replace(/\$@/g, rawArgs)
    .replace(/\$(\d+)\b/g, (_match, index) => argv[Number(index) - 1] ?? "");
}

function splitArgs(args: string): string[] {
  const result: string[] = [];
  let current = "";
  let quote: '"' | "'" | null = null;
  let escaping = false;

  for (const char of args) {
    if (escaping) {
      current += char;
      escaping = false;
      continue;
    }
    if (char === "\\") {
      escaping = true;
      continue;
    }
    if (quote) {
      if (char === quote) quote = null;
      else current += char;
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      continue;
    }
    if (/\s/.test(char)) {
      if (current.length > 0) {
        result.push(current);
        current = "";
      }
      continue;
    }
    current += char;
  }

  if (escaping) current += "\\";
  if (current.length > 0) result.push(current);
  return result;
}

async function listCompanionFiles(dir: string): Promise<string[]> {
  const files: string[] = [];

  async function walk(currentDir: string, prefix = "") {
    if (files.length >= COMPANION_LIMIT) return;

    const entries = await fs.readdir(currentDir, { withFileTypes: true });
    for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      if (files.length >= COMPANION_LIMIT) return;
      if (entry.name.startsWith(".")) continue;
      const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
      const absolute = path.join(currentDir, entry.name);

      if (entry.isDirectory()) {
        if (IGNORED_DIRS.has(entry.name)) continue;
        await walk(absolute, relative);
      } else if (entry.isFile() && !PROMPT_FILE_NAMES.has(entry.name)) {
        files.push(relative);
      }
    }
  }

  await walk(dir);
  return files;
}

function buildUserMessage(prompt: DirectoryPrompt, expandedBody: string, rawArgs: string, companionFiles: string[]): string {
  const companionList = companionFiles.length > 0
    ? companionFiles.map((file) => `- ${file}`).join("\n")
    : "(none)";

  return `<directory-prompt-metadata>\nName: ${prompt.name}\nPrompt file: ${prompt.promptPath}\nPrompt base directory: ${prompt.dir}\nSource: ${prompt.source}\n\nRelative-path rule:\nAny relative file path mentioned by this prompt is relative to the prompt base directory above, not the current working directory.\n\nCompanion-file rule:\nThis prompt may intentionally reference companion files that are not included inline. Use the read tool to load them when the prompt asks for them or when needed.\n\nAvailable companion files:\n${companionList}\n</directory-prompt-metadata>\n\nUser arguments: ${rawArgs}\n\n${expandedBody}`;
}

function sourcePriority(source: DirectoryPrompt["source"]): number {
  if (source === "project") return 3;
  if (source === "extra") return 2;
  return 1;
}

function expandHome(value: string): string {
  if (value === "~") return os.homedir();
  if (value.startsWith(`~${path.sep}`)) return path.join(os.homedir(), value.slice(2));
  return value;
}

function unquote(value: string): string {
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1);
  }
  return value;
}

function isNotFound(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error && (error as { code?: string }).code === "ENOENT";
}
