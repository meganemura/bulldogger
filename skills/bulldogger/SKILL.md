---
name: bulldogger
description: Use bulldogger failure evidence, targeted probes, and full records to inspect Ruby runtime behavior or verify a code change.
compatibility: Uses files from bulldogger 0.1.0. The query examples require jq. SQLite conversion requires the optional sqlite3 gem.
license: MIT
---

# Use bulldogger evidence

Choose the smallest evidence source that answers the question:

- Read an existing failure file when test output has `bulldogger evidence:`.
- Use `probe` for one method or for a before-and-after behavior check.
- Use `record` when you must follow the full call sequence.

Use the available evidence before you add logging or infer values from source.
The evidence `skill` key points to this file when it is available.
Run `bulldogger skill path` to print its installed directory.

Read [failure evidence](references/failure-evidence.md) for snapshot modes, frames, limits, and missing values.
Read [probe evidence](references/probe.md) for method shapes, raised exits, samples, and comparisons.
Read [record traces](references/record.md) for JSONL events, limits, and queries.

`probe` and `record` are explicit, expensive verbs for one focused run.
The environment disable switches stop all three approaches.

## Start from a failure

1. Find the `bulldogger evidence:` line in the test output.
2. Open the absolute JSON path from that line.
3. Read `capture_mode` before you inspect `frames`.

If the output is unavailable, inspect `tmp/bulldogger/latest/index.json`.
Each `failures[].path` value is relative to the run directory.
If no evidence exists, check for `BULLDOGGER_DISABLE=1` or `BULLDOGGER_DISABLED=1`.
Either switch prevents file output, so no `frames_unavailable_reason` exists.

Read `capture_mode` before you infer what the file can show.
Then follow the failure reference.
