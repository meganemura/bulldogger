# Changelog

## 0.2.0

### An assertion failure now reaches the value that caused it

`0.1.0` could not do that for the most ordinary failure there is. When an
assertion fails, the method that produced the wrong value has already
returned, so the snapshot held the test framework and the test body and no
application code. Measured against two real gems, it found nothing.

- **Four re-execution verbs join `probe`.** `frames` runs a test in a fresh
  process and indexes every call by a stable identifier, `fid`
  (`path:method#k`, where `k` counts calls to that method inside the test
  window). `preflight` runs a test twice in isolation and compares the two
  application-frame sequences, so an agent can trust a `fid` from one run to
  address the same call in the next. `flt` traces one selected frame: its
  entry arguments and locals, each line's changed locals, and its return.
  `exec` evaluates one statement at one addressed line visit inside a
  selected frame, gated behind the `BULLDOGGER_EXEC=1` launch token the
  launcher sets for the child process.
- **`record` and automatic replay retire.** Whole-run tracing measured 881x
  to 2869x with debug.gem's recorder, and 34x to 51x with the shipped record
  path; `frames` plus `flt` answer the same questions at re-execution cost,
  paid only when invoked. `flt` and `exec` both refuse a target outside the
  project's own source, naming the frames index, the gem source, and `probe`
  as the alternatives.
- **The failure output's rerun line is the whole handoff.** `bulldogger
  rerun:` prints the complete command for the failing test and seed; an
  agent runs it under `frames` to reach a value whose producing method had
  already returned. A green run still costs nothing extra, and re-execution
  runs only when an agent invokes it.

### Running bulldogger over its own suite

- **`Bulldogger::Instance`** separates the observing tool from the subject
  under test. A single module singleton could not be both, because a suite's
  own setup resets bulldogger for test isolation and destroyed any outer
  observer. The module now delegates to a default instance, and
  `Bulldogger::Minitest.instance=` and `Bulldogger::RSpec.instance=` accept
  another one.
- `rake dogfood` covers the unit suite as well as acceptance.

### Reaching the skill

- **`exe/bulldogger`** launches the re-execution verbs and answers two more
  questions: `skill path` prints the location of the skill shipped with the
  installed gem, and `version` prints the version.
- Evidence and probe evidence carry a `skill` key holding that path. The key
  is omitted when the file is absent, because a path that does not resolve
  costs a reader more than a missing one.
- The skill teaches what the files cannot: that an absent local means the run
  could not see it, that a probe reporting zero calls was blind rather than
  idle, and how to walk a trace from a symptom down to the value's origin.

### Cost

- Redaction matches one union pattern instead of nine separate ones, checked
  against 26 boundary names and 2,000 random names. Every capture path
  shares the same redactor: failure snapshots, `probe`, `flt`, and `exec`.
- A failure snapshot still costs 44.126 microseconds for each raise-and-rescue
  cycle, and a green test that raises nothing still costs nothing measurable.
  `frames`, `preflight`, `flt`, and `exec` start a new process only when an
  agent runs them; `probe` runs only around a block it selects.

### Documentation

- `README.ja.md` translates the README. `README.md` stays the source of the
  claims.
- `docs/design-decisions.md` records the observation limits found while
  building this: `Coverage` cannot see lines under a `TracePoint` callback,
  and neither can a probe, which is why bulldogger cannot probe its own
  serialization path.

## 0.1.0

First release. A failing Ruby test writes a JSON snapshot of its own failure
and names the file in its output, with `probe` and `record` as explicit verbs
for targeted and full observation.
