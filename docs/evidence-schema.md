# Evidence schema

bulldogger writes one JSON evidence file for each failed test.
The run directory also contains `index.json`, which lists the failure files.

## Top-level fields

| Field | Type | Presence | Meaning |
|---|---|---|---|
| `schema_version` | Integer | always | Schema version. Version 0.1.0 writes `1`. |
| `tool` | Object | always | Writer name and version. |
| `captured_at` | String | always | UTC write time in `YYYY-MM-DDTHH:MM:SSZ` format. |
| `capture_mode` | String | always | `capture_frames`, `degraded`, or `missed`. |
| `test` | Object | always | Framework test data. |
| `exception` | Object | always | Exception data. |
| `frames` | Array | always | Frames from the raise site outward. |
| `frames_omitted` | Integer | when positive | Frames removed by `max_frames`. |
| `frames_unavailable_reason` | String | in missed mode | Reason for an empty frame list. |
| `limits` | Object | always | Limits used for this capture. |

## Test fields

The framework integration supplies all four fields.
Each value can be `null` when the framework has no value.

| Field | Type |
|---|---|
| `framework` | String or null |
| `id` | String or null |
| `file` | String or null |
| `line` | Integer or null |

## Exception fields

| Field | Type | Presence | Meaning |
|---|---|---|---|
| `class` | String | always | Exception class name. |
| `message` | String | always | Message with a limit of five times `max_value_length`. |
| `message_truncated` | Boolean | when true | The message exceeded its limit. |
| `message_original_length` | Integer | with `message_truncated` | Length before truncation. |
| `backtrace` | Array of String | always | First `max_frames` backtrace lines. |

## Frame fields

| Field | Type | Presence | Meaning |
|---|---|---|---|
| `index` | Integer | always | Position from the raise site. |
| `path` | String or null | always | Ruby source path. |
| `line` | Integer or null | always | Ruby source line. |
| `label` | String or null | always | Method or block label. |
| `self` | String | when captured | Rendered frame receiver. |
| `locals` | Object | when captured | Map from local names to entries. |
| `locals_omitted` | Integer | when positive | Locals removed by `max_locals`. |
| `locals_unavailable` | Boolean | degraded frames after frame 0 | The capture source could not read these locals. |

Frame 0 is the innermost frame.
An assertion library can raise before control returns to the test method.
Search frame labels and paths to identify the frame that owns the needed locals.

## Local entries

A captured local has a String value:

```json
{"qty": {"value": "3"}}
```

A value longer than `max_value_length` also has truncation fields:

```json
{"value": "a long rendered value…", "truncated": true, "original_length": 814}
```

A local name that matches a redaction pattern has this shape:

```json
{"api_token": {"redacted": true, "reason": "name"}}
```

The redacted entry has no `value` field.
Version 0.1.0 emits only `"name"` as the `reason` value.

Hash-key redaction appears inside the parent value String:

```json
{"settings": {"value": "{\"token\" => \"[REDACTED]\", \"level\" => \"debug\"}"}}
```

## Value rendering

bulldogger stores each rendered value as a JSON String.
It uses Ruby `inspect` for scalar values and Strings.

Arrays and Hashes expand one level.
A nested Array becomes `[…]`, and a nested Hash becomes `{…}`.
The formatter keeps 10 elements and adds `…` when more elements exist.

For other objects, the formatter calls `inspect` and catches any exception.
An object with a failing `inspect` produces `#<ClassName (inspect raised ExceptionClass)>`.

## Capture modes

### `capture_frames`

The `debug` frame API supplies locals and `self` for each retained frame.
This projection came from a generated Minitest failure file:

```json
{
  "schema_version": 1,
  "tool": {"name": "bulldogger", "version": "0.1.0"},
  "capture_mode": "capture_frames",
  "test": {
    "framework": "minitest",
    "id": "RedTest#test_deep_raise",
    "file": "test/fixtures/minitest_red/red_test.rb",
    "line": 19
  },
  "exception": {
    "class": "ArgumentError",
    "message": "expected 3 to equal the sum of [1, 2, 3]"
  },
  "frames": [
    {
      "index": 0,
      "line": 9,
      "label": "Order.total",
      "self": "Order",
      "locals": {
        "qty": {"value": "3"},
        "rows": {"value": "[1, 2, 3]"},
        "api_token": {"redacted": true, "reason": "name"}
      }
    }
  ],
  "limits": {"max_frames": 20, "max_locals": 50, "max_value_length": 200}
}
```

### `degraded`

Frame 0 uses the raising `TracePoint` binding.
Later frames contain positions and `locals_unavailable: true`.
This projection came from the same fixture with `BULLDOGGER_FRAME_SOURCE=degraded`:

```json
{
  "schema_version": 1,
  "capture_mode": "degraded",
  "frames": [
    {
      "index": 0,
      "line": 9,
      "label": "Order.total",
      "locals": {
        "qty": {"value": "3"},
        "rows": {"value": "[1, 2, 3]"},
        "api_token": {"redacted": true, "reason": "name"}
      },
      "self": "Order"
    },
    {
      "index": 1,
      "path": "test/fixtures/minitest_red/red_test.rb",
      "line": 20,
      "label": "RedTest#test_deep_raise",
      "locals_unavailable": true
    }
  ]
}
```

A later frame can have Ruby locals even when the evidence has no `locals` field.
Add `gem "debug", group: :test` and repeat the failed test to capture those locals.

### `missed`

Missed mode has an empty frame list.
The following complete file came from recording an exception before capture started:

```json
{
  "schema_version": 1,
  "tool": {"name": "bulldogger", "version": "0.1.0"},
  "captured_at": "2026-08-28T07:58:25Z",
  "capture_mode": "missed",
  "test": {
    "framework": "minitest",
    "id": "MissedTest#test_example",
    "file": "test/missed_test.rb",
    "line": 7
  },
  "exception": {
    "class": "ArgumentError",
    "message": "missed example",
    "backtrace": ["-e:1:in '<main>'"]
  },
  "frames": [],
  "frames_unavailable_reason": "capture_disabled",
  "limits": {"max_frames": 20, "max_locals": 50, "max_value_length": 200}
}
```

The reason has one of these values:

| Value | Meaning |
|---|---|
| `capture_disabled` | Capture was not running when Ruby raised the exception. |
| `not_captured` | Capture was running, but the pending ring had no matching exception. |
| `evicted` | Later exceptions removed the matching snapshot from the bounded ring. |

Missed evidence retains the test data, exception message, and exception backtrace.

## Limits and omission markers

The default limits are 20 frames, 50 locals per frame, and 200 characters per value.
The pending ring keeps 32 exception snapshots.

The file records positive omission counts:

- `frames_omitted` counts frames after `max_frames`.
- `locals_omitted` counts locals after `max_locals`.
- `original_length` records the rendered length before value truncation.
- `message_original_length` records the message length before message truncation.

An Array or Hash uses a trailing `…` to mark elements after the first 10.

## Run index

`index.json` has this shape:

```json
{
  "schema_version": 1,
  "run_dir": "/absolute/path/tmp/bulldogger/run-20260828-165825-28806",
  "failures": [
    {
      "path": "001-RedTest-test_assertion_failure.json",
      "test": {
        "framework": "minitest",
        "id": "RedTest#test_assertion_failure",
        "file": "test/fixtures/minitest_red/red_test.rb",
        "line": 12
      },
      "exception": {
        "class": "Minitest::Assertion",
        "message": "seeded api_token: 9 chars.\nExpected: 4\n  Actual: 9"
      }
    }
  ]
}
```

Each failure path is relative to the run directory.
The `latest` symlink points to the last finished run when the filesystem supports symlinks.

## jq queries

These queries ran against generated evidence files.

List the capture mode and test identifier:

```sh
jq '{capture_mode, test_id: .test.id}' evidence.json
```

List frame positions:

```sh
jq '[.frames[] | {index, label, path}]' evidence.json
```

Find a local in any captured frame:

```sh
jq '[.frames[] | select(.locals.qty) | {index, label, qty: .locals.qty}]' evidence.json
```

List truncated locals:

```sh
jq '[.frames[] | .index as $frame | (.locals // {}) | to_entries[]
  | select(.value.truncated == true)
  | {frame: $frame, name: .key, original_length: .value.original_length}]' evidence.json
```

List redacted locals:

```sh
jq '[.frames[] | .index as $frame | (.locals // {}) | to_entries[]
  | select(.value.redacted == true)
  | {frame: $frame, name: .key, reason: .value.reason}]' evidence.json
```

List failed test identifiers from the run index:

```sh
jq '[.failures[].test.id]' tmp/bulldogger/latest/index.json
```
