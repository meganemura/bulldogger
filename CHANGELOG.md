# Changelog

## 0.2.0

### A failing test now leads to the value that caused it

`0.1.0` could not do that for the most ordinary failure there is. When an
assertion fails, the method that produced the wrong value has already
returned, so the snapshot held the test framework and the test body and no
application code. Measured against two real gems, it found nothing.

- **replay**: bulldogger re-runs the one failing test in a child process
  under full recording, and the trace holds the producing call with its
  arguments and its return. The child keeps the parent suite's result
  untouched, and a green run replays nothing. Evidence gains `replay` and
  `replay_reproduced`.
- **Replay runs only when it can add something.** A propagating exception
  leaves the raising method on the stack with its locals, so the snapshot
  already answers and no second run happens. Evidence records that choice
  in `replay_skipped_reason` rather than staying silent. `replay_on_failure`
  accepts `true`, `:always`, and `false`; `BULLDOGGER_REPLAY` accepts `0`,
  `1`, and `always`.
- **The failure output says which file to read and why.** The line worth
  opening carries a short clause, so the first step needs nothing else.
  Four states each say what they hold, including a replay whose child
  passed, which shows a passing run rather than the failure.

### Running bulldogger over its own suite

- **`Bulldogger::Instance`** separates the observing tool from the subject
  under test. A single module singleton could not be both, because a suite's
  own setup resets bulldogger for test isolation and destroyed any outer
  observer. The module now delegates to a default instance, and
  `Bulldogger::Minitest.instance=` and `Bulldogger::RSpec.instance=` accept
  another one.
- `rake dogfood` covers the unit suite as well as acceptance.

### Reaching the skill

- **`exe/bulldogger`** answers two questions: `skill path` prints the
  location of the skill shipped with the installed gem, and `version` prints
  the version.
- Evidence, probe evidence, and record headers carry a `skill` key holding
  that path. The key is omitted when the file is absent, because a path that
  does not resolve costs a reader more than a missing one.
- The skill teaches what the files cannot: that an absent local means the run
  could not see it, that a probe reporting zero calls was blind rather than
  idle, and how to walk a trace from a symptom down to the value's origin.

### Cost

- Redaction matches one union pattern instead of nine separate ones, which
  took value capture from about 41x to between 34x and 37x. Redaction was
  about half the cost of serializing one local, and almost no name matches
  any pattern.

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
