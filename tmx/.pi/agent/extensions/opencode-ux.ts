import {
  CustomEditor,
  type AppKeybinding,
  type ExtensionAPI,
  type ExtensionCommandContext,
  type ExtensionContext,
  type KeybindingsManager,
  type Theme,
} from "@earendil-works/pi-coding-agent";
import {
  Input,
  matchesKey,
  truncateToWidth,
  type Component,
  type EditorTheme,
  type Focusable,
  type KeyId,
  type TUI,
} from "@earendil-works/pi-tui";

const LEADER_TIMEOUT_MS = 2000;
const LEADER_STATUS = "opencode-leader";
const INTERNAL_COMMANDS = new Set(["opencode-undo", "opencode-redo"]);

type RecentModel = {
  provider: string;
  id: string;
};

type EditorCallbacks = {
  cycleRecentModel: (direction: 1 | -1) => Promise<boolean>;
};

type Action = {
  key?: KeyId;
  title: string;
  category: string;
  run: () => void | Promise<void>;
};

export default function opencodeUx(pi: ExtensionAPI) {
  let editor: OpenCodeEditor | undefined;
  let redoTargetId: string | undefined;
  const recentModels: RecentModel[] = [];

  const rememberModel = (model: RecentModel) => {
    const index = recentModels.findIndex(
      (candidate) => candidate.provider === model.provider && candidate.id === model.id,
    );
    if (index !== -1) recentModels.splice(index, 1);
    recentModels.unshift(model);
  };

  const cycleRecentModel = async (direction: 1 | -1, ctx: ExtensionContext) => {
    if (recentModels.length < 2) return false;

    for (let offset = 1; offset < recentModels.length; offset++) {
      const index = (direction * offset + recentModels.length) % recentModels.length;
      const recent = recentModels[index];
      const model = ctx.modelRegistry.find(recent.provider, recent.id);
      if (model && await pi.setModel(model)) return true;
    }

    return false;
  };

  pi.registerCommand("opencode-undo", {
    description: "Undo the latest conversation turn",
    handler: async (_args, ctx) => undoConversation(ctx),
  });

  pi.registerCommand("opencode-redo", {
    description: "Redo the conversation turn most recently undone",
    handler: async (_args, ctx) => redoConversation(ctx),
  });

  pi.on("input", (event) => {
    if (event.source === "interactive") redoTargetId = undefined;
  });

  pi.on("model_select", (event) => {
    rememberModel({ provider: event.model.provider, id: event.model.id });
  });

  pi.on("session_start", (_event, ctx) => {
    recentModels.length = 0;
    for (const entry of ctx.sessionManager.getEntries()) {
      if (entry.type === "model_change") {
        rememberModel({ provider: entry.provider, id: entry.modelId });
      }
    }
    if (ctx.model) rememberModel({ provider: ctx.model.provider, id: ctx.model.id });

    ctx.ui.setEditorComponent((tui, theme, keybindings) => {
      editor = new OpenCodeEditor(tui, theme, keybindings, ctx, pi, {
        cycleRecentModel: (direction) => cycleRecentModel(direction, ctx),
      });
      return editor;
    });
  });

  pi.on("session_shutdown", () => {
    editor?.dispose();
    editor = undefined;
  });

  async function undoConversation(ctx: ExtensionCommandContext) {
    if (!ctx.isIdle()) {
      ctx.ui.notify("Wait for the current response to finish before undoing", "warning");
      return;
    }

    const branch = ctx.sessionManager.getBranch();
    const userIndex = branch.findLastIndex(
      (entry) => entry.type === "message" && entry.message.role === "user",
    );
    if (userIndex <= 0) {
      ctx.ui.notify("There is no conversation turn to undo", "warning");
      return;
    }

    const userEntry = branch[userIndex];
    const target = branch[userIndex - 1];
    const prompt = userEntry.type === "message" && "content" in userEntry.message
      ? getUserText(userEntry.message.content)
      : "";
    redoTargetId = ctx.sessionManager.getLeafId() ?? undefined;

    const result = await ctx.navigateTree(target.id, { summarize: false });
    if (result.cancelled) {
      redoTargetId = undefined;
      return;
    }

    ctx.ui.setEditorText(prompt);
    ctx.ui.notify("Conversation turn undone; file changes were not reverted", "info");
  }

  async function redoConversation(ctx: ExtensionCommandContext) {
    if (!ctx.isIdle()) {
      ctx.ui.notify("Wait for the current response to finish before redoing", "warning");
      return;
    }
    if (!redoTargetId || !ctx.sessionManager.getEntry(redoTargetId)) {
      ctx.ui.notify("There is no conversation turn to redo", "warning");
      return;
    }

    const targetId = redoTargetId;
    const result = await ctx.navigateTree(targetId, { summarize: false });
    if (result.cancelled) return;

    redoTargetId = undefined;
    ctx.ui.setEditorText("");
    ctx.ui.notify("Conversation turn restored", "info");
  }
}

class OpenCodeEditor extends CustomEditor {
  private leaderPending = false;
  private leaderTimer?: ReturnType<typeof setTimeout>;
  private paletteOpen = false;
  private modelCycling = false;

  constructor(
    tui: TUI,
    theme: EditorTheme,
    keybindings: ConstructorParameters<typeof CustomEditor>[2],
    private ctx: ExtensionContext,
    private pi: ExtensionAPI,
    private callbacks: EditorCallbacks,
  ) {
    super(tui, theme, keybindings);
  }

  override handleInput(data: string) {
    if (this.leaderPending) {
      this.handleLeaderInput(data);
      return;
    }

    if (matchesKey(data, "ctrl+x")) {
      this.beginLeader();
      return;
    }
    if (matchesKey(data, "ctrl+p")) {
      void this.openPalette();
      return;
    }
    if (matchesKey(data, "f2")) {
      void this.cycleModel(1);
      return;
    }
    if (matchesKey(data, "shift+f2")) {
      void this.cycleModel(-1);
      return;
    }
    if (matchesKey(data, "ctrl+t")) {
      this.runAppAction("app.thinking.cycle");
      return;
    }

    super.handleInput(data);
  }

  dispose() {
    this.cancelLeader();
  }

  private beginLeader() {
    this.cancelLeader();
    this.leaderPending = true;
    this.ctx.ui.setStatus(LEADER_STATUS, "Ctrl+X: n new · l sessions · g tree · m models · c compact · q quit");
    this.leaderTimer = setTimeout(() => this.cancelLeader(), LEADER_TIMEOUT_MS);
  }

  private cancelLeader() {
    this.leaderPending = false;
    if (this.leaderTimer) clearTimeout(this.leaderTimer);
    this.leaderTimer = undefined;
    this.ctx.ui.setStatus(LEADER_STATUS, undefined);
  }

  private handleLeaderInput(data: string) {
    if (matchesKey(data, "escape") || matchesKey(data, "backspace") || matchesKey(data, "ctrl+x")) {
      this.cancelLeader();
      return;
    }

    const action = this.getActions().find((candidate) => candidate.key && matchesKey(data, candidate.key));
    this.cancelLeader();
    if (!action) {
      this.ctx.ui.notify("Unknown Ctrl+X binding", "warning");
      return;
    }
    void this.run(action);
  }

  private getActions(): Action[] {
    return [
      { key: "e", title: "Open external editor", category: "Editor", run: () => this.runAppAction("app.editor.external") },
      { key: "t", title: "Select theme", category: "Application", run: () => this.openThemePicker() },
      { key: "s", title: "Show session status", category: "Session", run: () => this.submitSlash("/session") },
      { key: "x", title: "Export session", category: "Session", run: () => this.submitSlash("/export") },
      { key: "n", title: "New session", category: "Session", run: () => this.runAppAction("app.session.new") },
      { key: "l", title: "List sessions", category: "Session", run: () => this.runAppAction("app.session.resume") },
      { key: "g", title: "Show session tree", category: "Session", run: () => this.runAppAction("app.session.tree") },
      { key: "c", title: "Compact session", category: "Session", run: () => this.ctx.compact() },
      { key: "m", title: "Select model", category: "Model", run: () => this.runAppAction("app.model.select") },
      { key: "y", title: "Copy last assistant message", category: "Messages", run: () => this.runAppAction("app.message.copy") },
      { key: "u", title: "Undo conversation turn", category: "Messages", run: () => this.submitSlash("/opencode-undo") },
      { key: "r", title: "Redo conversation turn", category: "Messages", run: () => this.submitSlash("/opencode-redo") },
      { key: "h", title: "Toggle tool details", category: "Messages", run: () => this.runAppAction("app.tools.expand") },
      { key: "q", title: "Quit", category: "Application", run: () => this.ctx.shutdown() },
    ];
  }

  private async openPalette() {
    if (this.paletteOpen) return;
    this.paletteOpen = true;

    try {
      const actions = [
        ...this.getActions(),
        { title: "Toggle thinking visibility", category: "Messages", run: () => this.runAppAction("app.thinking.toggle") },
        { title: "Settings", category: "Application", run: () => this.submitSlash("/settings") },
        { title: "Keyboard shortcuts", category: "Application", run: () => this.submitSlash("/hotkeys") },
        { title: "Reload", category: "Application", run: () => this.submitSlash("/reload") },
        { title: "Share session", category: "Session", run: () => this.submitSlash("/share") },
        ...this.pi.getCommands()
          .filter((command) => !INTERNAL_COMMANDS.has(command.name))
          .map((command) => ({
            title: `/${command.name}`,
            category: command.source === "extension" ? "Commands" : command.source === "skill" ? "Skills" : "Prompts",
            run: () => this.submitSlash(`/${command.name}`),
          })),
      ];
      const index = await this.ctx.ui.custom<number | undefined>((tui, theme, keybindings, done) =>
        new SearchableCommandPalette(
          actions,
          theme,
          keybindings,
          () => tui.requestRender(),
          done,
        ),
      );
      if (index !== undefined) await this.run(actions[index]);
    } finally {
      this.paletteOpen = false;
    }
  }

  private async openThemePicker() {
    const themes = this.ctx.ui.getAllThemes();
    const selected = await this.ctx.ui.select("Themes", themes.map((theme) => theme.name));
    if (!selected) return;

    const result = this.ctx.ui.setTheme(selected);
    if (!result.success) this.ctx.ui.notify(result.error ?? `Could not load theme ${selected}`, "error");
  }

  private async cycleModel(direction: 1 | -1) {
    if (this.modelCycling) return;
    this.modelCycling = true;
    try {
      if (!await this.callbacks.cycleRecentModel(direction)) {
        this.runAppAction(direction === 1 ? "app.model.cycleForward" : "app.model.cycleBackward");
      }
    } finally {
      this.modelCycling = false;
    }
  }

  private runAppAction(action: AppKeybinding) {
    const handler = this.actionHandlers.get(action);
    if (handler) handler();
    else this.ctx.ui.notify(`Action unavailable: ${action}`, "warning");
  }

  private submitSlash(command: string) {
    this.setText(command);
    super.handleInput("\r");
  }

  private async run(action: Action) {
    try {
      await action.run();
    } catch (error) {
      this.ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
    }
  }
}

class SearchableCommandPalette implements Component, Focusable {
  private input = new Input();
  private filtered: Array<{ action: Action; index: number }>;
  private selectedIndex = 0;
  private readonly maxVisible = 16;

  constructor(
    private actions: Action[],
    private theme: Theme,
    private keybindings: KeybindingsManager,
    private requestRender: () => void,
    private done: (index: number | undefined) => void,
  ) {
    this.filtered = actions.map((action, index) => ({ action, index }));
  }

  get focused() {
    return this.input.focused;
  }

  set focused(value: boolean) {
    this.input.focused = value;
  }

  handleInput(data: string) {
    if (this.keybindings.matches(data, "tui.select.cancel")) {
      this.done(undefined);
      return;
    }
    if (this.keybindings.matches(data, "tui.select.confirm")) {
      const selected = this.filtered[this.selectedIndex];
      if (selected) this.done(selected.index);
      return;
    }
    if (this.keybindings.matches(data, "tui.select.up")) {
      this.moveSelection(-1);
      return;
    }
    if (this.keybindings.matches(data, "tui.select.down")) {
      this.moveSelection(1);
      return;
    }
    if (this.keybindings.matches(data, "tui.select.pageUp")) {
      this.moveSelection(-this.maxVisible);
      return;
    }
    if (this.keybindings.matches(data, "tui.select.pageDown")) {
      this.moveSelection(this.maxVisible);
      return;
    }
    if (matchesKey(data, "home")) {
      this.selectedIndex = 0;
      this.requestRender();
      return;
    }
    if (matchesKey(data, "end")) {
      this.selectedIndex = Math.max(0, this.filtered.length - 1);
      this.requestRender();
      return;
    }

    const previous = this.input.getValue();
    this.input.handleInput(data);
    if (this.input.getValue() !== previous) this.filter(this.input.getValue());
    this.requestRender();
  }

  render(width: number) {
    const title = this.theme.fg("accent", this.theme.bold("Commands"));
    const hint = this.theme.fg("dim", "type to search · ↑↓ select · enter run · esc close");
    const lines = [truncateToWidth(`${title}  ${hint}`, width), ...this.input.render(width), ""];

    if (this.filtered.length === 0) {
      lines.push(this.theme.fg("warning", "  No matching commands"));
      return lines;
    }

    const start = Math.max(
      0,
      Math.min(
        this.selectedIndex - Math.floor(this.maxVisible / 2),
        this.filtered.length - this.maxVisible,
      ),
    );
    const end = Math.min(start + this.maxVisible, this.filtered.length);

    for (let index = start; index < end; index++) {
      const entry = this.filtered[index];
      const prefix = index === this.selectedIndex ? "→ " : "  ";
      const category = this.theme.fg("dim", `${entry.action.category}: `);
      const titleText = index === this.selectedIndex
        ? this.theme.fg("accent", entry.action.title)
        : entry.action.title;
      lines.push(truncateToWidth(`${prefix}${category}${titleText}`, width));
    }

    if (start > 0 || end < this.filtered.length) {
      lines.push(this.theme.fg("dim", `  (${this.selectedIndex + 1}/${this.filtered.length})`));
    }
    return lines;
  }

  invalidate() {
    this.input.invalidate();
  }

  private moveSelection(delta: number) {
    if (this.filtered.length === 0) return;
    this.selectedIndex = (
      this.selectedIndex + delta % this.filtered.length + this.filtered.length
    ) % this.filtered.length;
    this.requestRender();
  }

  private filter(query: string) {
    const normalized = query.trim().toLowerCase();
    this.filtered = this.actions
      .map((action, index) => ({ action, index, score: fuzzyScore(normalized, `${action.title} ${action.category}`) }))
      .filter((entry) => entry.score !== undefined)
      .sort((left, right) => left.score! - right.score! || left.index - right.index)
      .map(({ action, index }) => ({ action, index }));
    this.selectedIndex = 0;
  }
}

function fuzzyScore(query: string, candidate: string) {
  if (!query) return 0;

  const text = candidate.toLowerCase();
  const substring = text.indexOf(query);
  if (substring !== -1) return substring;

  let cursor = -1;
  let score = 0;
  for (const character of query.replaceAll(" ", "")) {
    const next = text.indexOf(character, cursor + 1);
    if (next === -1) return undefined;
    score += next - cursor - 1;
    cursor = next;
  }
  return score + 100;
}

function getUserText(content: unknown) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";

  return content
    .filter((part) => typeof part === "object" && part !== null && "type" in part && part.type === "text")
    .map((part) => "text" in part && typeof part.text === "string" ? part.text : "")
    .join("\n");
}
