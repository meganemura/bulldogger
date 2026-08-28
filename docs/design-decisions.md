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
