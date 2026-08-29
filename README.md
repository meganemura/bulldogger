# bulldogger

bulldogger writes Ruby test failures as structured evidence for coding agents.
Each JSON file contains the exception, the backtrace, and captured frame values.
The failure output gives the absolute path to that file.

Development and measurements used Ruby 4.0.6 and debug 1.11.1.
bulldogger 0.2.0 adds independent instances and extends dogfooding to the unit suite.

## Install

Add both gems to the test group:

```ruby
gem "bulldogger", group: :test
gem "debug", group: :test
```

The `debug` gem supplies `DEBUGGER__.capture_frames`, which gives bulldogger locals from each frame.
Ruby distributes `debug` as a bundled gem.
Bundler only exposes it when the application Gemfile includes it.

Without `debug`, bulldogger records locals from the raising frame.
It records file, line, and label data for the remaining frames.

Install the skill on an agent host from the default branch:

```sh
gh skill install meganemura/bulldogger
```

Use the copy that matches the installed gem when version alignment matters:

```sh
bulldogger skill path
```

The first command installs the skill on the agent host. The second command prints the matching gem copy.

Add one framework entry point.

For Minitest, add this line to `test_helper.rb`:

```ruby
require "bulldogger/minitest"
```

For RSpec, add this line to `spec_helper.rb`:

```ruby
require "bulldogger/rspec"
```

Each entry point starts capture and records each failed test.
It finishes the run index when the suite ends.

## Use independent instances

The `Bulldogger` module delegates its API to `Bulldogger.default`.
Existing calls such as `Bulldogger.start` and `Bulldogger.probe` use that default instance.

Create a separate instance when two capture lifecycles must run at the same time:

```ruby
observer = Bulldogger::Instance.new
observer.start
```

Each instance owns its configuration, capture subscription, run, and evidence state.
It also provides the failure, probe, record, and SQLite conversion methods from the module facade.

An integration can use an assigned instance instead of the default:

```ruby
Bulldogger::Minitest.instance = observer
Bulldogger::RSpec.instance = observer
```

Assign the instance before the suite starts.
This separation lets an outer observer remain active while test setup replaces the default instance.

## Three approaches

bulldogger provides three ways to collect runtime evidence:

- A failure snapshot is the default. Green tests do not capture data when they raise no exception. The snapshot answers a propagated exception from its frames and locals. For an assertion, bulldogger replays the test once under full recording because the application call has returned.
- `probe` watches named methods during one explicit run.
- `record` traces all Ruby method calls during one explicit run.

Use a failure snapshot when a failed test already provides an evidence path.
Use `probe` to inspect one method or to compare behavior before and after a change.
Use `record` when you must follow the full call sequence.

## Failure output

This output came from:

```sh
bundle exec ruby -Ilib test/fixtures/minitest_red/red_test.rb
```

```text
  1) Error:
RedTest#test_deep_raise:
ArgumentError: expected 3 to equal the sum of [1, 2, 3]
    test/fixtures/minitest_red/app.rb:9:in 'Order.total'
    test/fixtures/minitest_red/red_test.rb:20:in 'RedTest#test_deep_raise'
bulldogger evidence: /home/you/project/tmp/bulldogger/run-20260829-100406-58231/001-RedTest-test_deep_raise.json (raising method is in these frames)
```

Open the path on the line with the parenthetical guidance.
The file contains one failure and its captured runtime values.
The evidence file has `replay_skipped_reason: "application_frame_available"` for this propagated exception. Its `Order.total` frame contains the application locals, so replay did not run.

The `bulldogger replay:` line appears when replay runs for a failure. Its parenthetical identifies a reproduced failure or a passing replay. Read [Replay a failing test](#replay-a-failing-test) for the rule, settings, and side effect.

Each run uses this layout:

```text
tmp/bulldogger/
  latest -> run-20260829-100406-58231
  run-20260829-100406-58231/
    001-RedTest-test_deep_raise.json
    002-RedTest-test_assertion_failure.json
    trace-001.jsonl
    index.json
```

The [`bulldogger` skill](skills/bulldogger/SKILL.md) tells an agent how to inspect these files.
The [evidence schema](docs/evidence-schema.md) defines every field and capture mode.

## Replay a failing test

An assertion raises after the code under test already returned. The failure snapshot then holds the test framework and the test body, and no application frames. More frames do not help. The call that produced the wrong value already left the stack.

bulldogger reruns that one failing test under full recording to reach the value. An exception has a different shape. Its application code remains on the stack while the exception propagates. The snapshot already holds that code and its locals, so bulldogger skips replay.

The default rule counts application frames outside the test file. Zero such frames causes replay. One or more such frames cause a skip with `replay_skipped_reason: "application_frame_available"`. A missing `replay` key with this reason means the frames already answer the question.

Replay runs in a child process, so the parent suite's result stays unchanged. A green run replays nothing, so the zero-cost-when-green property still holds. The added cost applies only after an assertion-shaped failure, once by default, in an isolated process.

Evidence gains a `replay` key with the absolute path to the trace. It also gains a `replay_reproduced` key. This key is `true` when the child failed the same way, and `false` when the child passed. A `false` value means the failure did not reproduce alone. This usually points to a test that depends on run order or on state shared with another test.

Failure output marks the file that contains the useful runtime data:

```text
bulldogger evidence: /abs/path/evidence.json
bulldogger replay: /abs/path/trace.jsonl (value was produced before the assertion raised)
```

A passing replay uses `(test passed alone; this trace shows the passing run)`.
When replay cannot run, the evidence line says that its frames do not show where the value came from.
When replay is off, the evidence parenthetical also names `BULLDOGGER_REPLAY=1`.
A missed capture says that the snapshot holds no frames.

Replay settings:

| Attribute | Default | Effect |
|---|---|---|
| `replay_on_failure` | `true` | Replays when the frames contain no application code outside the test file. `:always` replays every failure. `false` never replays. |
| `max_replays` | `1` | Caps the number of replays for one run. |
| `replay_timeout` | `60` | Seconds before bulldogger cancels the replay child. A cancelled replay writes no `replay` or `replay_reproduced` key. |

Replay runs fewer tests under the default rule. A replayed test still performs each side effect again: a file write, an external request, or a sandbox account change. Set `BULLDOGGER_REPLAY=0` to turn off replay for one process. Set `BULLDOGGER_REPLAY=always` to replay every failure. Set `config.replay_on_failure` to `false` or `:always` for the same application policies. `BULLDOGGER_MAX_REPLAYS` overrides the cap. `BULLDOGGER_DISABLE=1` turns off replay along with every other capture.

The [replay reference](skills/bulldogger/references/replay.md) tells an agent how to narrow a trace to the value's origin.
The [trace schema](docs/trace-schema.md) defines the event fields a replay trace holds.

## Target a method with probe

Wrap the relevant test or operation with a named target:

```ruby
before_path = Bulldogger.probe("Billing::Invoice#amount") do
  run_related_test
end
```

The evidence summarizes argument and return classes, `nil` values, raised exits, and callers.
It serializes the first 10 samples by default and counts every call.

Run the probe before and after a change, then compare the two files:

```ruby
result = Bulldogger.probe_compare(before_path, after_path)
result.fetch("identical")
```

An `identical` value of `true` shows that the compared behavior stayed the same.
The comparison covers call counts, classes, `nil` counts, raised exits, parameters, callers, and normalized samples.

This excerpt came from a generated probe file:

```json
{
  "kind": "probe",
  "targets": ["ProseSample#amount"],
  "methods": {
    "ProseSample#amount": {
      "calls": 3,
      "raised_exits": 1,
      "returns": {
        "classes": {"Integer": 1, "NilClass": 1},
        "nil_count": 1,
        "samples": [{"value": "21"}, {"value": "nil"}]
      },
      "raised": {"ArgumentError": 1},
      "callers": {"-e:1:in 'block in <main>'": 3}
    }
  },
  "limits": {"max_samples": 10, "max_value_length": 200}
}
```

## Record the call sequence

Wrap one focused operation when you need a full call sequence:

```ruby
trace_path = Bulldogger.record do
  run_related_test
end
```

The result is a JSONL file with a header and one object for each call, return, or raise event.
This excerpt came from a generated trace:

```jsonl
{"schema_version":1,"kind":"record","events":["call","return","raise"],"limits":{"max_value_length":200}}
{"event":"call","seq":1,"depth":1,"path":"-e","line":1,"method":"ProseTrace#outer","args":{"value":{"value":"3"}}}
{"event":"return","seq":4,"depth":1,"path":"-e","line":1,"method":"ProseTrace#outer","return":{"value":"6"}}
{"event":"raise","seq":7,"depth":2,"path":"-e","line":1,"method":"ProseTrace#inner","exception":{"class":"ArgumentError","message":"negative"}}
{"event":"return","seq":8,"depth":2,"path":"-e","line":1,"method":"ProseTrace#inner","raised":true}
```

The [trace schema](docs/trace-schema.md) defines the event fields and tested `jq` queries.

JSONL is the primary record format.
`Bulldogger.trace_to_sqlite(trace_path, db_path)` converts an existing trace when the `sqlite3` gem is available.
The converter uses a soft require, so bulldogger keeps zero runtime dependencies.

## Cost

`TracePoint(:raise)` observes every raised exception, including exceptions that application code rescues.
These measurements used Ruby 4.0.6.
Each condition has three runs, and the table gives each median.

| condition | without bulldogger | with bulldogger | ratio |
|---|---:|---:|---:|
| 2,000,000 no-op iterations with no raised exception | 0.0389s | 0.0387s | 0.99x |
| 10,000 raise and rescue cycles | 0.0052s | 0.4256s | 82.60x |
| 200 recorded failures with file output | 0.0001s | 0.0252s | 412.85x |

The second condition costs 42.042 microseconds for each exception.
Repeated runs measured 40 to 42 microseconds and 76x to 83x.

The capture cost has this measured breakdown:

| stage | added cost for each exception |
|---|---:|
| Subscribe to `TracePoint(:raise)` | 0.019 microseconds |
| Call `DEBUGGER__.capture_frames` | 1.411 microseconds |
| Serialize, redact, and insert into the ring | 24.198 microseconds |

Frame capture has a small cost in this measurement, while later processing accounts for most of the measured cost.

A green suite with no raised exception caused no measurable overhead in this test.
A green suite can still raise and rescue exceptions, and each exception incurs the capture cost.

### Explicit verb cost

The proportionality harness used one app fixture for both verbs.
It measured 1353.3 ns per targeted method call for `probe`.
It measured 3872.2 ns per traced call for `record`.

`probe` cost scales with calls to the targeted method, which the harness names M.
`record` cost scales with all traced calls, which the harness names N.
With M/N at 0.25, the fixture measured `probe` at 9.07x and `record` at 103.72x.
These ratios describe this app fixture, and another app has a different M/N value.

The record-specific harness measured value capture at 34.18x.
The complete path, including the JSONL write, measured 50.56x.

`probe` and `record` are explicit verbs for one focused run before or after a change.
Do not apply either verb continuously to the full suite.

## Disable bulldogger

Set `BULLDOGGER_DISABLE=1` to disable capture and output for one test process.
`BULLDOGGER_DISABLED=1` is an alias with the same behavior.

With either switch, startup returns before the `TracePoint(:raise)` subscription.
It writes no evidence, creates no run directory, and adds no evidence line to a failure.
Replay does not run either, because replay starts from the evidence step that this switch skips.
The test exit code and failure count stay unchanged.
Acceptance tests confirm this behavior for Minitest and RSpec.

A rescue-heavy green suite measured 0.99x with bulldogger disabled.

## Environment variables

These environment variables configure a child test process:

| Variable | Accepted value | Default and effect |
|---|---|---|
| `BULLDOGGER_DISABLE` | `1` | Capture is enabled by default. `1` disables capture and output. |
| `BULLDOGGER_DISABLED` | `1` | Alias for `BULLDOGGER_DISABLE`. |
| `BULLDOGGER_OUTPUT_DIR` | A nonempty path | The default is `tmp/bulldogger`, relative to the working directory. |
| `BULLDOGGER_FRAME_SOURCE` | `capture_frames` or `degraded` | The default is automatic selection. |
| `BULLDOGGER_REPLAY` | `0`, `1`, or `always` | The default is `1`. It replays when the frames cannot answer. `0` disables replay. `always` replays every failure. |
| `BULLDOGGER_MAX_REPLAYS` | An integer | Overrides `max_replays`, the number of replays for one run. The default is `1`. |

## Secrets and limits

Captured values can contain secrets.
bulldogger checks each local name before it calls `inspect` on the value.
A matching local becomes `{"redacted": true, "reason": "name"}` and has no `value` field.

The default patterns match these names without regard to case:

- `password`, `passwd`, and `pass`
- `secret` and `token`
- `api_key` and `api-key`
- the word `key`
- `credential`, `auth`, `session`, and `cookie`

The patterns favor redaction when a name is ambiguous.
For example, `/auth/i` also matches `author` and `authorized`.
Applications can replace `Bulldogger.config.redact_patterns` with their own regular expressions.
Bulldogger compiles these patterns into one union when it constructs a redactor.
An in-place change to the source array does not change an existing redactor.
Assign a new pattern array before Bulldogger constructs the capture or trace session that will use it.

bulldogger also checks keys while it renders a Hash.
A matching key has the string `"[REDACTED]"` as its rendered value.

The defaults keep 20 frames and 50 locals for each frame.
Each rendered value keeps 200 characters, and each Array or Hash keeps 10 elements.
The evidence file marks omitted or truncated data.

## Scope of version 0.1

Version 0.1 provides failure snapshots, targeted probes, and explicit full records.
It writes JSON evidence and JSONL traces.
The version 0.1 boundary exposes file artifacts and an offline SQLite converter.

The [design decisions](docs/design-decisions.md) explain the three approaches and their measured costs.

## License

MIT. See `LICENSE`.
