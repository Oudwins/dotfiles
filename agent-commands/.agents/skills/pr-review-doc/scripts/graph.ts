// Lays out graph tabs at build time, so the page ships positioned SVG data
// and needs no layout library.
import ELK from "elkjs/lib/elk.bundled.js";

type Graph = {
  nodes: { id: string; label: string; kind?: string; group?: string; signature?: string }[];
  edges: { from: string; to: string; label?: string }[];
};

// Cards show the name and kind, then up to `maxLines` of the signature.
// Sizes approximate the card CSS in viewer.css.
const card = { maxLines: 12, maxChars: 72, labelChar: 7.8, kindChar: 6.6, codeChar: 7.1, codeLine: 17, head: 36 };

const nodeSize = (node: Graph["nodes"][number]) => {
  const lines = node.signature?.split("\n").slice(0, card.maxLines) ?? [];
  const head = node.label.length * card.labelChar + (node.kind ? node.kind.length * card.kindChar + 26 : 0) + 28;
  const code = Math.min(Math.max(0, ...lines.map((line) => line.length)), card.maxChars) * card.codeChar + 40;
  return {
    width: Math.max(head, lines.length ? code : 0),
    height: card.head + (lines.length ? lines.length * card.codeLine + 10 : 0),
    lines: lines.length,
  };
};

export async function layout({ nodes, edges }: Graph) {
  const sizes = new Map(nodes.map((node) => [node.id, nodeSize(node)]));
  const child = (node: Graph["nodes"][number]) => {
    const { width, height } = sizes.get(node.id)!;
    return { id: node.id, width, height };
  };
  const groups = [...new Set(nodes.flatMap((node) => (node.group ? [node.group] : [])))];
  const result = await new ELK().layout({
    id: "root",
    layoutOptions: {
      "elk.algorithm": "layered",
      "elk.direction": "DOWN",
      "elk.hierarchyHandling": "INCLUDE_CHILDREN",
      "elk.edgeRouting": "ORTHOGONAL",
      "elk.spacing.nodeNode": "28",
      "elk.layered.spacing.nodeNodeBetweenLayers": "48",
      "elk.padding": "[top=12,left=12,bottom=12,right=12]",
      "elk.json.shapeCoords": "ROOT",
      "elk.json.edgeCoords": "ROOT",
    },
    children: [
      ...nodes.filter((node) => !node.group).map(child),
      ...groups.map((group, i) => ({
        id: `group:${i}`,
        layoutOptions: { "elk.padding": "[top=32,left=14,bottom=14,right=14]" },
        children: nodes.filter((node) => node.group === group).map(child),
      })),
    ],
    edges: edges.map((edge, i) => ({
      id: `edge:${i}`,
      sources: [edge.from],
      targets: [edge.to],
      labels: edge.label ? [{ text: edge.label, width: edge.label.length * 6.6, height: 14 }] : [],
    })),
  });

  const boxes = (result.children ?? []).flatMap((child) => [child, ...(child.children ?? [])]);
  const box = (id: string) => {
    const { x = 0, y = 0, width = 0, height = 0 } = boxes.find((b) => b.id === id)!;
    return { x, y, width, height };
  };
  return {
    width: result.width ?? 0,
    height: result.height ?? 0,
    // `lines` is how many signature lines fit on the card.
    nodes: Object.fromEntries(nodes.map((node) => [node.id, { ...box(node.id), lines: sizes.get(node.id)!.lines }])),
    groups: groups.map((label, i) => ({ label, ...box(`group:${i}`) })),
    edges: (result.edges ?? []).map((edge) => ({
      points: (edge.sections ?? []).flatMap((s) => [s.startPoint, ...(s.bendPoints ?? []), s.endPoint]),
      label: edge.labels?.[0] && { text: edge.labels[0].text, x: edge.labels[0].x, y: edge.labels[0].y },
    })),
  };
}
