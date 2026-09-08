---
name: write-team-update
description: Write team update based on linear issues
agent: build
---

Write a short team update based on linear issues using the linear MCP and github cli to find relevant context. Each task/issue should be prefixed with an emoji for its state

:resolved: -> completed/measuring
:review: -> for things in review. If there is a PR lets also add the link to it. 
:hourglass_flowing_sand: -> in progress
:to-do: -> todo
:no_entry: -> blocked


The order of the issues should be as above, first resolved, then in progress then todo and finally blocked. Give a short description for each as per the example below. For blocked you probably don't want to write anything as most of the time you will not have context on why these things are blocked. Leave it for me.

For the resolved issues you should only take the issues resolved since last update. Updates are on wednesday and friday each week. The output should not be md as its for slack, so no md style links. Wednesday should be (friday, wednesday] so friday exclusive to wednesday inclusive. Friday should be (wednesday, friday].

Make sure to check all the PRs I merged/created since the last relevant update day. Because sometimes i forget to add a linear ticket for them


Example update: 
```txt
:resolved:  Termline cluster membership overrides system. Initial PR sets up must be connected overrides. We will also require must not be connected and must be root.  Of those, the second will be tricky have some ideas but want to discuss with @Mihail Feraru (thank you for always dealing with my crazy ramblings)
:review: Twilio hardening checklist progress. I'm sending a PR to XI and with that we should be good. Although there is no way to manually trigger the twilio alerts so I left one alert at very low to test and doesn't seem to have triggered.... Other than this everything is setup, we have XI using the new twilio project for verify and using a new phone number I purchased there. I also figured out the issue with n8n....

:hourglass_flowing_sand: More termline missing table permissions terraform PR. Some more work needs to be done for this. Speaking to Stav & Alex Holt. Huge thank you to @Gergely Bihary for your help!
:hourglass_flowing_sand: Ship one sample sfx page via termline. I think I will pick something since Rich is out to test.
:hourglass_flowing_sand: Help @Dorian with auth for vertex for elevenhacks

:to-do: Explore a way to have preseeded agent conversations. No progress here yet
:to-do: Investigate issue with EL not being able to send you to contact sales
```
