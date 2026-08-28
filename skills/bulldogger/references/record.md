# Read a full record

Use a record when the relevant method is unknown or the full call sequence matters.

```ruby
path = Bulldogger.record do
  run_related_test
end
```

The JSONL first line is a header.
It gives the schema version, event set, start time, and limits.
Each later line is one call, return, or raise event.

```sh
head -n 1 "$path" | jq '{schema_version, kind, events, limits}'
jq -c 'select(.event) | {seq, depth, event, method}' "$path"
jq -c 'select(.event == "raise") | {method, exception}' "$path"
```

A return with `raised: true` represents an exception exit.
It has no `return` field.
The trace does not contain `:line`, `:b_call`, or `:rescue` lines.

Arguments and return values use redaction and length limits.
Read `redacted`, `truncated`, and a trailing `…` before you infer that a value did not occur.

See [`docs/trace-schema.md`](../../../docs/trace-schema.md) for all event fields and tested queries.
