# Use a targeted probe

Use a probe when one method defines the behavior you need to inspect.

```ruby
path = Bulldogger.probe("Billing::Invoice#amount") do
  run_related_test
end
```

Read `methods` by target name.
Each target has call counts, parameters, argument shapes, return shapes, raised exits, and callers.

`raised_exits` counts calls that left through an exception.
Those calls do not increase the return `nil_count`.
The distinction prevents a raised exit from appearing as a normal `nil` return.

The class, `nil`, and caller counts include every observed call.
The `samples` arrays contain the first `limits.max_samples` values.
`samples_omitted` counts later values that were not serialized.

Run the same probe before and after a change:

```ruby
before_path = Bulldogger.probe("Billing::Invoice#amount") { run_related_test }
# Apply the change.
after_path = Bulldogger.probe("Billing::Invoice#amount") { run_related_test }
comparison = Bulldogger.probe_compare(before_path, after_path)
```

`comparison["identical"] == true` shows behavior preservation for the compared shape.
Read each item in `differences` when the value is false.

Redacted samples have no value.
Truncated samples include their original length.
See [`docs/evidence-schema.md`](../../../docs/evidence-schema.md) for all probe fields.
