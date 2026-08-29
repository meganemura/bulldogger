# AGENTS.md

Context for agents that work in this repository.

## What this is

bulldogger makes Ruby execution available to coding agents as evidence.
A failing test writes a structured snapshot of its own failure; an agent
reads the snapshot instead of guessing runtime values from source.

The name: a bulldogger is the rodeo rider who catches a running steer
with bare hands.

## Visibility

This repository is written to be published. English everywhere:
README, docs, comments, commit messages.

`README.ja.md` is the one exception, and it is a translation rather than a
second source. `README.md` holds the claims, and every measured number
belongs there first. A change to `README.md` is finished when the
translation carries it too, because a translation that drifts states
something the project does not, and a reader who trusts it has no way to
tell.

## Design principles (settled; change only with the owner)

- The default capture is the failure snapshot. It costs nothing while
  tests are green, and microseconds per exception when they are not.
- Always-on full tracing is out. It was measured at 60x to 106x and
  the design treats that as a closed door.
- Heavy work is an explicit verb (probe, record), never an ambient
  default.
- The product is files: a documented snapshot schema an agent can read
  and query. CLI and any servers are thin adapters over the files.
- The failure message names the evidence path and how to query it.
  An agent learns the tool at the moment of need, from the failure
  output itself.
- Values may hold secrets. Capture is bounded (shallow inspect, length
  caps) and redaction is a first-class concern, not an afterthought.

## Mechanism facts this build stands on (measured 2026-08-28, ruby 4.0.6, debug 1.11.1)

- `TracePoint(:raise)` plus `DEBUGGER__.capture_frames` yields every
  frame's locals at ~0.007ms per exception. debug.gem's own postmortem
  uses this exact pair in production; the C signature is unchanged from
  v1.8.0 through master.
- `capture_frames(skip_path_prefix)`: passing your own `__dir__` hides
  your own frames — pass the path of the code to exclude (this
  library's), never the app's.
- `TracePoint#enable(target:)` cannot target `:raise`; failure capture
  subscribes globally.
- Degrade path when `capture_frames` is missing: `tp.binding` gives the
  raising frame's locals, `caller_locations` gives every frame's
  location without locals.
- `require "debug"` at rest costs nothing measurable (1.01x). Require
  `debug/frame_info` instead: it defines `DEBUGGER__.capture_frames`
  and stops there, while `debug` itself calls `DEBUGGER__.start` and
  opens a debugger session.
- `debug` is a bundled gem, not a default gem
  (`Gem::Specification.find_by_name("debug").default_gem?` is false on
  ruby 4.0.6). Under Bundler it loads only when the app's own Gemfile
  asks for it; otherwise `require "debug/frame_info"` raises LoadError.
  The degrade path is therefore the default under Bundler, not a rare
  case, and it carries the same weight in tests as the full path.

## Conventions

- Tests prove behavior by running it. The zero-cost-when-green claim
  and the capture-on-failure claim are both demonstrated by executing
  real suites, not asserted.
- No publishing (gem push, repo visibility) without the owner's
  explicit instruction.
- Dependency additions need the owner's approval. The core carries zero
  runtime dependencies: it runs on stdlib alone, and uses `debug` only
  when the host app already has it.
