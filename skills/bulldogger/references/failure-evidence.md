# Read failure evidence

## Interpret the capture mode

- `capture_frames`: Each retained frame has `locals` and `self`.
- `degraded`: Frame 0 has `locals` and `self`.
  Later frames have `locals_unavailable: true` and location data.
- `missed`: `frames` is empty, and `frames_unavailable_reason` explains the capture failure.

In degraded evidence, a missing `locals` field does not describe the Ruby frame.
It means the capture source could not read that frame's locals.

Add `gem "debug", group: :test` to the application Gemfile for complete frame locals.
Then install the bundle and run the failed test again.

Missed evidence still contains the test, exception message, and exception backtrace.
Use `frames_unavailable_reason` to distinguish disabled capture, an uncaptured exception, and ring eviction.
The values are `capture_disabled`, `not_captured`, and `evicted`.

## Find the useful frame

Frame 0 is the raise site.
For assertion failures, framework assertion code can occupy the first frames.
A generated Minitest failure placed the test method at index 2.

An exception can propagate while the raising application method remains on the stack. Its frame and locals answer the question. The evidence records `replay_skipped_reason: "application_frame_available"` and has no `replay` key.

An assertion raises after the code under test already returned, so the produced value has no application frame. When the frames stop at the test framework and the test body, read [replay traces](replay.md) for the value's origin.

A missing `replay` key with the recorded skip reason describes a deliberate skip. Use the application frame instead of looking for a trace.

List the frame labels and paths:

```sh
jq '[.frames[] | {index, label, path}]' /absolute/path/to/evidence.json
```

Choose the application or test frame that owns the values you need.
Then read its locals:

```sh
jq '.frames[2].locals' /absolute/path/to/evidence.json
```

Find one local across all captured frames:

```sh
jq '[.frames[] | select(.locals.qty) | {index, label, qty: .locals.qty}]' /absolute/path/to/evidence.json
```

## Read missing values correctly

A local with `redacted: true` was hidden because its name matched a redaction pattern.
It has no `value` field.

A value with `truncated: true` was cut to the configured character limit.
Use `original_length` to see the length before truncation.

`locals_omitted` and `frames_omitted` give the numbers removed by capture limits.
An Array or Hash ending in `…` had more than 10 elements.

See [`docs/evidence-schema.md`](../../../docs/evidence-schema.md) for each field and more queries.
