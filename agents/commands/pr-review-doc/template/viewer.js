const { pr, hunks, tabs } = JSON.parse(document.getElementById("data").textContent);
const api = `/api/pr/${pr.owner}/${pr.repo}/${pr.number}`;
const storageKey = `pr-review-doc:${pr.owner}/${pr.repo}#${pr.number}`;
const saved = JSON.parse(localStorage.getItem(storageKey) ?? "{}");
const reviewed = new Set(saved.reviewed ?? []);
const cursors = saved.cursors ?? {};
// Graph zoom per tab, where 1 is the layout's own size.
const zooms = saved.zooms ?? {};

const $ = (id) => document.getElementById(id);
const main = $("tabs");
const prompt = $("prompt");
const help = $("help");

function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs ?? {})) {
    if (key === "html") el.innerHTML = value;
    else if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
    else el.setAttribute(key, value);
  }
  el.append(...children.flat(Infinity).filter((child) => child != null && child !== false));
  return el;
}

// Links may come from PR text, so only http(s) targets stay clickable.
function safeLinks(el) {
  for (const a of el.querySelectorAll("a")) {
    if (!/^https?:/i.test(a.getAttribute("href") ?? "")) a.removeAttribute("href");
    a.target = "_blank";
    a.rel = "noreferrer";
  }
  return el;
}

function markdown(html, rows = true) {
  const el = safeLinks(h("div", { class: "md", html }));
  if (rows) {
    for (const child of el.children) {
      if (child.matches("ul, ol")) for (const li of child.children) li.classList.add("row");
      else child.classList.add("row");
    }
  }
  return el;
}

// ---------------------------------------------------------------- rendering

// Diff rows by `side:line:path`, where review threads attach. A line shown in
// several tabs gets its threads in each.
const anchors = new Map();
const anchor = (side, line, path) => `${side}:${line}:${path}`;

// A head row whose body za, o and Enter show and hide.
const foldable = (cls, head, body, folded) =>
  h("div", { class: `foldable ${cls}${folded ? " folded" : ""}` }, head, h("div", { class: "body" }, body));

const badge = (text, cls = text) => h("span", { class: `badge ${cls}` }, text);

// Renders a whole hunk, or the slice a code reference resolved to.
function renderHunk(id, { from = 0, to = hunks[id].lines.length - 1, review = false, folded = false } = {}) {
  const hunk = hunks[id];
  const lines = hunk.lines.slice(from, to + 1);
  const numbers = lines.map((line) => line.n ?? line.o);
  const range = lines.length === hunk.lines.length ? "" : `:${numbers[0]}-${numbers.at(-1)}`;
  const el = foldable(
    "hunk",
    h(
      "div",
      { class: "row block hunk-head" },
      h("span", { class: "path" }, hunk.path + range),
      h("span", { class: "context" }, hunk.context),
      h("span", { class: "mark" }),
    ),
    lines.map((line) => {
      const side = line.t === "-" ? "LEFT" : "RIGHT";
      const num = side === "LEFT" ? line.o : line.n;
      const kind = { "+": "add", "-": "del", " ": "ctx" }[line.t];
      const row = h(
        "div",
        { class: `row line ${kind}` },
        h("span", { class: "ln" }, line.o ?? ""),
        h("span", { class: "ln" }, line.n ?? ""),
        h("span", { class: "sign" }, line.t),
        h("span", { class: "code", html: line.html }),
      );
      row.line = { path: hunk.path, side, num };
      row.threads = [];
      const key = anchor(side, num, hunk.path);
      anchors.set(key, [...(anchors.get(key) ?? []), row]);
      return row;
    }),
    folded || (review && reviewed.has(hunk.key)),
  );
  el.hunk = hunk;
  if (reviewed.has(hunk.key)) el.classList.add("reviewed");
  return el;
}

const renderRefs = (refs) => refs.map((ref) => renderHunk(ref.hunk, ref));

// Code the PR doesn't change, folded. Its lines can be yanked but not commented on.
function renderExcerpt({ path, side, start, lines }) {
  const head = h(
    "div",
    { class: "row block excerpt-head" },
    h("span", { class: "path" }, `${path}:${start}-${start + lines.length - 1}`),
    h("span", { class: "context" }, side === "base" ? "unchanged, before this PR" : "unchanged"),
  );
  return foldable(
    "excerpt",
    head,
    lines.map((html, i) => {
      const num = start + i;
      const row = h(
        "div",
        { class: "row line ctx" },
        h("span", { class: "ln" }, side === "base" ? num : ""),
        h("span", { class: "ln" }, side === "base" ? "" : num),
        h("span", { class: "sign" }, " "),
        h("span", { class: "code", html }),
      );
      row.line = { path, side: side === "base" ? "LEFT" : "RIGHT", num, unchanged: true };
      return row;
    }),
    true,
  );
}

// Test files by common conventions: foo.test.ts, foo_test.go, test_foo.py,
// and anything under __tests__/, test/, tests/ or spec/.
const isTest = (path) => /(^|\/)(__tests__|tests?|spec)\/|[._-](test|spec)s?\.[^/]+$|(^|\/)test_[^/]+$/.test(path);

const codeToggle = (refs, folded = true) =>
  refs.length > 0 &&
  foldable("code", h("div", { class: "row code-toggle" }, `Code (${refs.length})`), renderRefs(refs), folded);

const svg = (tag, attrs, ...children) => {
  const el = document.createElementNS("http://www.w3.org/2000/svg", tag);
  for (const [key, value] of Object.entries(attrs ?? {})) el.setAttribute(key, value);
  el.append(...children.flat(Infinity).filter((child) => child != null && child !== false));
  return el;
};

// Shortens a group label (often a file path) from the left to fit its box.
function fit(label, width) {
  const max = Math.floor(width / 7.3);
  return label.length <= max ? label : `…${label.slice(label.length - max + 1)}`;
}

const tierLabels = { "stored-or-wire": "stored / wire", "cross-feature": "cross-feature" };

// A signature line; lines of a before → after signature carry their diff sign.
const signatureLine = (line) =>
  h(
    "div",
    { class: `sig ${{ "+": "add", "-": "del", " ": "ctx" }[line.t] ?? ""}` },
    line.t && h("span", { class: "sign" }, line.t),
    h("span", { html: line.html }),
  );

const typeNamePattern = (names) => new RegExp(`\\b(${names.map(name => name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|")})\\b`, "g");

// A short alias shows its value next to its name; an object type is never inlined.
const inlineValue = (definition, before) => {
  const value = (before && definition.previous ? definition.previous : definition).type;
  return definition.inline && value && !value.includes("\n") && value.length <= 72 ? value : null;
};

// A signature line whose referenced types explain themselves: short aliases
// get their value beside the name, object types link to the inspector.
function typeSignatureLine(line, definitions, open) {
  const row = signatureLine(line);
  if (!definitions.length) return row;
  const pattern = typeNamePattern(definitions.map(type => type.name));
  const walker = document.createTreeWalker(row.lastElementChild, NodeFilter.SHOW_TEXT);
  const texts = [];
  while (walker.nextNode()) texts.push(walker.currentNode);
  let before = "";
  for (const text of texts) {
    const parts = [];
    let start = 0;
    for (const match of text.textContent.matchAll(pattern)) {
      // A declaration's own name (`type Foo =`) is not a reference to explain.
      if (/\b(?:type|interface|class)\s+$/.test(before + text.textContent.slice(0, match.index))) continue;
      const definition = definitions.find(type => type.name === match[0]);
      const value = inlineValue(definition, line.t === "-");
      parts.push(
        text.textContent.slice(start, match.index),
        value
          ? [match[0], h("span", { class: "type-inline" }, ` = ${value}`)]
          : h("button", {
              class: "type-link",
              type: "button",
              title: `Inspect ${definition.name}`,
              onclick: event => { event.stopPropagation(); open(definition.id); },
            }, match[0]),
      );
      start = match.index + match[0].length;
    }
    before += text.textContent;
    if (parts.length) text.replaceWith(...parts.flat(), text.textContent.slice(start));
  }
  return row;
}

// The definitions a contract references, as field trees. Only the branches the
// contract marks relevant start open; every other nested shape is one key away.
function renderTypeTree(references, registry) {
  const sourceLink = definition => h("a", {
    class: "type-source",
    href: `https://github.com/${pr.owner}/${pr.repo}/blob/${definition.source.side === "base" ? pr.mergeBaseOid : pr.headOid}/${definition.source.path.split("/").map(encodeURIComponent).join("/")}#L${definition.source.line}`,
    target: "_blank",
    rel: "noreferrer",
  }, `${definition.source.path}:${definition.source.line}`);
  const fields = (definition, expanded, path = "", ancestors = []) => {
    const before = definition.previous?.fields ?? [];
    const current = definition.fields;
    return [...current, ...before.filter(field => !current.some(next => next.name === field.name))].map(field => {
      const previous = before.find(candidate => candidate.name === field.name);
      const removed = !current.includes(field);
      const changed = definition.previous && (!previous || previous.type !== field.type || removed);
      const dependency = registry.get(field.ref);
      const key = [path, field.name.replace(/\?$/, "")].filter(Boolean).join(".");
      const relevant = expanded.some(branch => branch === key || branch.startsWith(`${key}.`));
      const value = dependency && field.type === dependency.name && inlineValue(dependency, false);
      const head = h("div", { class: `row type-field${changed ? removed ? " sig del" : " sig add" : ""}` },
        h("span", { class: "type-field-name" }, `${field.name}: `),
        h("span", { class: "type-value" }, field.type),
        value && h("span", { class: "type-inline" }, ` = ${value}`),
        dependency?.fields.length > 0 && h("span", { class: "type-count" }, `${dependency.fields.length} fields`),
      );
      const prior = changed && previous && !removed && h("div", { class: "row type-field sig del" }, `${previous.name}: ${previous.type}`);
      if (!dependency?.fields.length || removed) return [prior, head];
      if (ancestors.includes(dependency.id)) return [head, h("div", { class: "type-recursive" }, "Recursive reference · ", sourceLink(dependency))];
      return [prior, foldable(`type-branch${relevant ? " relevant" : ""}`, head, fields(dependency, expanded, key, [...ancestors, dependency.id]), !relevant)];
    });
  };
  return references.map(reference => {
    const definition = registry.get(reference.id);
    const aliasChanged = definition.previous?.type && definition.previous.type !== definition.type;
    const body = definition.type
      ? h("div", { class: "type-alias" },
          aliasChanged && h("div", { class: "row sig del" }, definition.previous.type),
          h("div", { class: `row${aliasChanged ? " sig add" : ""}` }, definition.type))
      : h("div", { class: "type-fields" }, fields(definition, reference.expanded, "", [definition.id]));
    // A huge union (every icon name, say) starts folded so it doesn't bury the rest.
    const huge = (definition.type?.length ?? 0) > 400;
    const section = foldable("type-definition", h("div", { class: "row block type-definition-head" }, definition.name, sourceLink(definition)), body, huge);
    section.typeId = definition.id;
    return section;
  });
}

// ---------------------------------------------------------------- inspector

// One side panel shows the type definitions of a contract. It opens from a
// type name or `gd`; pinned, it follows the cursor from contract to contract.
const inspector = $("inspector");
let inspected = null;
let inInspector = false;
let pinned = saved.pinned ?? false;

// What a row can show in the inspector: its contract's node and type registry.
const typeContext = (row) => row?.typeContext ?? row?.closest(".detail")?.typeContext;

function inspect(context, typeId, focus = false) {
  if (inspected !== context) {
    inspected = context;
    $("inspector-title").textContent = context.node.label;
    $("inspector-body").replaceChildren(
      ...(context.node.types?.length
        ? renderTypeTree(context.node.types, context.registry)
        : [h("p", { class: "type-hint" }, "No referenced types")]),
    );
  }
  inspector.hidden = false;
  document.body.classList.add("inspecting");
  const target = [...$("inspector-body").children].find(section => section.typeId === typeId) ?? $("inspector-body").firstElementChild;
  if (target?.matches(".foldable")) fold(target, false);
  if (focus && target?.matches(".foldable")) {
    jumps.push(cursor);
    inInspector = true;
    setCursor(target.firstElementChild);
  } else target?.scrollIntoView({ block: "nearest" });
}

function leaveInspector() {
  if (!inInspector) return;
  inInspector = false;
  jumpBack();
}

function closeInspector() {
  leaveInspector();
  inspector.hidden = true;
  inspected = null;
  document.body.classList.remove("inspecting");
  status();
}

function togglePin() {
  pinned = !pinned;
  $("inspector-pin").textContent = pinned ? "Unpin" : "Pin";
  save();
  flash(pinned ? "Inspector pinned: it follows the cursor" : "Inspector unpinned");
}

$("inspector-pin").textContent = pinned ? "Unpin" : "Pin";
$("inspector-pin").addEventListener("click", togglePin);
$("inspector-close").addEventListener("click", closeInspector);
$("inspector-expand").addEventListener("click", () => $("inspector-body").querySelectorAll(".foldable").forEach(el => fold(el, false)));
$("inspector-collapse").addEventListener("click", () => $("inspector-body").querySelectorAll(".type-branch").forEach(el => fold(el, true)));

inspector.addEventListener("click", (e) => {
  const row = e.target.closest(".row");
  if (!row || e.target.closest("a, button")) return;
  if (!inInspector) jumps.push(cursor);
  inInspector = true;
  setCursor(row, false);
  if (row.parentElement.matches(".foldable") && row === row.parentElement.firstElementChild) toggleFold();
});

// Nodes come first in reading order, so j and k walk the graph top-down.
function renderGraph(data) {
  const { layout } = data;
  const registry = new Map((data.types ?? []).map(type => [type.id, type]));
  const nodes = [...data.nodes].sort(
    (a, b) => layout.nodes[a.id].y - layout.nodes[b.id].y || layout.nodes[a.id].x - layout.nodes[b.id].x,
  );
  const graph = svg(
    "svg",
    { class: "graph", viewBox: `0 0 ${layout.width} ${layout.height}`, width: layout.width },
    svg(
      "defs",
      {},
      svg(
        "marker",
        { id: "arrow", viewBox: "0 0 10 10", refX: 9, refY: 5, markerWidth: 7, markerHeight: 7, orient: "auto-start-reverse" },
        svg("path", { d: "M0,0 L10,5 L0,10 z" }),
      ),
    ),
    layout.groups.map((group) =>
      svg(
        "g",
        { class: "group" },
        svg("rect", { x: group.x, y: group.y, width: group.width, height: group.height, rx: 8 }),
        svg("text", { x: group.x + 12, y: group.y + 20 }, fit(group.label, group.width - 24)),
      ),
    ),
    layout.edges.map((edge) =>
      svg(
        "g",
        { class: "edge" },
        svg("polyline", { points: edge.points.map((p) => `${p.x},${p.y}`).join(" "), "marker-end": "url(#arrow)" }),
        edge.label && svg("text", { x: edge.label.x, y: edge.label.y + 11 }, edge.label.text),
      ),
    ),
    nodes.map((node) => {
      const context = { node, registry };
      const definitions = (node.types ?? []).map(ref => registry.get(ref.id));
      const renderSignature = line => typeSignatureLine(line, definitions, id => inspect(context, id));
      const box = layout.nodes[node.id];
      const signature = node.signature ?? [];
      // A signature longer than the card ends with a line saying what is left out.
      const shown = signature.length > box.lines ? signature.slice(0, box.lines - 1) : signature;
      const el = svg(
        "g",
        { class: `row node ${node.changed} ${node.tier ?? ""}` },
        svg("rect", { x: box.x, y: box.y, width: box.width, height: box.height, rx: 6 }),
        svg(
          "foreignObject",
          { x: box.x, y: box.y, width: box.width, height: box.height },
          h(
            "div",
            { class: "card" },
            h(
              "div",
              { class: "card-head" },
              h("span", { class: "label" }, node.label),
              node.kind && badge(node.kind, "kind"),
              node.tier && badge(tierLabels[node.tier], `tier ${node.tier}`),
              definitions.length > 0 && h("button", { class: "type-shortcut", type: "button", title: "Inspect types (gd)", onclick: event => { event.stopPropagation(); inspect(context); } }, "Types"),
            ),
            shown.length > 0 &&
              h(
                "div",
                { class: "card-code" },
                shown.map(renderSignature),
                shown.length < signature.length && h("div", { class: "more" }, `… ${signature.length - shown.length} more lines`),
              ),
          ),
        ),
      );
      el.node = node;
      el.typeContext = context;
      return el;
    }),
  );
  const details = [...graph.querySelectorAll(".node")].map((el) => {
    const { node } = el;
    const head = h(
      "div",
      { class: "row block section-head detail-head" },
      h("h2", {}, node.label, " ", badge(node.changed)),
      h("div", { class: "meta" }, [node.kind, tierLabels[node.tier], node.group].filter(Boolean).join(" · ")),
    );
    el.detail = head;
    const definitions = (node.types ?? []).map(ref => registry.get(ref.id));
    const section = h(
      "section",
      { class: "section detail" },
      head,
      markdown(node.description),
      node.signature && h("pre", { class: "row signature" }, node.signature.map(line => typeSignatureLine(line, definitions, id => inspect(el.typeContext, id)))),
      node.pseudocode.length > 0 && h("div", { class: "pseudo" }, node.pseudocode.map((line) => h("div", { class: "row step" }, line))),
      codeToggle(node.refs),
    );
    section.typeContext = el.typeContext;
    return section;
  });
  return [data.summary && markdown(data.summary), h("div", { class: "graph-wrap" }, graph), details];
}

const kindLabels = {
  "try-catch": "try / catch",
  "loose-types": "Loose types",
  "tiny-functions": "Tiny functions",
  "data-mapping": "Data mapping",
  "client-fetching": "Client-side data fetching",
  "async-waterfall": "Async waterfalls",
  other: "Other",
};

function renderFindings(data) {
  const kinds = [...new Set(data.items.map((item) => item.kind ?? ""))];
  return [
    data.summary && markdown(data.summary),
    kinds.map((kind) =>
      h(
        "section",
        { class: "section" },
        kind && h("div", { class: "row section-head" }, h("h2", {}, kindLabels[kind] ?? kind)),
        data.items
          .filter((item) => (item.kind ?? "") === kind)
          .map((item) =>
            h(
              "div",
              { class: "finding" },
              h("div", { class: "row block finding-head" }, badge(item.severity), " ", item.title),
              markdown(item.note),
              renderRefs(item.refs),
            ),
          ),
      ),
    ),
  ];
}

const concernLabels = {
  outside: "Outside the feature",
  endpoints: "Endpoints",
  data: "Data and DB",
  security: "Security",
  performance: "Performance",
};

function renderQuickView(data) {
  return [
    data.summary && markdown(data.summary),
    Object.entries(concernLabels).map(([concern, label]) => {
      const items = data.items.filter((item) => item.concern === concern);
      return h(
        "section",
        { class: "section" },
        h("div", { class: "row section-head" }, h("h2", {}, label)),
        items.length ? "" : h("div", { class: "row none" }, "Nothing found"),
        items.map((item) =>
          h(
            "div",
            { class: "finding" },
            h("div", { class: "row block finding-head" }, item.title),
            markdown(item.note),
            item.flag && h("div", { class: "flag" }, markdown(item.flag)),
            item.code.map((code) => ("path" in code ? renderExcerpt(code) : renderHunk(code.hunk, code))),
          ),
        ),
      );
    }),
  ];
}

const fieldSigns = { added: "+", removed: "−", modified: "~", unchanged: " " };

const renderers = {
  "at-a-glance": (data) => [
    h(
      "header",
      { class: "row pr-head" },
      h("h1", {}, pr.title),
      h(
        "p",
        { class: "meta" },
        `${pr.author} · ${pr.headRefName} → ${pr.baseRefName} · +${pr.additions} −${pr.deletions} · `,
        h("a", { href: pr.url, target: "_blank", rel: "noreferrer" }, `${pr.owner}/${pr.repo}#${pr.number}`),
      ),
    ),
    h("h2", { class: "row" }, "Problem"),
    markdown(data.problem),
    pr.bodyHTML && [h("h2", { class: "row" }, "Description"), markdown(pr.bodyHTML)],
  ],
  "quick-view": renderQuickView,
  review: (data) => [
    data.hunks.map((id) => renderHunk(id, { review: true, folded: data.folded.includes(id) || isTest(hunks[id].path) })),
    // Threads whose line is not in this diff, e.g. outdated ones.
    h("section", { class: "section orphans", hidden: "" }, h("div", { class: "row section-head" }, h("h2", {}, "Other threads"))),
  ],
  // Each section's pseudocode first and its code folded underneath, one fold
  // per file.
  pseudocode: (data) =>
    data.sections.map(
      (section, i) =>
        h(
          "section",
          { class: "section" },
          h("div", { class: "row section-head" }, h("h2", {}, `${i + 1}. ${section.title}`), markdown(section.why, false)),
          h("div", { class: "pseudo" }, section.pseudocode.map((step) => h("div", { class: "row step" }, step))),
          Object.entries(Object.groupBy(section.hunks, (id) => hunks[id].path)).map(([path, ids]) => {
            const lines = ids.flatMap((id) => hunks[id].lines);
            const count = (t) => lines.filter((line) => line.t === t).length;
            return foldable(
              "file",
              h(
                "div",
                { class: "row block file-head" },
                h("span", { class: "path" }, path),
                h("span", { class: "context" }, `+${count("+")} −${count("-")}`),
              ),
              ids.map((id) => renderHunk(id)),
              true,
            );
          }),
        ),
    ),
  architecture: renderGraph,
  "data-model": (data) => [
    data.summary && markdown(data.summary),
    data.entities.map((entity) =>
      h(
        "section",
        { class: "section" },
        h(
          "div",
          { class: "row block section-head" },
          h("h2", {}, entity.name, " ", badge(entity.changed)),
          entity.kind && h("div", { class: "meta" }, entity.kind),
          markdown(entity.description, false),
        ),
        entity.fields.length > 0 &&
          h(
            "div",
            { class: "fields" },
            entity.fields.map((field) =>
              h(
                "div",
                { class: `row field ${field.change}` },
                h("span", { class: "sign" }, fieldSigns[field.change]),
                h("span", { class: "field-name" }, field.name),
                h("span", { class: "field-type" }, field.previousType ? [h("s", {}, field.previousType), " → "] : "", field.type),
                h("span", { class: "field-note" }, field.note ?? ""),
              ),
            ),
          ),
        entity.usage && markdown(entity.usage),
        codeToggle(entity.refs),
      ),
    ),
  ],
  interfaces: renderGraph,
  "code-smells": renderFindings,
  performance: renderFindings,
  risks: renderFindings,
};

const tabbar = $("tabbar");
const tabEls = tabs.map((tab, i) => {
  const el = h("section", { class: "tab", hidden: "" }, renderers[tab.id](tab.data));
  el.tab = tab;
  main.append(el);
  const graph = el.querySelector(".graph");
  if (graph) {
    setZoom(graph, zooms[tab.id] ?? 1);
    // Pinch and Ctrl-scroll zoom too.
    graph.parentElement.addEventListener(
      "wheel",
      (e) => {
        if (!e.ctrlKey) return;
        e.preventDefault();
        zoom((scale) => scale * Math.exp(-e.deltaY / 100), false);
      },
      { passive: false },
    );
  }
  tabbar.append(h("button", { onclick: () => showTab(i) }, h("kbd", {}, i + 1), tab.title));
  return el;
});
document.title = `#${pr.number} ${pr.title}`;

// Your latest review of the PR, shown once the server sends a snapshot.
const reviewLabels = {
  APPROVED: "✓ Approved",
  CHANGES_REQUESTED: "Changes requested",
  COMMENTED: "Commented",
  DISMISSED: "Review dismissed",
  PENDING: "Review pending",
};
const reviewEl = h(
  "div",
  { id: "review", hidden: "" },
  h("span", { id: "review-state" }),
  h(
    "button",
    {
      id: "approve",
      onclick: (e) => {
        e.currentTarget.blur();
        if (confirm(`Approve #${pr.number}? Pending comments are submitted with it.`)) runCommand("approve");
      },
    },
    "Approve",
  ),
);
const prLink = (href, label) => h("a", { href, target: "_blank", rel: "noreferrer" }, label);
tabbar.append(
  h(
    "div",
    { id: "tabbar-end" },
    reviewEl,
    prLink(pr.url, "GitHub"),
    prLink(`https://app.graphite.dev/github/pr/${pr.owner}/${pr.repo}/${pr.number}`, "Graphite"),
  ),
);

function renderReviewState() {
  const state = snapshot?.viewerReview;
  reviewEl.hidden = !snapshot;
  $("review-state").textContent = reviewLabels[state] ?? "Not reviewed";
  $("review-state").dataset.state = state ?? "";
  $("approve").hidden = state === "APPROVED";
}

// ------------------------------------------------------------------- cursor

let active = 0;
let cursor;
let visualAnchor = null;

// Inside the inspector, movement stays in the inspector.
const rows = () =>
  [...(inInspector ? $("inspector-body") : tabEls[active]).querySelectorAll(".row")].filter((row) => row.offsetParent !== null);

// Keeps the cursor in the middle of the screen, like scrolloff=999. A row
// taller than the screen shows its top instead.
function center(row = cursor) {
  if (inspector.contains(row)) return row.scrollIntoView({ block: "nearest" });
  const rect = row.getBoundingClientRect();
  const top = tabbar.offsetHeight + $("banner").offsetHeight;
  const bottom = innerHeight - $("statusline").offsetHeight;
  scrollBy(0, rect.height > bottom - top ? rect.top - top - 16 : rect.top + rect.height / 2 - (top + bottom) / 2);
  // Graphs wider than the page scroll sideways to centre the node too.
  const wrap = row.closest(".graph-wrap");
  if (!wrap) return;
  const box = wrap.getBoundingClientRect();
  wrap.scrollLeft += rect.left + rect.width / 2 - (box.left + box.width / 2);
}

function setCursor(row, scroll = true) {
  if (!row) return;
  cursor?.classList.remove("cursor");
  cursor = row;
  row.classList.add("cursor");
  if (scroll) center(row);
  for (const el of document.querySelectorAll(".selected")) el.classList.remove("selected");
  if (visualAnchor) for (const el of selection()) el.classList.add("selected");
  if (!visualAnchor && !inInspector) {
    cursors[tabEls[active].tab.id] = rows().indexOf(row);
    save();
  }
  // A pinned inspector follows the contract under the cursor.
  const context = !inInspector && pinned && !inspector.hidden && typeContext(row);
  if (context && context !== inspected) inspect(context);
  status();
}

function move(n) {
  const all = rows();
  setCursor(all[Math.max(0, Math.min(all.length - 1, all.indexOf(cursor) + n))]);
}

function jump(selector, dir, n = 1, accept = () => true) {
  const all = rows();
  let i = all.indexOf(cursor);
  for (let step = 0; step < n; step++) {
    let j = i + dir;
    while (all[j] && !(all[j].matches(selector) && accept(all[j]))) j += dir;
    if (!all[j]) break;
    i = j;
  }
  setCursor(all[i]);
}

function halfPage(dir) {
  const y = cursor.getBoundingClientRect().top;
  const before = scrollY;
  scrollBy(0, (dir * innerHeight) / 2);
  if (scrollY === before) return move(dir * 20);
  const closest = rows().reduce((best, row) =>
    Math.abs(row.getBoundingClientRect().top - y) < Math.abs(best.getBoundingClientRect().top - y) ? row : best,
  );
  setCursor(closest);
}

function showTab(i) {
  if (!tabEls[i]) return;
  tabEls[active].hidden = true;
  tabbar.children[active].classList.remove("active");
  inInspector = false;
  if (!pinned) closeInspector();
  active = i;
  visualAnchor = null;
  tabEls[i].hidden = false;
  tabbar.children[i].classList.add("active");
  const all = rows();
  setCursor(all[Math.min(cursors[tabEls[i].tab.id] ?? 0, all.length - 1)], false);
  center();
}

// ------------------------------------------------------------ fold actions

const hunkOf = (row) => row.closest(".hunk");

function fold(el, folded) {
  el.classList.toggle("folded", folded);
  if (folded && el.contains(cursor)) setCursor(el.firstElementChild);
}

function toggleFold() {
  const el = cursor.closest(".foldable");
  if (el) fold(el, !el.classList.contains("folded"));
}

const foldAll = (folded) =>
  (inInspector ? $("inspector-body") : tabEls[active]).querySelectorAll(".foldable").forEach((el) => fold(el, folded));

// Marks every copy of the hunk, but only folds the one under the cursor.
function toggleReviewed() {
  const el = hunkOf(cursor);
  if (!el) return;
  const { key } = el.hunk;
  const on = !reviewed.has(key);
  if (on) reviewed.add(key);
  else reviewed.delete(key);
  for (const other of document.querySelectorAll(".hunk")) if (other.hunk.key === key) other.classList.toggle("reviewed", on);
  fold(el, on);
  if (on) jump(".hunk-head", 1);
  save();
  status();
}

const unreviewed = (row) => !hunkOf(row).classList.contains("reviewed");

// ------------------------------------------------------------------ graphs

const jumps = [];

function jumpTo(row) {
  jumps.push(cursor);
  setCursor(row);
  center();
}

function jumpBack() {
  const row = jumps.pop();
  if (!row) return;
  inInspector = inspector.contains(row);
  const tab = tabEls.findIndex((el) => el.contains(row));
  if (tab !== -1 && tab !== active) showTab(tab);
  setCursor(row);
  center();
}

// Moves to the nearest node in a direction; j and k leave the graph when
// there is none.
function spatial(dx, dy, n = 1) {
  for (let step = 0; step < n; step++) {
    const from = cursor.getBoundingClientRect();
    const [cx, cy] = [from.x + from.width / 2, from.y + from.height / 2];
    let best;
    let bestScore = Infinity;
    for (const node of cursor.closest("svg").querySelectorAll(".node")) {
      const rect = node.getBoundingClientRect();
      const [ox, oy] = [rect.x + rect.width / 2 - cx, rect.y + rect.height / 2 - cy];
      const along = ox * dx + oy * dy;
      if (node === cursor || along <= 1) continue;
      const score = along + 2 * Math.abs(dx ? oy : ox);
      if (score < bestScore) [best, bestScore] = [node, score];
    }
    if (best) setCursor(best);
    else if (dy) return leaveGraph(dy);
  }
}

// A declaration, since tabs apply their saved zoom while rendering.
function setZoom(graph, scale) {
  graph.setAttribute("width", graph.viewBox.baseVal.width * scale);
}

// The scale that shows the whole graph, never above its own size.
function fitScale(graph) {
  const { width, height } = graph.viewBox.baseVal;
  const room = innerHeight - tabbar.offsetHeight - $("statusline").offsetHeight - 32;
  return Math.min(1, (graph.parentElement.clientWidth - 32) / width, room / height);
}

// Zooms the active tab's graph and keeps the cursor centred.
function zoom(next, announce = true) {
  const graph = tabEls[active].querySelector(".graph");
  if (!graph) return flash("No graph in this tab");
  const { id } = tabEls[active].tab;
  zooms[id] = Math.min(3, Math.max(0.1, next(zooms[id] ?? 1, graph)));
  setZoom(graph, zooms[id]);
  center();
  save();
  if (announce) flash(`Zoom ${Math.round(zooms[id] * 100)}%`);
}

function leaveGraph(dir) {
  const all = rows();
  const nodes = all.filter((row) => row.matches(".node"));
  const i = dir > 0 ? all.indexOf(nodes.at(-1)) + 1 : all.indexOf(nodes[0]) - 1;
  setCursor(all[i]);
}

// The rows from the visual anchor to the cursor, like Vim's linewise V.
function selection() {
  const all = rows();
  if (!visualAnchor || !all.includes(visualAnchor)) return [cursor];
  const [a, b] = [all.indexOf(visualAnchor), all.indexOf(cursor)].sort((x, y) => x - y);
  return all.slice(a, b + 1);
}

// Diff lines from one file yank as path:lines, anything else as its text.
function yank() {
  const sel = selection();
  const code = sel.every((row) => row.line) && new Set(sel.map((row) => row.line.path)).size === 1;
  const { path, num } = sel[0].line ?? {};
  const end = sel.at(-1).line?.num;
  const text = code
    ? `${path}:${num}${end !== num ? `-${end}` : ""}`
    : sel.map((row) => (row.querySelector(".code") ?? row).textContent.trim()).join("\n");
  navigator.clipboard
    .writeText(text)
    .then(() => flash(code ? `Yanked ${text}` : `Yanked ${sel.length} line${sel.length === 1 ? "" : "s"}`));
  visualAnchor = null;
  setCursor(cursor);
}

// ---------------------------------------------------------------- comments

let snapshot = null;
// A rebase that leaves the diff alone moves the head but not the page's lines.
const sameDiff = () => Boolean(pr.diffHash) && snapshot?.diffHash === pr.diffHash;
// Comments go on the commit the page shows, or on the new head when its diff is the same.
const commitOid = () => (sameDiff() ? snapshot.headOid : pr.headOid);
let editor = null;
const drafts = new Map();
// Numbers upload placeholders so two pasted images can't swap places.
let uploads = 0;
// Image uploads still running, per draft key.
const uploading = new Map();
const waitMessage = "Wait for the images to finish uploading";
// Thread ids whose default collapsed state (resolved = collapsed) is flipped.
const toggledThreads = new Set();

async function post(path, body, method = "POST") {
  const res = await fetch(api + path, {
    method,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error((await res.text()).trim() || res.statusText);
}

// The head, each comment's meta and each block of its body are rows, so the
// cursor moves through threads like any other text.
function renderThread(thread, anchorRow) {
  const comments = thread.comments.nodes;
  const collapsed = thread.isResolved !== toggledThreads.has(thread.id);
  const el = h(
    "div",
    { class: `thread${collapsed ? " collapsed" : ""}${thread.isResolved ? " resolved" : ""}` },
    h(
      "div",
      { class: "row thread-head" },
      `${comments[0]?.author?.login ?? "ghost"} · ${comments.length} comment${comments.length === 1 ? "" : "s"}`,
      thread.isResolved && " · resolved",
      thread.isOutdated && " · outdated",
    ),
    comments.map((c) => {
      const body = markdown(c.bodyHTML);
      body.classList.add("comment-body");
      return h(
        "div",
        { class: `comment${c.state === "PENDING" ? " pending" : ""}` },
        h(
          "div",
          { class: "row comment-meta" },
          `${c.author?.login ?? "ghost"} · ${new Date(c.createdAt).toLocaleString()}`,
          c.state === "PENDING" && h("span", { class: "badge" }, "pending"),
        ),
        body,
      );
    }),
  );
  el.thread = thread;
  el.anchorRow = anchorRow;
  for (const row of el.querySelectorAll(".row")) row.threads = [thread];
  return el;
}

// Inserts after the row and any threads or editor already following it.
function insertAfter(row, el) {
  let at = row;
  while (at.nextElementSibling?.matches(".thread")) at = at.nextElementSibling;
  at.after(el);
}

function renderThreads() {
  // A cursor inside a thread goes back to the same row of the rebuilt thread.
  const old = cursor?.closest(".thread");
  const restore = old && { id: old.thread.id, anchorRow: old.anchorRow, i: [...old.querySelectorAll(".row")].indexOf(cursor) };
  for (const el of document.querySelectorAll(".thread, .orphan")) el.remove();
  for (const row of document.querySelectorAll(".has-thread")) {
    row.classList.remove("has-thread");
    row.threads = [];
  }
  const orphans = document.querySelector(".orphans");
  for (const thread of snapshot?.threads ?? []) {
    let targets = anchors.get(anchor(thread.diffSide, thread.line, thread.path)) ?? [];
    if (thread.line == null || !targets.length) {
      if (!orphans) continue;
      const row = h("div", { class: "row orphan" }, `${thread.path}:${thread.line ?? thread.originalLine}`);
      row.threads = [];
      orphans.append(row);
      targets = [row];
    }
    for (const row of targets) {
      row.classList.add("has-thread");
      row.threads.push(thread);
      insertAfter(row, renderThread(thread, row));
    }
  }
  if (orphans) orphans.hidden = !orphans.querySelector(".orphan");
  if (!restore) return;
  // Orphan rows are rebuilt too, so their threads are found by id instead.
  const copies = [...tabEls[active].querySelectorAll(".thread")].filter((el) => el.thread.id === restore.id);
  const el = copies.find((el) => el.anchorRow === restore.anchorRow) ?? copies[0];
  const row = el?.querySelectorAll(".row")[restore.i];
  if (row?.offsetParent) setCursor(row, false);
  else setCursor(el?.firstElementChild ?? (restore.anchorRow.isConnected ? restore.anchorRow : rows()[0]));
}

// Drafts are kept per row and kind, so reopening an editor restores them.
// Without a row the editor floats over the page.
function openEditor(row, kind, title, submit) {
  closeEditor();
  const key = row ? `${kind}:${anchor(row.line?.side, row.line?.num, row.line?.path)}` : kind;
  const textarea = h("textarea", {
    rows: row ? 4 : 8,
    placeholder: `Markdown; paste images. ⌘↵ posts ${row ? "to your pending review" : "to the PR"}, Esc closes.`,
  });
  const error = h("div", { class: "editor-error" });
  editor = h("div", { class: "editor" }, h("div", { class: "editor-title" }, title), textarea, error);
  editor.key = key;
  textarea.value = drafts.get(key) ?? "";
  // Pasted images upload to GitHub, holding their place with a placeholder
  // like github.com does.
  textarea.addEventListener("paste", (e) => {
    const images = [...e.clipboardData.files].filter((file) => file.type.startsWith("image/"));
    if (!images.length) return;
    e.preventDefault();
    for (const file of images) {
      const alt = file.name.replace(/[[\]\\]/g, "\\$&");
      const placeholder = `![Uploading ${alt} #${++uploads}…]()`;
      textarea.setRangeText(`${placeholder}\n`, textarea.selectionStart, textarea.selectionEnd, "end");
      uploading.set(key, (uploading.get(key) ?? 0) + 1);
      let failure = "";
      fetch(`${api}/attachments?name=${encodeURIComponent(file.name)}`, { method: "POST", headers: { "Content-Type": file.type }, body: file })
        .then(async (res) => {
          if (!res.ok) throw new Error((await res.text()).trim() || res.statusText);
          return `![${alt}](${(await res.json()).url})`;
        })
        .catch((err) => {
          failure = `Upload failed: ${err.message}`;
          return "";
        })
        .then((link) => {
          uploading.set(key, uploading.get(key) - 1);
          // The editor may have been closed into a draft, or reopened, meanwhile.
          if (editor?.key !== key) {
            if (drafts.has(key)) drafts.set(key, drafts.get(key).replace(placeholder, () => link));
            return;
          }
          const live = editor.querySelector("textarea");
          const at = live.value.indexOf(placeholder);
          if (at >= 0) live.setRangeText(link, at, at + placeholder.length, "preserve");
          const note = editor.querySelector(".editor-error");
          if (failure) note.textContent = failure;
          else if (!uploading.get(key) && note.textContent === waitMessage) note.textContent = "";
        });
    }
  });
  textarea.addEventListener("keydown", async (e) => {
    e.stopPropagation();
    if (e.key === "Escape") {
      drafts.set(key, textarea.value);
      closeEditor();
    } else if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      if (uploading.get(key)) return (error.textContent = waitMessage);
      if (!textarea.value.trim()) return;
      textarea.disabled = true;
      error.textContent = "Posting…";
      try {
        await submit(textarea.value);
        drafts.delete(key);
        closeEditor();
      } catch (err) {
        textarea.disabled = false;
        error.textContent = err.message;
        textarea.focus();
      }
    }
  });
  textarea.addEventListener("focus", status);
  if (row) insertAfter(row, editor);
  else {
    editor.classList.add("floating");
    document.body.append(editor);
  }
  textarea.focus();
}

function closeEditor() {
  editor?.remove();
  editor = null;
  status();
}

// GitHub anchors a comment to diff lines within one hunk.
function comment() {
  // Threads between the selected diff lines are skipped.
  const sel = selection().filter((row) => !row.closest(".thread"));
  if (!sel.length || !sel.every((row) => row.line && !row.line.unchanged)) return flash("Comments go on diff lines");
  if (new Set(sel.map(hunkOf)).size > 1) return flash("A comment's lines must be in one hunk");
  const first = sel[0].line;
  const last = sel.at(-1).line;
  const range = sel.length > 1 ? `${first.num}-${last.num}` : last.num;
  visualAnchor = null;
  setCursor(sel.at(-1));
  openEditor(sel.at(-1), "comment", `Comment on ${last.path}:${range}`, (body) =>
    post("/threads", {
      commitOid: commitOid(),
      path: last.path,
      line: last.num,
      side: last.side,
      startLine: sel.length > 1 ? first.num : null,
      startSide: sel.length > 1 ? first.side : null,
      body,
    }),
  );
}

const threadAtCursor = () => cursor.threads?.find((t) => !t.isResolved) ?? cursor.threads?.[0];

function reply() {
  const thread = threadAtCursor();
  if (!thread) return flash("No thread on this line");
  openEditor(cursor.closest(".thread")?.anchorRow ?? cursor, "reply", `Reply to ${thread.comments.nodes[0]?.author?.login ?? "thread"}`, (body) =>
    post(`/threads/${thread.id}/replies`, { commitOid: commitOid(), body }),
  );
}

const generalComment = () =>
  openEditor(null, "general", `Comment on #${pr.number}`, async (body) => {
    await post("/comments", { body });
    flash("Comment posted");
  });

function toggleThreads() {
  for (const thread of cursor.threads ?? []) {
    if (toggledThreads.has(thread.id)) toggledThreads.delete(thread.id);
    else toggledThreads.add(thread.id);
  }
  renderThreads();
}

const commands = {
  async submit(event = "comment", ...body) {
    const events = { comment: "COMMENT", approve: "APPROVE", changes: "REQUEST_CHANGES" };
    if (!events[event]) throw new Error("Usage: :submit [comment|approve|changes] [body]");
    await post("/review", { commitOid: commitOid(), event: events[event], body: body.join(" ") });
    flash("Review submitting in the background, safe to close");
  },
  approve: (...body) => commands.submit("approve", ...body),
  async resolve() {
    const thread = threadAtCursor();
    if (!thread) throw new Error("No thread on this line");
    await post(`/threads/${thread.id}/resolve`, { resolved: !thread.isResolved });
  },
  async delete() {
    const mine = threadAtCursor()?.comments.nodes.findLast(
      (c) => c.state === "PENDING" && c.author?.login === snapshot?.viewer,
    );
    if (!mine) throw new Error("No pending comment of yours on this line");
    await post(`/comments/${mine.id}`, {}, "DELETE");
  },
};

async function runCommand(line) {
  const [name, ...args] = line.trim().split(/\s+/);
  const command = Object.keys(commands).find((c) => name && c.startsWith(name));
  if (!command) return flash(`Unknown command: ${name}`);
  try {
    await commands[command](...args);
  } catch (err) {
    flash(err.message);
  }
}

function connect() {
  // Opened as a file there is no server, so the page stays without comments.
  if (location.protocol === "file:") return;
  // Browsers allow 6 connections per host over HTTP/1.1 and each page's event
  // stream holds one open, so pages let theirs go while hidden. Otherwise a
  // seventh page would never load. Reconnecting sends the latest snapshot.
  let source = null;
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      source?.close();
      source = null;
      setConnection("offline");
    } else if (!source) open();
  });
  if (!document.hidden) open();

  function open() {
    source = new EventSource(`${api}/events`);
    source.addEventListener("open", () => setConnection("live"));
    source.addEventListener("error", () => setConnection("offline"));
    source.addEventListener("snapshot", (e) => {
      snapshot = JSON.parse(e.data);
      $("banner").hidden = snapshot.headOid === pr.headOid || sameDiff();
      $("banner").textContent =
        "The PR has new commits since this page was built, so threads may sit on the wrong lines. Rebuild to update.";
      renderThreads();
      renderReviewState();
      setConnection("live");
    });
    source.addEventListener("failure", (e) => flash(`GitHub: ${JSON.parse(e.data)}`));
  }
}

// ------------------------------------------------------------ prompt, search

let promptSubmit = null;
let lastSearch = "";
// 1 after /, -1 after ?; n repeats it and N reverses it.
let searchDir = 1;

const startSearch = (dir) =>
  openPrompt(dir > 0 ? "/" : "?", (q) => {
    lastSearch = q || lastSearch;
    searchDir = dir;
    search(dir);
  });

function openPrompt(prefix, submit) {
  promptSubmit = submit;
  prompt.hidden = false;
  prompt.value = prefix;
  prompt.focus();
  status();
}

function closePrompt() {
  prompt.hidden = true;
  prompt.blur();
  status();
}

prompt.addEventListener("keydown", (e) => {
  e.stopPropagation();
  if (e.key === "Escape" || (e.key === "Backspace" && prompt.value.length === 1)) {
    e.preventDefault();
    closePrompt();
  } else if (e.key === "Enter") {
    const value = prompt.value.slice(1);
    closePrompt();
    promptSubmit(value);
  }
});

function search(dir) {
  if (!lastSearch) return;
  const caseSensitive = lastSearch !== lastSearch.toLowerCase();
  const matches = (row) => {
    const text = row.textContent;
    return (caseSensitive ? text : text.toLowerCase()).includes(lastSearch);
  };
  const all = rows();
  const start = all.indexOf(cursor);
  for (let step = 1; step <= all.length; step++) {
    const row = all[(start + dir * step + all.length * step) % all.length];
    if (matches(row)) return setCursor(row);
  }
  flash(`Pattern not found: ${lastSearch}`);
}

// ----------------------------------------------------------------- keymap

const keymap = [
  ["Move", ["j", "ArrowDown"], "Next line; node below in a graph", (n) => (onNode() ? spatial(0, 1, n) : move(n ?? 1))],
  ["Move", ["k", "ArrowUp"], "Previous line; node above in a graph", (n) => (onNode() ? spatial(0, -1, n) : move(-(n ?? 1)))],
  ["Move", ["h", "l"], "Node left / right in a graph", null],
  ["Move", ["}"], "Next block (hunk, step, finding, node)", (n) => jump(".block", 1, n)],
  ["Move", ["{"], "Previous block", (n) => jump(".block", -1, n)],
  ["Move", ["]]"], "Next section", (n) => jump(".section-head", 1, n)],
  ["Move", ["[["], "Previous section", (n) => jump(".section-head", -1, n)],
  ["Move", ["]u"], "Next unreviewed hunk", (n) => jump(".hunk-head", 1, n, unreviewed)],
  ["Move", ["[u"], "Previous unreviewed hunk", (n) => jump(".hunk-head", -1, n, unreviewed)],
  ["Move", ["]c"], "Next thread", (n) => jump(".has-thread", 1, n)],
  ["Move", ["[c"], "Previous thread", (n) => jump(".has-thread", -1, n)],
  ["Move", ["gg"], "First line", () => setCursor(rows()[0])],
  ["Move", ["G"], "Last line", () => setCursor(rows().at(-1))],
  ["Move", ["Ctrl-d", "Ctrl-u"], "Half page down / up", null],
  ["Move", ["zz"], "Centre the cursor", () => center()],
  ["Graphs", ["+"], "Zoom in (pinch or Ctrl-scroll too)", (n) => zoom((scale) => scale * 1.25 ** (n ?? 1))],
  ["Graphs", ["-"], "Zoom out", (n) => zoom((scale) => scale / 1.25 ** (n ?? 1))],
  ["Graphs", ["="], "Fit the whole graph on screen", () => zoom((_, graph) => fitScale(graph))],
  ["Graphs", ["0"], "Actual size", () => zoom(() => 1)],
  ["Graphs", ["Space + drag"], "Pan the graph", null],
  ["Tabs", ["⌘1-9", "{n}gt"], "Go to tab n", null],
  ["Tabs", ["gt"], "Next tab", (n) => showTab(n ? n - 1 : (active + 1) % tabEls.length)],
  ["Tabs", ["gT"], "Previous tab", () => showTab((active - 1 + tabEls.length) % tabEls.length)],
  ["Review", ["za", "o"], "Fold or unfold (hunk, code under a step)", toggleFold],
  ["Review", ["Enter"], "Open node details, or fold", () => (onNode() ? jumpTo(cursor.detail) : toggleFold())],
  ["Types", ["gd"], "Inspect the contract's types", () => {
    const context = typeContext(cursor);
    if (context?.node.types?.length) inspect(context, undefined, true);
    else flash("No referenced types here");
  }],
  ["Types", ["gp"], "Pin or unpin the inspector", togglePin],
  ["Types", ["gq"], "Close the inspector", closeInspector],
  ["Review", ["Ctrl-o"], "Jump back", null],
  ["Review", ["zM"], "Fold everything", () => foldAll(true)],
  ["Review", ["zR"], "Unfold everything", () => foldAll(false)],
  ["Review", ["x"], "Toggle hunk reviewed", toggleReviewed],
  ["Review", ["V"], "Select lines", () => {
    visualAnchor = visualAnchor ? null : cursor;
    setCursor(cursor);
  }],
  ["Review", ["y"], "Yank path:lines, or the text", yank],
  ["Review", ["/"], "Search forward", () => startSearch(1)],
  ["Review", ["?"], "Search backward", () => startSearch(-1)],
  ["Review", ["n", "N"], "Next match in the search's direction / reverse", null],
  ["Comments", ["c"], "Comment on line or selection", comment],
  ["Comments", ["r"], "Reply to thread", reply],
  ["Comments", ["C"], "General comment on the PR", generalComment],
  ["Comments", ["t"], "Expand or collapse threads", toggleThreads],
  ["Comments", [":resolve"], "Resolve or unresolve thread", null],
  ["Comments", [":delete"], "Delete your pending comment", null],
  ["Comments", [":submit [comment|approve|changes] [body]"], "Submit pending review", null],
  ["Comments", [":approve [body]"], "Approve the PR (with pending comments)", null],
  ["Other", [":"], "Command line", () => openPrompt(":", runCommand)],
  ["Other", ["⌘K"], "Command palette", null],
  ["Other", ["g?"], "Toggle this help", () => (help.hidden = !help.hidden)],
  ["Other", ["Esc", "Ctrl-c"], "Cancel; leaves, then closes, the inspector", () => {
    visualAnchor = null;
    help.hidden = true;
    if (inInspector) return pinned ? leaveInspector() : closeInspector();
    if (!inspector.hidden && !pinned) return closeInspector();
    setCursor(cursor);
  }],
];

const bindings = new Map([
  ["h", (n) => onNode() && spatial(-1, 0, n)],
  ["l", (n) => onNode() && spatial(1, 0, n)],
  ["n", () => search(searchDir)],
  ["N", () => search(-searchDir)],
  ["Escape", keymap.at(-1)[3]],
  ...keymap.flatMap(([, keys, , run]) => (run ? keys.map((key) => [key, run]) : [])),
]);
const prefixes = new Set([...bindings.keys()].filter((key) => key.length === 2).map((key) => key[0]));
const onNode = () => cursor?.matches(".node");

help.append(
  h("h2", {}, "Keys"),
  h(
    "dl",
    {},
    keymap.map(([group, keys, description]) => [
      h("dt", { "data-group": group }, keys.map((key) => h("kbd", {}, key))),
      h("dd", {}, description),
    ]),
  ),
);

// ----------------------------------------------------------------- palette

const palette = $("palette");
const paletteInput = $("palette-input");
const paletteList = $("palette-list");

// Tabs, keymap actions and : commands. Commands that take arguments open the
// command line with their name filled in.
const actions = [
  ...tabEls.map((el, i) => ({ label: `Go to tab: ${el.tab.title}`, keys: [`⌘${i + 1}`], run: () => showTab(i) })),
  ...keymap.flatMap(([group, keys, description, run]) => {
    const label = `${group}: ${description}`;
    const command = keys[0].match(/^:(\w+)( \[)?/);
    if (command) {
      const [, name, args] = command;
      return [{ label, keys, run: () => (args ? openPrompt(`:${name} `, runCommand) : runCommand(name)) }];
    }
    return run ? [{ label, keys, run: () => run() }] : [];
  }),
];
let matches = [];
let selected = 0;

function renderPalette() {
  const words = paletteInput.value.toLowerCase().split(/\s+/).filter(Boolean);
  matches = actions.filter((action) => {
    const text = `${action.label} ${action.keys.join(" ")}`.toLowerCase();
    return words.every((word) => text.includes(word));
  });
  selected = Math.min(selected, Math.max(0, matches.length - 1));
  paletteList.replaceChildren(
    ...matches.map((action, i) =>
      h(
        "li",
        {
          class: i === selected ? "active" : "",
          // mousedown keeps focus in the input, so its blur does not close the palette first.
          onmousedown: (e) => {
            e.preventDefault();
            runAction(action);
          },
        },
        h("span", {}, action.label),
        h("span", { class: "keys" }, action.keys.map((key) => h("kbd", {}, key))),
      ),
    ),
  );
  paletteList.children[selected]?.scrollIntoView({ block: "nearest" });
}

function openPalette() {
  palette.hidden = false;
  paletteInput.value = "";
  selected = 0;
  renderPalette();
  paletteInput.focus();
  status();
}

function closePalette() {
  palette.hidden = true;
  paletteInput.blur();
  status();
}

function runAction(action) {
  closePalette();
  action.run();
  status();
}

paletteInput.addEventListener("input", () => {
  selected = 0;
  renderPalette();
});
paletteInput.addEventListener("blur", closePalette);
paletteInput.addEventListener("keydown", (e) => {
  e.stopPropagation();
  const step =
    e.key === "ArrowDown" || (e.ctrlKey && e.key === "n") ? 1
    : e.key === "ArrowUp" || (e.ctrlKey && e.key === "p") ? -1
    : 0;
  if (step) {
    e.preventDefault();
    if (matches.length) selected = (selected + step + matches.length) % matches.length;
    renderPalette();
  } else if (e.key === "Enter") {
    e.preventDefault();
    if (matches[selected]) runAction(matches[selected]);
  } else if (e.key === "Escape" || ((e.metaKey || e.ctrlKey) && e.key === "k")) {
    e.preventDefault();
    closePalette();
  }
});

let pending = "";
let count = "";

addEventListener("keydown", (e) => {
  if (e.target instanceof HTMLTextAreaElement || e.target instanceof HTMLInputElement) return;
  if (["Shift", "Control", "Alt", "Meta"].includes(e.key)) return;
  if (e.key === " ") {
    e.preventDefault();
    return setPanning(true);
  }
  if ((e.metaKey || e.ctrlKey) && e.key === "k") {
    e.preventDefault();
    return openPalette();
  }
  if ((e.metaKey || e.ctrlKey) && /^[1-9]$/.test(e.key)) {
    e.preventDefault();
    return showTab(Number(e.key) - 1);
  }
  if (e.ctrlKey && e.key === "c") {
    e.preventDefault();
    pending = count = "";
    return bindings.get("Escape")();
  }
  if (e.ctrlKey && e.key === "o") {
    e.preventDefault();
    return jumpBack();
  }
  if (e.ctrlKey && (e.key === "d" || e.key === "u")) {
    e.preventDefault();
    return halfPage(e.key === "d" ? 1 : -1);
  }
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (!pending && (/^[1-9]$/.test(e.key) || (count && e.key === "0"))) {
    count += e.key;
  } else {
    const run = bindings.get(pending + e.key);
    if (run) {
      const n = count ? Number(count) : undefined;
      pending = count = "";
      run(n);
    } else if (!pending && prefixes.has(e.key)) {
      pending = e.key;
    } else {
      pending = count = "";
      if (e.key.length > 1) return status();
    }
  }
  e.preventDefault();
  status();
});

// Space + drag pans a graph: sideways inside it, and up and down the page.
let panning = false;
let drag = null;
let dragged = false;

function setPanning(on) {
  panning = on;
  document.body.classList.toggle("panning", on);
  if (!on) drag = null;
}

addEventListener("keyup", (e) => e.key === " " && setPanning(false));
addEventListener("blur", () => setPanning(false));

main.addEventListener("mousedown", (e) => {
  const wrap = e.target.closest(".graph-wrap");
  if (!panning || !wrap) return;
  e.preventDefault();
  drag = { wrap, x: e.clientX, y: e.clientY, left: wrap.scrollLeft, top: scrollY };
});

addEventListener("mousemove", (e) => {
  if (!drag) return;
  drag.moved = true;
  drag.wrap.scrollLeft = drag.left - (e.clientX - drag.x);
  scrollTo(scrollX, drag.top - (e.clientY - drag.y));
});

// The click that follows a drag is dropped, even once Space is released.
addEventListener("mouseup", () => {
  dragged = Boolean(drag?.moved);
  drag = null;
  setTimeout(() => (dragged = false));
});

main.addEventListener("click", (e) => {
  // A drag ending on a node is not a click on it.
  if (panning || dragged) return;
  const row = e.target.closest(".row");
  if (!row || e.target.closest("a")) return;
  // A node takes the cursor on the first click and opens its details on the next.
  if (row.matches(".node") && row === cursor) return jumpTo(row.detail);
  setCursor(row, false);
});

// ------------------------------------------------------------------ status

let connection = "offline";
let flashTimer;

function setConnection(state) {
  connection = state;
  status();
}

function flash(text) {
  $("message").textContent = text;
  clearTimeout(flashTimer);
  flashTimer = setTimeout(() => ($("message").textContent = ""), 5000);
}

function save() {
  localStorage.setItem(
    storageKey,
    JSON.stringify({ reviewed: [...reviewed], tab: tabEls[active].tab.id, cursors, zooms, pinned }),
  );
}

function status() {
  const mode =
    document.activeElement === prompt || document.activeElement === paletteInput ? "COMMAND"
    : document.activeElement?.matches("textarea") ? "INSERT"
    : visualAnchor ? "VISUAL"
    : "NORMAL";
  $("mode").textContent = mode;
  $("mode").dataset.mode = mode;
  $("keys").textContent = count + pending;
  const line = cursor?.line;
  $("where").textContent = line ? `${line.path}:${line.num}` : "";
  const pendingComments = (snapshot?.threads ?? [])
    .flatMap((t) => t.comments.nodes)
    .filter((c) => c.state === "PENDING").length;
  $("comments").textContent =
    connection === "live" ? `● live${pendingComments ? ` · ${pendingComments} pending` : ""}` : "○ offline";
  $("comments").dataset.state = connection;
  const keys = Object.values(hunks).map((hunk) => hunk.key);
  $("progress").textContent = `${keys.filter((key) => reviewed.has(key)).length}/${keys.length} reviewed`;
  renumber();
}

// Like Vim's relativenumber, every row shows its distance from the cursor, so
// counts like 5j can be read off the gutter. Batched to once per frame.
let renumberQueued = false;
function renumber() {
  if (renumberQueued) return;
  renumberQueued = true;
  requestAnimationFrame(() => {
    renumberQueued = false;
    const all = rows();
    const at = all.indexOf(cursor);
    all.forEach((row, i) => (row.dataset.rel = Math.abs(i - at)));
  });
}

showTab(Math.max(0, tabEls.findIndex((el) => el.tab.id === saved.tab)));
connect();
