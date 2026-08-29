# Design decisions

These decisions define the failure capture path in bulldogger 0.1.0.
The measurements used Ruby 4.0.6 and debug 1.11.1.

## Capture only raised exceptions

An early design traced each method call and return.
Measurements placed its run time at 60x to 106x the baseline.
That cost applied throughout each test run.

bulldogger subscribes to `TracePoint(:raise)`.
The subscription produces no capture work until Ruby raises an exception.

## Build no shadow stack

Another design kept each frame `Binding` in a shadow call stack.
A `TracePoint` updated the stack on every call and return.
Measurements placed this design at 9x to 18x the baseline.

bulldogger asks `DEBUGGER__.capture_frames` for the stack when Ruby raises.
This choice removes the continuous call and return work.

## Use one frame capture call

`binding_of_caller` can return a caller binding.
Repeated calls intended to walk outward returned the same frame during testing.
This behavior made the captured stack incorrect.

`DEBUGGER__.capture_frames` returns the available frame bindings in one call.

## Serialize during the raise hook

A `DEBUGGER__::FrameInfo` holds a live `Binding`.
The binding keeps objects reachable from its frame alive.

A measurement retained a frame from a `TracePoint` block.
The retained binding could still reach the block's captured array.
Keeping frame objects would let a bounded entry ring retain unbounded object graphs.

bulldogger renders values before the `:raise` hook returns.
The pending ring then holds Hashes, Strings, numbers, and Boolean values.
It holds no captured `FrameInfo` or `Binding`.

The full capture path measured 42.042 microseconds for each exception.
This path captures frames, renders values, applies redaction, and inserts the snapshot into the ring.

## Exclude bulldogger frames

`DEBUGGER__.capture_frames(prefix)` removes frames whose paths start with `prefix`.
A test passed the application directory and received zero application frames.

bulldogger passes its own `lib` directory as the prefix.
This value removes bulldogger frames while it retains application frames.

## Keep zero runtime dependencies

The gemspec declares development dependencies and no runtime dependency.
The core uses the Ruby standard library.

The complete frame source uses `debug/frame_info` when the application bundle exposes it.
The `debug` gem is bundled with Ruby 4.0.6, and it is not a default gem.
Under Bundler, the application Gemfile must include `debug`.

When `debug/frame_info` raises `LoadError`, bulldogger uses the degraded frame source.
That source records raising-frame locals and the remaining frame locations.

This design lets applications choose the `debug` dependency.
The installation guide includes `gem "debug", group: :test` for complete frame locals.

## Require an explicit Minitest entry point

Minitest discovers files named `minitest/*_plugin.rb` in each active gem.
A measured plugin file started bulldogger in every Minitest run that activated the gem.
The test suite did not need a `require "bulldogger"` line to trigger this behavior.

This repository's own tests then ran with bulldogger capture active.
The automatic behavior conflicted with the explicit integration boundary.

bulldogger provides `require "bulldogger/minitest"` as the Minitest entry point.
The require line makes capture activation visible in the test setup.

## Keep complete probe counts

The probe records every caller, class, and `nil` occurrence.
Caller sampling could hide a call site and support a false claim that it did not occur.
Count sampling could hide a later `nil` value and support the same false claim.
We rejected both performance proposals because they would create false negative evidence.

The probe serializes only the first 10 values by default.
It continues the complete class, `nil`, and caller counts after that limit.
This design keeps the evidence complete for the questions that probe answers.

A raised method also produces a Ruby `:return` event with a `nil` value.
The Ruby-level rescue counter identifies that raised exit.
The evidence records `raised_exits` and excludes that event from normal return counts.

## Measure the shipped event work

Early estimates measured a different amount of work.
Using those estimates would state a low probe cost and a high record cost.
Measurement of the shipped paths corrected both directions.

The common proportionality harness measured 1353.3 ns per targeted probe call.
It measured 3872.2 ns per traced record call.
The record-specific harness measured 34.18x for value capture and 50.56x with file output.

## Use proportionality as the performance rule

A probe observes M calls to its named methods.
A record observes N calls to all Ruby methods in its traced operation.
The measured probe cost follows M, and the measured record cost follows N.

A fixed cost ratio changes when the workload changes M/N.
The proportionality rule lets a reader apply the measurement to an application call graph.

## Keep JSONL as the record writer

The record path writes versioned JSONL with one event on each line.
`trace_to_sqlite` converts a finished file when the `sqlite3` gem is available.

This converter keeps SQLite behind the file boundary.
It also keeps the core at zero runtime dependencies.

## Account for the coverage blind spot

Ruby `Coverage` does not observe lines that run under a `TracePoint` callback.
The suite calls the callback logic directly to test those lines.

The coverage gate also keeps a line-specific ledger for callback gaps.
The measured ledger has zero entries, and its fixed cap is zero.
The gate fails when a new entry appears.

## Limit dogfooding to the acceptance suite

The acceptance suite runs under bulldogger and keeps its outer capture instance active.
The dogfood demo produced `capture_frames` evidence with a planted local and a redacted secret.

The unit setup resets the module singleton before each test.
That reset also stops an outer dogfood instance.
An instance API would let the subject and the test tool coexist.
That API is planned after version 0.1.

## Add independent instances in version 0.2

Version 0.2 adds `Bulldogger::Instance` and makes the module a facade over a default instance.
Each instance owns its capture subscription, configuration, run, and evidence state.

A module singleton could not serve as both the unit-test subject and the outer observer.
The unit setup reset the singleton for isolation and stopped the outer observer.
The resulting failure evidence used `capture_mode: missed` and contained zero frames.

The Minitest and RSpec integrations accept an assigned instance and use `Bulldogger.default` when no instance is assigned.
With a separate outer instance, the same unit-suite failure used `capture_frames` and contained 20 frames.

Dogfooding now runs the unit and acceptance suites, and a green unit run writes zero evidence files.

## Match one redaction union in version 0.2

The redactor compiles its pattern array with `Regexp.union` during construction.
Each name check performs one regular expression match instead of nine matches.

The results matched for 26 boundary names and 2,000 random names.
The record harness measured value capture at 34.18x and the complete path at 50.56x.

Construction defines the pattern snapshot boundary.
An in-place array change after construction does not affect an existing redactor.
Configuration reassignment already had the same effective boundary.

## Treat TracePoint callback suppression as an observation limit

Ruby suppresses trace events while a `TracePoint` callback runs.
A probe cannot observe a target method that another `TracePoint` callback calls.

Bulldogger serializes failure values inside its `:raise` callback.
A probe aimed at that serialization path reports zero calls for every target.
Those zero counts mean that the calls were never visible to the probe.
They do not show that the methods never ran.

This VM behavior imposes an observation limit on the available evidence.
Timing measurements guided the redaction change because a probe could not observe this path.
The property tests verified that the redaction behavior stayed the same.

## Update the explicit verb measurements in version 0.2

The common proportionality harness measured 1353.3 ns per targeted probe call.
It measured 3872.2 ns per traced record call.
The proportionality law held in both measured directions.

At M/N of 0.25, the publication point measured probe at 9.07x and record at 103.72x.
These values describe the fixture call graph.
The performance rule remains a proportionality based on M and N.

## Replay a failure to reach a value already returned

A measurement traced a failing assertion whose application code had already returned before the assertion raised.
The failure snapshot held 20 frames: the test framework and the test body, and no application code.
More frames do not help this case. The call that produced the wrong value had already left the stack when Ruby raised.

A rerun of the same failing test, under full recording, found the value.
The recorded trace held the call and the return of the method that produced it, several thousand events into the same test run.

bulldogger reruns a failing test automatically, under full recording, once by default.
The `replay` evidence key names the resulting trace.

## Run replay in a child process

Full recording subscribes to every call and return. An early design that ran this continuously, inside the parent process, measured 60x to 106x the baseline.
Replay inside the parent test process would apply that same continuous cost to every green run.
It would also let a re-run test change state that a later test depends on.

bulldogger runs replay as a separate `ruby` process instead. The child inherits the environment and a filtered copy of the parent's `$LOAD_PATH`.
It does not inherit the parent's live objects or its running state.
A crash, a timeout, or a wrong exit status in the child does not change the parent suite's exit code or failure count.

This design keeps the zero-cost-when-green property. Replay adds cost only after a failure, once by default, bounded to the one process that investigates it.

## Keep replay on by default, and state its side effect beside the switch

Replay exists to find a value that a snapshot alone cannot reach, so the default enables it.
Replay also runs the failing test a second time. A test with a side effect performs that effect twice: a file write, an external request, or a sandbox account change.

The side effect applies only after a failure, never on a green run.
The default stays on because the value replay finds outweighs that cost for most suites.
Any application can turn replay off: `BULLDOGGER_REPLAY=0` for one process, or `config.replay_on_failure = false` for the application.
`BULLDOGGER_DISABLE=1` turns off replay along with every other capture.

## Verify a replay trace by its content

An early acceptance check asserted only that the evidence held a `replay` key.
A replay child that could not load the application code still wrote a trace.
The trace held only interpreter and framework boot events.
It carried no line of application code.
The evidence file still carried the `replay` key.
That version passed the existing suite.

The acceptance suite now reads the named trace and asserts that a chosen application method's own call and return appear in it, by name.
A trace that holds no application events fails that assertion, even when the `replay` key is present.
