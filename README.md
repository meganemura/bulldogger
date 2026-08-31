# bulldogger

bulldogger writes Ruby test failures as structured evidence for coding agents.
Each JSON file contains the exception, the backtrace, and captured frame values.
The failure output gives the absolute path to that file.

Development and snapshot measurements used Ruby 4.0.6 and debug 1.11.1.

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

The CLI has these subcommands:

```text
bulldogger frames -- command...
bulldogger preflight -- command...
bulldogger flt 'path:method#k' [--index path] -- command...
bulldogger exec 'path:method#k' --line N [--visit K] --statement text [--index path] -- command...
bulldogger skill path
bulldogger version
bulldogger --version
```

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
It also provides the failure and probe methods from the module facade.

An integration can use an assigned instance instead of the default:

```ruby
Bulldogger::Minitest.instance = observer
Bulldogger::RSpec.instance = observer
```

Assign the instance before the suite starts.
This separation lets an outer observer remain active while test setup replaces the default instance.

## Cost model

The always-on path captures a failure snapshot.
It does no work for a green test that raises no exception.
Each observed exception costs microseconds.

The snapshot benchmark used Ruby 4.0.6.
It measured 44.126 microseconds for each raise-and-rescue cycle.
Frame capture used 1.288 microseconds of that total.

Re-execution is explicit.
`frames`, `preflight`, `flt`, and `exec` start a new process only when you run them.
`probe` also runs only around a block that you select.

## Start from a failure snapshot

This output came from:

```sh
bundle exec ruby -Ilib test/fixtures/minitest_red/red_test.rb --seed 12345
```

```text
  1) Error:
RedTest#test_deep_raise:
ArgumentError: expected 3 to equal the sum of [1, 2, 3]
    test/fixtures/minitest_red/app.rb:9:in 'Order.total'
    test/fixtures/minitest_red/red_test.rb:20:in 'RedTest#test_deep_raise'
bulldogger evidence: /home/you/project/tmp/bulldogger/run-20260831-192835-69510/001-RedTest-test_deep_raise.json (raising method is in these frames)
bulldogger rerun: bundle exec ruby -Itest test/fixtures/minitest_red/red_test.rb -n /\\Atest_deep_raise\\z/ --seed 12345
```

Open the path on the line with the parenthetical guidance.
The file contains one failure and its captured runtime values.
The rerun line gives the complete command for that test and seed.
bulldogger does not run this command automatically.

Each run uses this layout:

```text
tmp/bulldogger/
  latest -> run-20260829-100406-58231
  run-20260829-100406-58231/
    001-RedTest-test_deep_raise.json
    002-RedTest-test_assertion_failure.json
    index.json
```

The [`bulldogger` skill](skills/bulldogger/SKILL.md) tells an agent how to inspect these files.
The [evidence schema](docs/evidence-schema.md) defines every field and capture mode.

## Index one isolated run with frames

Run the rerun command under `frames`:

```sh
bulldogger frames -- bundle exec ruby -Itest test/fixtures/frames/minitest_frames_test.rb --seed 12345
```

The command prints the index path and the child result:

```text
bulldogger frames: /home/you/project/tmp/bulldogger/frames-69833.jsonl
bulldogger result: pass (exit 0)
```

The index names each call with a frame identifier, or `fid`.
The format is `path:method#k`.
The number counts calls to that method inside the test window.
The index includes application, framework, and gem frames.

## Verify an isolated rerun with preflight

Run `preflight` before `flt` or `exec`:

```sh
bulldogger preflight -- bundle exec ruby -Itest test/fixtures/frames/minitest_frames_test.rb --seed 12345
```

It runs the command twice in separate processes.
It compares the two application-frame sequences.

```text
bulldogger preflight: deterministic (app frames: 3)
bulldogger preflight indexes: /home/you/project/tmp/bulldogger/frames-70427.jsonl /home/you/project/tmp/bulldogger/frames-70432.jsonl
```

Use `flt` or `exec` only when preflight reports `deterministic`.
Both verbs accept application frame identifiers only.

## Trace one frame with flt

Pass an application `fid` and the same isolated command:

```sh
bulldogger flt 'test/fixtures/flt/minitest_flt_test.rb:branchy#1' -- bundle exec ruby -Itest test/fixtures/flt/minitest_flt_test.rb --seed 12345
```

```text
bulldogger flt: /home/you/project/tmp/bulldogger/flt-77206.jsonl
bulldogger result: pass (exit 0)
```

The trace contains the frame entry, line changes, raises, and the return.
It records new locals under `new` and updates under `changed`.
It lists locals that leave scope under `out_of_scope`.
It folds loop middle iterations into `skipped_iterations` records.

Use `--index path` to require the index and rerun to have the same code-state marker.

## Evaluate one statement with exec

Address one line visit inside an application frame:

```sh
bulldogger exec 'test/fixtures/exec/minitest_exec_test.rb:threshold#1' --line 9 --statement 'binding.local_variable_set(:result, 10)' -- bundle exec ruby -Itest test/fixtures/exec/minitest_exec_test.rb --seed 12345 -n test_injection_can_change_the_outcome
```

```text
bulldogger exec: /home/you/project/tmp/bulldogger/exec-77267.jsonl
bulldogger value: 10
bulldogger result: pass (exit 0)
```

`exec` evaluates the statement in the selected frame binding.
The default visit is the first visit to the line.
Use `--visit K` for a later visit.
The launcher gives the child the required `BULLDOGGER_EXEC=1` token.
Use `--index path` to require a matching code-state marker.

The statement can change test behavior and perform side effects.
Read the result file before you use the changed outcome as evidence.

## Seed random values in RSpec

RSpec uses its seed to order examples.
RSpec does not call `Kernel.srand`.
Add this line inside `RSpec.configure` when examples call `rand`:

```ruby
config.before(:suite) { Kernel.srand config.seed }
```

This line lets the printed rerun seed reproduce those random values.
bulldogger does not call `Kernel.srand` for the application.

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

## Cost

`TracePoint(:raise)` observes every raised exception, including exceptions that application code rescues.
These measurements used Ruby 4.0.6.
Each condition has three runs, and the table gives each median.

| condition | without bulldogger | with bulldogger | ratio |
|---|---:|---:|---:|
| 2,000,000 no-op iterations with no raised exception | 0.0423s | 0.0424s | 1.00x |
| 10,000 raise and rescue cycles | 0.0055s | 0.4468s | 81.14x |
| 200 recorded failures with file output | 0.0001s | 0.0277s | 413.58x |

The second condition costs 44.126 microseconds for each exception in this measurement.

The capture cost has this measured breakdown:

| stage | added cost for each exception |
|---|---:|
| Subscribe to `TracePoint(:raise)` | 0.136 microseconds |
| Call `DEBUGGER__.capture_frames` | 1.288 microseconds |
| Serialize, redact, and insert into the ring | 23.220 microseconds |

Frame capture has a small cost in this measurement, while later processing accounts for most of the measured cost.

A green suite with no raised exception caused no measurable overhead in this test.
A green suite can still raise and rescue exceptions, and each exception incurs the capture cost.

### Explicit verb cost

The proportionality harness measured 1461.5 ns per targeted `probe` call.
The frame gate measured about 105 ns per non-target call.

An `flt` line event has a fixed cost near 0.5 microseconds.
Reading each local adds about 0.1 microseconds per line event.
A frame with 20 locals and 10,000 line events cost about 27 ms.

These measurements used Ruby 4.0.6 and the rubygems.org test suite.
The suite had 4,925 tests, seed 12345, and one worker.
The measurements ran on 2026-08-31.

## Disable bulldogger

Set `BULLDOGGER_DISABLE=1` to disable capture and output for one test process.
`BULLDOGGER_DISABLED=1` is an alias with the same behavior.

With either switch, startup returns before the `TracePoint(:raise)` subscription.
It writes no evidence, creates no run directory, and adds no evidence line to a failure.
The test exit code and failure count stay unchanged.
Acceptance tests confirm this behavior for Minitest and RSpec.

A rescue-heavy green suite measured 1.00x with bulldogger disabled.

## Environment variables

These environment variables configure a child test process:

| Variable | Accepted value | Default and effect |
|---|---|---|
| `BULLDOGGER_DISABLE` | `1` | Capture is enabled by default. `1` disables capture and output. |
| `BULLDOGGER_DISABLED` | `1` | Alias for `BULLDOGGER_DISABLE`. |
| `BULLDOGGER_OUTPUT_DIR` | A nonempty path | The default is `tmp/bulldogger`, relative to the working directory. |
| `BULLDOGGER_FRAME_SOURCE` | `capture_frames` or `degraded` | The default is automatic selection. |

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

## Scope of version 0.2

Version 0.2 provides failure snapshots, targeted probes, frame indexes, determinism checks, frame lifetime traces, statement evaluation, and independent instances.
It writes JSON evidence and JSONL artifacts.
Heavy collection starts only through an explicit verb.

The [design decisions](docs/design-decisions.md) explain the evidence model and its measured costs.

## License

MIT. See `LICENSE`.
