---
name: bulldogger
description: Use bulldogger failure evidence, targeted probes, and full records to inspect Ruby runtime behavior or verify a code change.
compatibility: Uses files from bulldogger 0.2.0. The query examples require jq. SQLite conversion requires the optional sqlite3 gem.
license: MIT
---

# Use bulldogger evidence

Choose the smallest evidence source that answers the question:

- Read an existing failure file when test output has `bulldogger evidence:`. Its frames and locals answer a propagated exception on their own.
- Read its replay trace when an assertion raised after the producing method returned.
- Use `probe` for one method or for a before-and-after behavior check.
- Use `record` when you must follow the full call sequence.

Use the available evidence before you add logging or infer values from source.
The evidence `skill` key points to this file when it is available.
Run `bulldogger skill path` to print its installed directory.

Read [failure evidence](references/failure-evidence.md) for snapshot modes, frames, limits, and missing values.
Read [probe evidence](references/probe.md) for method shapes, raised exits, samples, and comparisons.
Read [record traces](references/record.md) for JSONL events, limits, and queries.
Read [replay traces](references/replay.md) for the decision between snapshot frames and a replay trace.

`probe` and `record` are explicit, expensive verbs for one focused run.
Replay runs automatically when a failure's frames cannot answer, once by default, in a child process.
The environment disable switches stop all three approaches, and they stop replay too.

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
The output parenthetical selects the evidence snapshot or the replay trace.
Check `replay_reproduced` before you interpret a replay trace as a failing run.

A missing `replay` key with `replay_skipped_reason: "application_frame_available"` means the frames contain the raising method. Do not search for a replay trace in this case.
