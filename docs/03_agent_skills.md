# Agent skills

A skill is a written procedure an agent loads on demand. It converts a workflow that currently
lives in someone's head, or in a prompt they retype, into something with a fixed sequence,
fixed inputs, and a definition of done.

## Promote a prompt to a skill when any of these is true

- The workflow has been run more than twice.
- It has an ordering constraint, where step four is wrong if step two was skipped.
- It has a gate, some condition under which the correct action is to stop.
- Two people run it and get different results.
- It encodes a lesson learned from an incident, and that lesson must not be relearned.

## Do not write a skill when

- The task is a single query. That is a view.
- The task is genuinely novel. Let the agent reason, then capture what worked.
- The procedure is not yet stable. A skill written over an unsettled workflow calcifies the
  wrong version of it.

## Structure

A skill is a folder with `SKILL.md` at its root. The front matter is what the agent matches
against, so it carries the trigger vocabulary; the body carries the procedure.

```markdown
---
name: weekly-title-report
description: >
  Produce the weekly title performance report. Use for: weekly report,
  title report, Monday numbers, performance recap. Triggers: weekly report,
  title performance, recap, Monday report.
---

# Weekly title report

## Preconditions
Confirm before doing anything else. Stop and report if any fails.
1. Curated layer refreshed within 24 hours.
2. Validation gates in `sql/50_validation_gates.sql` return zero rows.

## Steps
1. Query the semantic layer for the six standing metrics. Do not hand-write SQL.
2. Retrieve narrative context from the Search service, filtered to the reporting week.
3. Render the four approved charts.
4. Write the summary. State the conclusion first.

## Acceptance
- Every figure traces to a semantic-layer metric name.
- Week-over-week deltas reconcile against last week's published report.
- No figure appears that is not in the metric set.
```

Three properties make this work: **preconditions that can fail**, **steps that name the layer
to query rather than the SQL to write**, and **acceptance criteria a reviewer can check
without rerunning the work**.

## Cost effect

Skills can reduce token cost in three ways. Measure the effect on the actual workflow.

**Bounded exploration.** The agent stops searching for an approach when the approach is
written down.

**Fewer retries.** Preconditions catch the state problems that otherwise surface as a failed
step and a retry loop.

**Less rediscovery.** A skill that names the tables, grain, and known traps can reduce
repeated schema exploration. The agent still needs to verify context that may have changed.

The counterweight: a skill loads into context, so its length is a per-invocation cost. Keep
the entry file short and push detail into reference files the agent reads only when it needs
them.

## Skills that only say no

An important skill in a DS workflow is a gate that produces only a verdict. Before a
model scores, before a report publishes, before a number reaches a stakeholder, a validation
skill checks the inputs and refuses to proceed if they are wrong. See
`skills/model-validation-gate/`.

Run stable checks as SQL or scripts with a blocking exit condition. An independent
subagent can review ambiguous findings or high-risk changes when isolation adds value,
but it also consumes tokens. A Markdown instruction cannot enforce a budget or make
an LLM deterministic. Missing dependencies, execution errors, empty sources, and disabled
checks must not be reported as PASS. See [CoCo efficiency](08_coco_token_efficiency.md).
