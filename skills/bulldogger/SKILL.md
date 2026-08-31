---
name: bulldogger
description: Use bulldogger failure evidence and re-execution verbs to inspect Ruby runtime behavior or verify a code change.
compatibility: Uses files from bulldogger 0.2.0. The query examples require jq.
license: MIT
---

# Use bulldogger evidence

Start from the failure output, not the source. A failed test prints two lines:

```text
bulldogger evidence: /absolute/path/to/evidence.json (raising method is in these frames)
bulldogger rerun: bundle exec ruby -Itest path/to/test.rb -n /\\Atest_name\\z/ --seed 12345
```

Open the evidence path. Its parenthetical names what the file holds:

- `(raising method is in these frames)`: the snapshot already answers. Read [failure evidence](references/failure-evidence.md).
- `(frames do not show where the value came from)`: the method that produced the value had already returned before the assertion raised, so the snapshot's frames hold no trace of it. Run the rerun command under `frames` (below) to reach that call.
- `(snapshot holds no frames)`: capture missed this exception. `frames_unavailable_reason` in the file names why; read [failure evidence](references/failure-evidence.md).

bulldogger never runs the rerun command for you.
Use the available evidence before you add logging or infer values from source.
The evidence `skill` key points to this file when it is available.
Run `bulldogger skill path` to print its installed directory.

## Verify determinism with preflight

`frames`, `flt`, and `exec` each re-run one test in a fresh process, and `flt` and `exec` depend on a `fid` addressing the same call in that fresh run that it addressed before. Confirm that reproducibility before you rely on it:

```sh
bulldogger preflight -- bundle exec ruby -Itest path/to/test.rb --seed 12345
```

It runs the command twice, in separate processes, and compares the two application-frame sequences:

```text
bulldogger preflight: deterministic (app frames: 3)
bulldogger preflight indexes: /absolute/path/frames-<pid>.jsonl /absolute/path/frames-<pid>.jsonl
```

Proceed to `frames`, `flt`, or `exec` only on `deterministic`. A divergence names the first mismatched frame by event, path, line, and method, and states that the test is not eligible for bulldogger re-execution:

```text
bulldogger preflight: first divergence at event 2
first: (call, path/to/test.rb:6, stable_branch)
second: (call, path/to/test.rb:10, alternate_branch)
app frames: 2 and 2
This test is not eligible for bulldogger re-execution.
```

A divergence usually means the test depends on order-sensitive state (hash iteration order, object IDs, timing) rather than only its seed. Re-execution cannot address a target it cannot re-find, so stop here for this test.

## Index calls with frames

Run the printed rerun command under `frames`:

```sh
bulldogger frames -- bundle exec ruby -Itest path/to/test.rb -n /\\Atest_name\\z/ --seed 12345
```

```text
bulldogger frames: /absolute/path/frames-<pid>.jsonl
bulldogger result: fail (exit 1)
```

The index has one `frame` record per call or block entry, in a `.jsonl` file:

```json
{"type": "frame", "fid": "path/to/app.rb:total#1", "app": true, "path": "path/to/app.rb", "lineno": 8, "method": "total"}
```

`fid` reads `path:method#k`: `k` counts calls to that method inside the test window, so it survives the move to a second process even though a process-wide frame number does not. `app: true` marks a frame under the project's own source, as opposed to a framework or gem frame. Find the `app` frame for the method that produced the value you need, and pass its `fid` to `flt` or `exec`.

A `raise` record in the same index carries `raise_ordinal`, the count of `:raise` events since the test started. Cross-check it against the failure snapshot's own `raise_ordinal`, and against the snapshot's `(path, lineno, exception class)`. Trust the frames run's ordinal as the address: a fresh process can rescue extra exceptions during lazy loading that the suite process already paid for before this test began, which shifts the ordinal. A mismatch at a different path, line, or exception class is a diagnosis by itself — the failure reproduced with a different face, which points to test-order dependence or state contamination rather than to a broken bridge.

## Trace one frame with flt

Pass an application `fid` and the same isolated command `frames` used:

```sh
bulldogger flt 'path/to/test.rb:branchy#1' -- bundle exec ruby -Itest path/to/test.rb --seed 12345
```

```text
bulldogger flt: /absolute/path/flt-<pid>.jsonl
bulldogger result: pass (exit 0)
```

The trace opens with a `call` record holding full entry `args` and `locals`. Each later `line` record then carries only what changed: `new` for locals that came into view, `changed` for updated ones (with `old` and `new`), and `out_of_scope` for locals that left a block or a rescue clause. Apply `out_of_scope`, then `new`, then `changed`, in that order, to reconstruct the visible locals at any line. A `skipped_iterations` record replaces a loop's folded middle; the trace keeps the first and last iteration, and `count` gives the number folded away — those values stayed unobserved. `raise` and `return` records close the trace.

When the target call never happens in the test window, the trace has no `call`, `line`, or `return` record. `flt` prints a note instead, naming the real call count so you can pick a reachable `k`:

```text
bulldogger note: target was never traced (method called 2 times in the test window, target was call #5)
```

Read [re-execution](references/reexecution.md) for the full field reference.

## Evaluate one statement with exec

Address one line visit inside an application frame:

```sh
bulldogger exec 'path/to/test.rb:threshold#1' --line 9 --statement 'binding.local_variable_set(:result, 10)' -- bundle exec ruby -Itest path/to/test.rb --seed 12345
```

```text
bulldogger exec: /absolute/path/exec-<pid>.jsonl
bulldogger value: 10
bulldogger result: pass (exit 0)
```

`exec` evaluates the statement inside the selected frame's own binding, at the given line and visit. The default visit is the first one; use `--visit K` for a later visit. When the target call or the target visit never happens, `exec` prints a `bulldogger note:` line instead of a value, the same way `flt` does for an unreached call.

`BULLDOGGER_EXEC=1` gates statement injection. The re-execution launcher sets this token for the child process; do not set it by hand. A statement running outside a launched re-execution defeats the gate the design puts there on purpose.

The statement can raise, change local state, and change the test's outcome, so read the result file before you use the changed outcome as evidence.

`flt` and `exec` both refuse a target outside the project's own source. The refusal names the alternatives: the frames index to navigate, the gem source to read, and `probe` to observe a gem method without a call index. Use `--index path` on either verb to require that the frames index and this re-execution share the same code-state marker (the git commit and the dirty-state digest); a mismatch means the index points at line numbers the current code no longer has.

## Target a method with probe

Use a probe when one method defines the behavior you need to inspect, or when you want to compare that behavior before and after a change.

```ruby
path = Bulldogger.probe("Billing::Invoice#amount") do
  run_related_test
end
```

Read `methods` by target name. Each target has call counts, parameters, argument shapes, return shapes, raised exits, and callers.

`probe` is an explicit, expensive verb for one focused run.
Read [probe evidence](references/probe.md) for method shapes, raised exits, samples, and comparisons.

## Check the TracePoint visibility limit

Ruby suppresses trace events while a `TracePoint` callback runs.
This rule applies when the target library uses TracePoint, including Bulldogger itself.

A probe reports zero calls when another TracePoint callback invokes every target method.
Read these zeros as "never visible to this probe."
Do not infer that the target methods never ran.

Use timing evidence to locate costs inside the callback.
Use direct or property tests to verify behavior after a change.

The environment disable switches (`BULLDOGGER_DISABLE=1`, `BULLDOGGER_DISABLED=1`) stop capture and probe alike. They do not stop `frames`, `preflight`, `flt`, or `exec`; those verbs run only when you invoke them, so the switch has nothing to add there.
