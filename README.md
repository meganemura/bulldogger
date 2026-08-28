# bulldogger

bulldogger writes Ruby test failures as structured evidence for coding agents.
Each JSON file contains the exception, the backtrace, and captured frame values.
The failure output gives the absolute path to that file.

Development and measurements used Ruby 4.0.6 and debug 1.11.1.
Publication of bulldogger 0.1.0 is pending.

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

## Failure output

This output came from:

```sh
bundle exec ruby -Ilib test/fixtures/minitest_red/red_test.rb
```

```text
  2) Error:
RedTest#test_deep_raise:
ArgumentError: expected 3 to equal the sum of [1, 2, 3]
    test/fixtures/minitest_red/app.rb:9:in 'Order.total'
    test/fixtures/minitest_red/red_test.rb:20:in 'RedTest#test_deep_raise'
bulldogger evidence: /home/you/project/tmp/bulldogger/run-20260828-173512-6178/002-RedTest-test_deep_raise.json
```

Open the path after `bulldogger evidence:`.
The file contains one failure and its captured runtime values.

Each run uses this layout:

```text
tmp/bulldogger/
  latest -> run-20260828-173512-6178
  run-20260828-173512-6178/
    001-RedTest-test_assertion_failure.json
    002-RedTest-test_deep_raise.json
    index.json
```

The [`bulldogger` skill](skills/bulldogger/SKILL.md) tells an agent how to inspect these files.
The [evidence schema](docs/evidence-schema.md) defines every field and capture mode.

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

## Disable bulldogger

Set `BULLDOGGER_DISABLE=1` to disable capture and output for one test process.
`BULLDOGGER_DISABLED=1` is an alias with the same behavior.

With either switch, startup returns before the `TracePoint(:raise)` subscription.
It writes no evidence, creates no run directory, and adds no evidence line to a failure.
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

bulldogger also checks keys while it renders a Hash.
A matching key has the string `"[REDACTED]"` as its rendered value.

The defaults keep 20 frames and 50 locals for each frame.
Each rendered value keeps 200 characters, and each Array or Hash keeps 10 elements.
The evidence file marks omitted or truncated data.

## Scope of version 0.1

Version 0.1 captures at `:raise` and writes JSON files.
It has no `probe` verb, `record` verb, CLI, SQLite store, or full execution trace.

Full method tracing measured 60x to 106x the baseline.
The [design decisions](docs/design-decisions.md) explain the capture design and its measured alternatives.

## License

MIT. See `LICENSE`.
