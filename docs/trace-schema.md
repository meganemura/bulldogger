# Trace schema

`Bulldogger.record` writes a JSONL file named `trace-NNN.jsonl`.
The first line is a header, and each later line is one event.

## Header

This header came from a generated trace:

```json
{"schema_version":1,"kind":"record","started_at":"2026-08-28T12:15:18Z","events":["call","return","raise"],"limits":{"max_value_length":200},"skill":"/home/you/.local/share/gem/ruby/4.0.0/gems/bulldogger-0.2.0/skills/bulldogger/SKILL.md"}
```

| Field | Type | Meaning |
|---|---|---|
| `schema_version` | Integer | Schema version. Versions 0.1.0 and 0.2.0 write `1`. |
| `kind` | String | The value is `record`. |
| `started_at` | String | UTC start time. |
| `events` | Array | Event kinds written after the header. |
| `limits` | Object | Value limits used for this trace. |
| `skill` | String | Absolute path to `SKILL.md` when the file is available. |

## Events

Each event has `event`, `seq`, `depth`, `path`, `line`, and `method`.
The sequence starts at 1 and follows write order.
The depth is the Ruby call depth observed by this recording session.

A call event has an `args` object with named arguments:

```json
{"event":"call","seq":2,"depth":2,"path":"-e","line":1,"method":"ProseTrace#inner","args":{"value":{"value":"3"}}}
```

A normal return has a rendered `return` entry:

```json
{"event":"return","seq":3,"depth":2,"path":"-e","line":1,"method":"ProseTrace#inner","return":{"value":"6"}}
```

A raise event has an exception class and message:

```json
{"event":"raise","seq":7,"depth":2,"path":"-e","line":1,"method":"ProseTrace#inner","exception":{"class":"ArgumentError","message":"negative"}}
```

Ruby emits a `:return` event when an exception leaves a method.
That event has `raised: true` and has no `return` field:

```json
{"event":"return","seq":8,"depth":2,"path":"-e","line":1,"method":"ProseTrace#inner","raised":true}
```

The discriminator uses Ruby-level `:rescue` events.
It distinguishes raised exits from normal `nil` returns.
The trace uses this event for internal state and does not write it.

## Event selection

The default event set contains `:call`, `:return`, and `:raise`.
The header records this set for each file.

`:line` produces an event for each executed source line.
`:b_call` produces an event for each block invocation.
Their event counts follow executed lines and block invocations.
The record verb keeps method boundaries and raises within a usable explicit run.

## Values and secrets

Argument and return entries use the bounded formatter from failure evidence.
Named arguments also use the configured redaction patterns.
A redacted argument has no `value` field.

Exception messages use five times `max_value_length`.
A long message has `message_truncated` and `message_original_length` fields.

## jq queries

These queries ran against the generated trace used for the examples.

Read the header:

```sh
head -n 1 trace.jsonl | jq '{schema_version, kind, events, limits}'
```

List the event sequence:

```sh
jq -c 'select(.event) | {seq, depth, event, method}' trace.jsonl
```

List raised exits:

```sh
jq -c 'select(.event == "return" and .raised == true)
  | {seq, depth, method, raised}' trace.jsonl
```

List raised exceptions:

```sh
jq -c 'select(.event == "raise")
  | {seq, method, class: .exception.class, message: .exception.message}' trace.jsonl
```

Count calls by method:

```sh
jq -s 'map(select(.event == "call"))
  | group_by(.method)
  | map({method: .[0].method, calls: length})' trace.jsonl
```

## SQLite adapter

`Bulldogger.trace_to_sqlite(jsonl_path, db_path)` converts a finished trace.
It returns `nil` with a warning when the `sqlite3` gem is unavailable.
The converter stores each event and its complete JSON payload.
