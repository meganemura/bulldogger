---
name: bulldogger
description: Use bulldogger failure evidence and targeted probes to inspect Ruby runtime behavior or verify a code change.
compatibility: Uses files from bulldogger 0.2.0. The query examples require jq.
license: MIT
---

# Use bulldogger evidence

Choose the smallest evidence source that answers the question:

- Read an existing failure file when test output has `bulldogger evidence:`. Its frames and locals answer a propagated exception on their own.
- Use `probe` for one method or for a before-and-after behavior check.

Use the available evidence before you add logging or infer values from source.
The evidence `skill` key points to this file when it is available.
Run `bulldogger skill path` to print its installed directory.

Read [failure evidence](references/failure-evidence.md) for snapshot modes, frames, limits, and missing values.
Read [probe evidence](references/probe.md) for method shapes, raised exits, samples, and comparisons.

`probe` is an explicit, expensive verb for one focused run.
The environment disable switches stop capture and probe alike.

## Check the TracePoint visibility limit

Ruby suppresses trace events while a `TracePoint` callback runs.
This rule applies when the target library uses TracePoint, including Bulldogger itself.

A probe reports zero calls when another TracePoint callback invokes every target method.
Read these zeros as "never visible to this probe."
Do not infer that the target methods never ran.

Use timing evidence to locate costs inside the callback.
Use direct or property tests to verify behavior after a change.

## Start from a failure

1. Find the output line with parenthetical guidance.
2. Open the absolute path from that line.
3. Read `capture_mode` before you inspect evidence frames.

If the output is unavailable, inspect `tmp/bulldogger/latest/index.json`.
Each `failures[].path` value is relative to the run directory.
If no evidence exists, check for `BULLDOGGER_DISABLE=1` or `BULLDOGGER_DISABLED=1`.
Either switch prevents file output, so no `frames_unavailable_reason` exists.

Read `capture_mode` before you infer what the file can show.
Then follow the failure reference.
The output parenthetical selects the evidence snapshot.
