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

bulldogger reruns an assertion-shaped failure automatically, under full recording, once by default.
The `replay` evidence key names the resulting trace.

## Skip replay when an application frame remains

A propagating exception leaves the raising application method on the stack. The failure snapshot holds that method and its locals. A second run adds a cost and a side effect risk without adding evidence.

The default rule counts application frames outside the test file. It also excludes Ruby library paths and gem paths. No application frame causes replay. At least one application frame causes a skip.

The red Minitest fixture measured both shapes. Its assertion failure had no application frame outside the test file. Its propagating exception retained `Order.total` with its locals.

The evidence records `replay_skipped_reason: "application_frame_available"` for a skip. This key distinguishes the skip from a replay attempt that produced no trace.

## Run replay in a child process

Full recording subscribes to every call and return. An early design that ran this continuously, inside the parent process, measured 60x to 106x the baseline.
Replay inside the parent test process would apply that same continuous cost to every green run.
It would also let a re-run test change state that a later test depends on.

bulldogger runs replay as a separate `ruby` process instead. The child inherits the environment and a filtered copy of the parent's `$LOAD_PATH`.
It does not inherit the parent's live objects or its running state.
A crash, a timeout, or a wrong exit status in the child does not change the parent suite's exit code or failure count.

This design keeps the zero-cost-when-green property. The default rule adds replay cost only when the failure frames cannot answer, once per run by default.

## Keep replay on by default, and state its side effect beside the switch

Replay exists to find a value that a snapshot alone cannot reach, so the default enables the frame-based rule.
Replay also runs the failing test a second time. A test with a side effect performs that effect twice: a file write, an external request, or a sandbox account change.

The default rule reduces the failures that receive a second run. The side effect remains for each replayed failure and never applies on a green run.
The default stays on because the value replay finds outweighs that cost for most suites.
An application can select the old behavior with `BULLDOGGER_REPLAY=always` or `config.replay_on_failure = :always`.
It can turn replay off with `BULLDOGGER_REPLAY=0` or `config.replay_on_failure = false`.
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

## Redirect version 0.2 to re-execution (2026-08-31)

The entries below this one define the re-execution design.
They replace the earlier version 0.2 plan where the two conflict.
Version 0.2.0 shipped automatic replay; this design replaces it and retires
the record verb, so it is a breaking change and ships as 0.3.0.

Four concepts come from published work on agent debugging interfaces (arXiv:2604.24212):
run the failing test again and collect statement-level detail for one selected frame during that run,
the frame lifetime trace with entry arguments and per-statement state changes,
the fold that keeps the first and last loop iterations,
and statement injection for what-if analysis.
That work measured 0.68 s to 0.87 s for a traced failing-test run on its Python benchmark.

The identity, addressing, and file decisions are original to bulldogger:
the application-boundary comparison rule, the normalized frame identity,
the test-scoped raise ordinal, the stateless verbs over evidence files,
and the code-state marker.
Each has its own dated entry below.

Every measurement below this line used ruby 4.0.6 and the rubygems.org
test suite (4,925 tests, seed 12345, one worker), measured on 2026-08-31.

## Retire the record verb and automatic replay (2026-08-31)

Version 0.2 removes the `record` verb.
Whole-run tracing measured 881x to 2869x with debug.gem's recorder, and 34x to 51x with the shipped record path.
The `frames` verb builds a call index from one re-execution.
A diff of two `frames` runs, plus a `probe` run, answers the questions record answered, at re-execution cost.

Automatic replay also retires.
The design principle keeps heavy work behind an explicit verb.
The failure message from `snap` prints the complete rerun command, so the agent chooses each re-execution.

## Compare executions inside the application boundary (2026-08-31)

Two isolated runs of the same test, same seed, matched on the full event stream in 39% of a 200-test stratified sample.
The mismatches sat in framework and gem frames: ActionView compiles each template into a method whose name embeds the process-random `String#hash`, and ActiveRecord fills type-metadata registries in varying first-seen order.
Most mismatched pairs differed by fewer than 100 events out of hundreds of thousands.

The same 200 pairs, compared only on frames whose paths sit under the application's `app/` and `lib/` directories, matched 200 of 200.
Every pair also matched on the application event count.
The sample's application event counts ranged from 1 to 3,561 with a median of 214.

bulldogger therefore compares executions on application frames, with normalized method names.
The normalization folds the numeric segments of compiled-template method names into one fixed token.
A negative template hash turns its minus sign into an extra underscore, and the normalization accepts both spellings.
The frames index still lists framework and gem frames, because navigation needs them.
The comparison rule and the stability guarantee cover application frames.

CRuby seeds its string hash from operating-system entropy at startup.
Ruby 4.0.6 reads no environment variable for this seed, so a per-process name difference has no official off switch, and normalization handles it instead.

## Verify determinism with two isolated runs (2026-08-31)

The preflight runs the target test twice in isolation and compares the two application-frame sequences.
This pair is the condition the verbs operate under, because every verb re-executes one test in a fresh process.

A suite-to-suite comparison answers a different question.
Two full-suite runs with one seed matched on raw full streams for 70% to 72% of 4,925 tests, across two independently built harnesses.
Among 20 sampled tests that matched suite-to-suite, the isolated rerun reproduced the suite's stream for none of them, and the isolated event counts ran 16% to 5,318% higher.
A fresh process resolves autoloads and builds caches inside the recorded window, and the suite process pays those costs before most tests start.
The preflight therefore measures the isolated pair, and treats the suite trace as a separate execution.

## Name a frame by its method and its in-test call index (2026-08-31)

A frame identifier must survive a second process: the `frames` run builds the index, and a later `flt` or `exec` run must reach the same frame.
The identifier is the normalized method identity plus the call count of that method inside the test window, written `path:method#k`.

A process-global frame number fails this requirement, because whole-process streams matched in 39% of isolated pairs.
Counting one method inside the test window rides on the 200-of-200 application-frame stability of isolated pairs.
The published interface also names frames by function and call index; bulldogger narrows the counting window from the process to the test.

Reaching call k costs one targeted TracePoint on `:call` and `:return`.
The pass-through measured about 105 ns per non-target call, so the gate stays armed for the whole run.

## Trace the selected frame with one targeted TracePoint (2026-08-31)

`TracePoint#enable(target:)` on the method's instruction sequence fires `:line` events inside nested blocks and rescue clauses of that method.
Ruby's own test suite pins this behavior in `test_tracepoint_enable_target`.
One enable call therefore covers the whole frame.

Reading every local on every line, with a capped shallow inspect and a change check, measured near 0.1 µs per local per line event, over a fixed floor near 0.5 µs per event.
A frame with 20 locals and 10,000 line events costs about 27 ms.
The cost follows line events times locals.

## Record scope exit in the frame lifetime trace (2026-08-31)

The trace prints entry arguments and locals in full, then only changed variables per line.
A reconstruction test replayed the change records against full per-line snapshots on four application frames.
Three frames reconstructed exactly.
The fourth failed after each inner block exit: the block's locals left scope, the change vocabulary had no record for that, and the reconstruction kept stale values.

The trace format therefore includes a scope-exit record.
With that record, the change stream carries enough information to rebuild every line's visible locals.

## Fold loops to their first and last iterations (2026-08-31)

The trace keeps the first and the last iteration of a loop and replaces the middle with one skipped marker that carries the count.
The fold works online with one iteration of delay, because the tracer learns that an iteration was the last one only when the loop exits.
Buffer memory follows nesting depth times iteration size, and stayed flat from 10 to 100,000 iterations in measurement.

On a collection-processing frame, the folded differential output measured 5,155 bytes against 50,994 bytes of full per-line output.
The skipped iterations held distinct values, so a defect inside a middle iteration stays outside the trace.
The marker declares that loss, and the fold trades it for the size reduction.

## Gate statement injection behind a launch token (2026-08-31)

`exec` evaluates an agent-supplied statement inside a chosen frame, so it runs only where the launcher intends.
Four inferred test-environment signals were measured: environment variable names, loaded framework constants, the program name, and caller paths.
Each signal produced a false positive and a false negative in measurement.

The gate therefore reads one explicit token, `BULLDOGGER_EXEC=1`, that the re-execution launcher sets for the child.
Without the token, `exec` refuses.
`Binding#local_variable_set` writes through to method and block locals during a `:line` event, so injection needs no other machinery.
The statement address is the frame identifier, the line, and the visit count of that line.

## Restrict flt and exec targets to application frames (2026-08-31)

The call index lists framework and gem frames, and their call counts vary between isolated runs.
A target whose call count varies can silently select a different invocation on the next run.
`flt` and `exec` therefore accept application frames and refuse the rest, and the refusal message names the alternatives: the call-tree view, the gem source, and `probe`.
`probe` records arguments and returns for a named method without a call index, so it stays safe on gem methods.

## Inject the collector through RUBYOPT (2026-08-31)

The re-execution child loads the collector through `RUBYOPT="-r<absolute path>"`.
Bundler prepends its own `-rbundler/setup` and keeps the absolute-path entry, and `Bundler.with_unbundled_env` keeps it too.
A collector loaded from the test helper misses raises that happen while the application boots, and the boot window measured real rescued raises.

`RUBYOPT` also reaches grandchildren: rake-spawned processes, parallel test workers, and processes the test itself starts.
The collector records its process id, and the evidence separates child records from the target's records.
A helper-line entry with an environment gate remains the fallback for a suite that rejects launcher-set options.

## Stamp evidence with a code-state marker (2026-08-31)

Every artifact from a re-execution carries the git commit and a digest of the dirty state.
`git rev-parse HEAD` measured about 8 ms and `git status --porcelain` about 10 ms, so the marker is computed once per run and cached.
`flt` and `exec` compare the marker of the index they were aimed with against their own run, and refuse or warn on a mismatch.
An index from edited code would otherwise send the agent to line numbers that no longer exist.

## Bridge the snapshot to the index with a test-scoped raise ordinal (2026-08-31)

`snap` writes during the suite run, and `frames` writes during an isolated rerun.
The two streams disagree on whole sequences, so the bridge uses a coordinate that both runs compute the same way: the count of `:raise` events since the test started, plus the raise's path, line, and exception class.
A process-wide raise count failed this role in measurement, because earlier tests in the suite advance it.
The test-scoped count survived the move from a suite run to an isolated run in measurement, with the caveat that a fresh process may rescue additional raises during lazy loading; the implementation verifies this on real suites before it relies on the ordinal.

A dogfooding run on rubygems.org performed that verification and sharpened the decision (2026-08-31, second entry).
The suite snapshot recorded its failure at raise ordinal 1, and two isolated frames runs both placed the same failure at ordinal 14, behind thirteen rescued lazy-loading raises that only a fresh process performs.
The two isolated runs agreed with each other down to the exception-class tally.
The bridge therefore treats the frames run's ordinal as the authoritative address, and the snapshot's role stays at the entry point: the test name and the rerun command.
The snapshot's (path, line, exception class) triple serves as a cross-check.
When the isolated reproduction fails at a different location or class than the snapshot recorded, the tool reports that mismatch as a named diagnosis — the suite failure reproduced with a different face, which signals test-order dependence or state contamination — in the same style preflight uses to name a divergence.

## Print evidence lines through the reporter's own io (2026-08-31)

A dogfooding run against a real Rails application's test suite, under Minitest 6, showed the evidence file written correctly but its failure-message annotation never reaching output.
Minitest 6 dropped the runtime plugin scan that Minitest 5 ran inside `Minitest.run`; Rails now loads its own plugin at require time instead.
That flips registration order ahead of bulldogger's: Rails' own reporter prints each failure inline before bulldogger's reporter tags the exception's `#message`, and Rails' summary reporter skips the deferred printout that would otherwise show the tag.
Minitest 5 ran the plugin scan late enough that bulldogger's plugin registered first, so the tag landed before Rails' inline print and the gap stayed hidden.
The Minitest reporter now prints the evidence line straight to its own io during `#record`, independent of any other reporter's position and of the exception's frozen state.
The guarantee attaches to what the run writes on failure, and no longer to the framework's message object.

## Name every block frame with a fid every verb can act on (2026-08-31)

`TracePoint#method_id` is nil for a block that sits outside any def (a spec's `it do...end`, a class-body block), so the frames collector built a fid with an empty method segment for it.
A block nested inside a def keeps its enclosing method's name instead, so its fid reads as an ordinary second call and is not distinguishable by text alone.
Neither shape is a valid `flt`/`exec` target: both verbs gate on `:call`/`:return` only, because targeting needs a `Method` object that a block does not have, so either fid let the child process run to completion with no trace.
The collector now names a nameless block "block", and `flt`/`exec` read the index's own event type for the target fid, refusing a block frame and naming the nearest ancestor frame that is an application call.
