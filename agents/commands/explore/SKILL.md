---
name: explore
description: Use this when the user wants to explore multiple possibilities to implement something or is unsure which approach to take.
disable-model-invocation: true
---

I want to do something but I am unsure exactly how it should be done. Let's explore multiple possibilities. You should prioritize presenting as many and as varied approaches as possible over making every approach "good". 

The general flow you should follow for this exploration is:

1. Gather context about the goal, the existing codebase, and relevant external constraints. Use subagents, skills, code search, and web research as appropriate.
2. Ask me as many clarifying questions as you need to help guide the design
3. Identify multiple approaches and research each enough to confirm basic feasibility.
4. Present multiple strategies for achieving the goal. Aim to make these varied. Each approach outline should be sufficiently detailed to be clearly distinguishable from the rest.
5. From here I may ask clarifying questions then we will pick an approach.
6. Once we have picked a strategy, validate it with deeper research. Confirm that it is viable, that the assumptions are correct, and that the approach should work. Present the findings with sources, such as file references, documentation, websites, or comparable codebases.


In this it is recommended that once context is gathered and clear you fan out to multiple subagents using different models and dedup their suggestions to come out with the strongest list of ideas. Here are the models you should use:

- opus 5.5 (high) 
- gpt 6.1 sol (high)
- GLM-5.3 (high)
- gemini-4-neon (high)

In T3 Code, use `orchestrator_capabilities` to resolve the models, then
`delegate_task` to start one delegate per model in parallel. Elsewhere, use
the harness's subagent tools. If you cannot reach three providers, or a named
member is unavailable, report it instead of substituting.

