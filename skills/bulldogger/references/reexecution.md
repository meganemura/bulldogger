# Read re-execution output

`preflight`, `frames`, `flt`, and `exec` each start one new process for the command after `--`. None of them select a test or change command arguments; the command is yours, unedited.

## preflight

`preflight` runs the command twice, in separate processes, and compares the two application-frame sequences before you trust `flt` or `exec` to find the same target twice.

Exit codes:

| Exit | Meaning |
|---|---|
| `0` | The two runs matched. Prints `deterministic (app frames: N)` and both frames index paths. |
| `1` | The two runs diverged. Prints the first mismatched frame and refuses re-execution for this test. |
| `2` | The command failed to start, or produced no frame summary. |

A divergence prints:

```text
bulldogger preflight: first divergence at event 2
first: (call, path/to/test.rb:6, stable_branch)
second: (call, path/to/test.rb:10, alternate_branch)
app frames: 2 and 2
This test is not eligible for bulldogger re-execution.
```

The `(event, path:line, method)` tuple names the mismatch directly, so you do not need to open either index by hand to see where the two runs split.

## frames

The index has one JSON object per line, in a `.jsonl` file. Each process writes its own file, named with its PID.

A `frame` record:

| Field | Type | Meaning |
|---|---|---|
| `type` | String | `frame`. |
| `event` | String | `call` or `b_call`. A `b_call` is a block that sits outside any `def` (an RSpec `it do...end`, a class-body block). |
| `fid` | String | `path:method#k`. `k` counts calls to that method inside the test window. |
| `parent` | String or null | The `fid` of the active caller. |
| `method` | String | Normalized method name. A nameless block is `"block"`. |
| `path` | String | Absolute source path. |
| `lineno` | Integer | Source line. |
| `app` | Boolean | `true` when the source sits under the command's own directory, outside `vendor/bundle`. |

A `return` record names the `fid` that returned, with the same `event` (`return` or `b_return`), `method`, `path`, `lineno`, and `app` fields.

A `raise` record adds `exception_class` and `raise_ordinal`, the count of `:raise` events since the test started. It includes raises the application rescues.

The final `envelope` record has `schema_version`, `code_state` (the git commit and dirty-state digest), `seed` (parsed from the command), `command`, `exit_status`, and `outside_window_events` (events observed before or after the test window — nonzero when the command runs more than the one selected test).

A block frame is never a valid `flt` or `exec` target: both verbs gate on `:call`/`:return`, and a block has no `Method` object to target. `flt`/`exec` read the index's own `event` field to catch this even when the fid text reads like an ordinary call (a block nested inside a `def` keeps its enclosing method's name).

List the application frames:

```sh
jq -c 'select(.type == "frame" and .app == true) | {fid, event, method}' frames.jsonl
```

Find one frame's `fid` by method name:

```sh
jq -c 'select(.type == "frame" and .method == "total")' frames.jsonl
```

### Cross-check a snapshot's raise_ordinal against a frames run

A failure snapshot's `raise_ordinal` and a `frames` run's `raise` record `raise_ordinal` both count `:raise` events since the test started, but they come from different processes and can disagree: a fresh process can rescue extra exceptions during lazy loading that the suite process already paid for before this test began. Trust the `frames` run's ordinal as the address. Use the snapshot's `(path, lineno, exception class)` triple as a cross-check. When the `frames` run's raise at that ordinal has a different path, line, or exception class than the snapshot recorded, the failure reproduced with a different face — a diagnosis in itself, pointing at test-order dependence or state contamination rather than at a broken bridge.

## flt

The trace has one JSON object per line.

A `call` record opens it: `fid` (the selected frame), `args` (rendered entry arguments by name), `locals` (every visible entry local by name).

A `line` record has `lineno` and, only when something changed:

| Field | Type | Meaning |
|---|---|---|
| `new` | Object | Locals that became visible, with rendered values. |
| `changed` | Object | Updated locals, with `old` and `new` rendered values. |
| `out_of_scope` | Array of String | Local names that stopped being visible (left a block, or a rescue clause ended). |

Apply `out_of_scope`, then `new`, then `changed`, in that order, to reconstruct the visible locals at any line.

A `skipped_iterations` record replaces a loop's folded middle iterations. Its `count` gives the number folded away; the trace keeps the first and last iteration, so a defect inside a middle iteration stays outside the trace.

A `raise` record has `exception_class` and a rendered `message`. A `return` record has the rendered return `value`.

The final `envelope` has `schema_version`, `code_state`, `command`, and `exit_status`. When the target's *k*th call never happens in the test window, the trace has no `call`/`line`/`return` record; the envelope instead carries `observed_calls`, `target_index`, and `traced: false`, and the launcher prints:

```text
bulldogger note: target was never traced (method called 2 times in the test window, target was call #5)
```

`--index path` requires the frames index and this `flt` run to share the same `code_state`. A mismatch refuses with both markers:

```text
bulldogger flt: code state mismatch
index git_sha="old" dirty_digest="old-dirty"
run git_sha="<current sha>" dirty_digest="<current digest>"
```

A non-application target (a gem or framework frame) refuses the same way in `flt` and `exec`:

```text
bulldogger flt: target is not an application frame; use the frames index, read the gem source, or use probe
```

A block-frame target, addressed with `--index`, refuses and names its nearest addressable ancestor:

```text
bulldogger flt: 'path/to/test.rb:branchy#2' is a block frame; flt cannot target a block directly
target its nearest addressable ancestor instead: 'path/to/test.rb:branchy#1'
```

List a trace's line-by-line changes:

```sh
jq -c 'select(.type == "line")' flt.jsonl
```

## exec

The result file has one JSON object per line.

An `evaluation` record: `fid`, `line`, `visit`, and either `value` (rendered) or `exception_class` with a rendered `message`.

The launcher appends a `result` record: the same address fields, `outcome` (`pass`, `fail`, or `error`), `exit_status`, and the evaluation fields when evaluation ran.

The final `envelope` has `schema_version`, `code_state`, and `command`. When the target's *k*th call never happens, no `evaluation` record exists; the envelope carries `observed_calls`, `target_index`, and `traced: false`, the same shape `flt` uses, and the launcher prints the same `target was never traced` note.

When the call happens but the addressed line never reaches the requested visit, the collector writes an `evaluation_summary` record instead, and the envelope carries `line_visits_observed`, `target_visit`, and `evaluated: false`:

```text
bulldogger note: statement was never evaluated (line 23 visited 1 time in call #1, target was visit #2)
```

`BULLDOGGER_EXEC=1` gates statement injection. The re-execution launcher sets this token for the child process. Without it, the collector never activates: no statement runs, and no evaluation record is written. An address alone cannot run a statement outside a launched re-execution.

`exec` shares `flt`'s application-frame and block-frame refusals, and the same `--index path` code-state check.

Read a result's value:

```sh
jq -c 'select(.type == "result") | .value.value' exec.jsonl
```

Redacted and truncated values use the same rules as failure evidence: see [failure evidence](failure-evidence.md).
