//.opencode/tool/btca.ts
// import { tool } from "@opencode-ai/plugin";
//
// async function runCodex({
//   prompt,
//   effort,
//   timeoutSeconds,
// }: {
//   prompt: string;
//   effort: string;
//   timeoutSeconds?: number;
// }) {
//   const args = [
//     "exec",
//     "--enable",
//     "web_search_request",
//     "--sandbox",
//     "read-only",
//     "-c",
//     `model_reasoning_effort=${effort}`,
//     prompt,
//   ];
//
//   const proc = Bun.spawn(["codex", ...args], {
//     stdout: "pipe",
//     stderr: "pipe",
//   });
//
//   let timeoutId: ReturnType<typeof setTimeout> | undefined;
//   if (timeoutSeconds && timeoutSeconds > 0) {
//     timeoutId = setTimeout(
//       () => {
//         proc.kill();
//       },
//       Math.round(timeoutSeconds * 1000),
//     );
//   }
//
//   const [stdout, stderr] = await Promise.all([
//     new Response(proc.stdout).text(),
//     new Response(proc.stderr).text(),
//   ]);
//   const exitCode = await proc.exited;
//   if (timeoutId) {
//     clearTimeout(timeoutId);
//   }
//
//   if (exitCode !== 0) {
//     const message =
//       stderr.trim() || `codex exec failed with exit code ${exitCode}`;
//     throw new Error(message);
//   }
//
//   return stdout.trim();
// }
//
// export default tool({
//   description:
//     "Run a web search and return a concise summary with source links. Use when you need current, verifiable information or citations.",
//   args: {
//     reason: tool.schema
//       .string()
//       .describe(
//         "Describe the core reason you’re reaching for web search and the decision or output you’re aiming for.",
//       ),
//     query: tool.schema
//       .string()
//       .describe(
//         'List the search queries you want run; use new lines or ";" to include multiple angles.',
//       ),
//     additional_context: tool.schema
//       .string()
//       .optional()
//       .describe(
//         "Add constraints or background: versions, product names, prior findings, relevant files/code, or must-include sources.",
//       ),
//     quality: tool.schema
//       .enum(["fast", "balanced", "deep"])
//       .describe(
//         "Fast = quick scan, balanced = normal depth, deep = thorough with follow-up leads.",
//       ),
//     timeout: tool.schema
//       .number()
//       .optional()
//       .describe("Optional max seconds to cap the search."),
//   },
//   async execute(args: {
//     reason: string;
//     query: string;
//     additional_context?: string;
//     quality: Quality;
//     timeout?: number;
//   }) {
//     const quality = args.quality as Quality;
//     const prompt = buildPrompt({
//       reason: args.reason,
//       query: args.query,
//       additionalContext: args.additional_context,
//       quality,
//     });
//
//     const effort = QUALITY_PRESETS[quality].effort;
//     return runCodex({
//       prompt,
//       effort,
//       timeoutSeconds: args.timeout,
//     });
//   },
// });
