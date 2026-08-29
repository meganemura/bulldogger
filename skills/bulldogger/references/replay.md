# Read a replay trace

First choose between the two failure shapes:

- A propagated exception keeps the raising application method and its locals in the snapshot. The evidence records `replay_skipped_reason: "application_frame_available"` and has no `replay` key. The frames already answer the question.
- An assertion raises after the producing method returns. Its snapshot holds the test framework and the test body. The replay trace contains the producing call and return.

A missing `replay` key with the recorded skip reason does not describe a defect. Bulldogger deliberately skipped replay because the frames already answer the question. Do not search for a trace in this case.

Use this procedure for the assertion shape. Replay reruns the same test under full recording, and the resulting trace is where the answer lives.

1. Read `capture_mode` in the evidence file. Check whether a `replay` key is present.
   When `replay_reproduced` is `false`, the child ran the test alone and passed.
   Treat that result as order-dependent or state-dependent.
2. When the failure came from an assertion, expect the frames to hold only the test framework and the test body.
   The code that produced the wrong value already returned before the assertion raised.
   This is expected. Read the replay trace for the value's origin.
3. Open the trace named by the `replay` key.
   Its first line is a header. The header carries `schema_version` and the recorded event set.
4. Narrow the trace to the application's own code.
   Filter events by path against the project's `lib` directory.
   This step removes the test framework and gem code, which make up most of the file.
5. Look for `return` events whose value is wrong: `false` where the test expected `true`, `nil` where it expected a value.
   More than one method can match this filter.
6. Anchor on the method the failure itself names, then walk down from there.
   The failure message, or a diagnostic inside the evidence, names the rule or
   the method that produced the reported value. Find that method's `call` event,
   and read the events that follow it before its own `return`.
   Those events are its subtree.
   Inside one subtree, `depth` orders the chain: a callee sits one level deeper
   than its caller, and returns first. A caller that returns the same wrong
   value straight after its callee is a relay, and the deepest wrong return in
   that chain produced the value.
   Confirm the source against its own line of code.

   Compare `depth` only inside one chain. A trace holds many unrelated
   subtrees, and other code legitimately returns `false` far deeper than the
   method at fault. Picking the greatest `depth` across the whole trace selects
   whichever unrelated branch happens to nest deepest.

## Queries

List every application return with the wrong value:

```sh
jq -c 'select(.event=="return" and .return.value=="false" and (.path|test("YOUR_PROJECT/lib"))) | {method, path, line}' trace-001.jsonl | sort | uniq -c
```

Replace `YOUR_PROJECT/lib` with the project's own `lib` directory.
`.return.value` holds a rendered string.
Compare it to the string `"false"` or `"nil"`.
A comparison against the Ruby literal `false` or `nil` matches nothing, because the value is a string.

Follow one candidate through the call tree:

```sh
jq -c 'select(.method=="Some::Class#method_name") | {depth, event, method, ret: .return.value}' trace-001.jsonl
```

Use the method label exactly as the first query printed it.
An instance method carries a `#` before its name.
A singleton method carries a `.` instead.
This query lists that method's own call and return events in sequence order.

Run this second query on the method the failure names, and on the candidates it
calls. Read the pairs it prints: a callee's `return` arrives before its
caller's, one `depth` deeper. When both carry the same wrong value, the caller
forwarded what the callee produced.

Do not rank the first query's output by `depth` alone. Those candidates come
from unrelated parts of the run, and a method that has nothing to do with the
failure can sit deeper than the one at fault.

## The limit

This procedure narrows the search.
It does not name a single line by itself.
A query over a whole trace can leave several candidate methods, with the true
source among them. Most of those candidates are unrelated code that returns
`false` for its own good reasons, so the list is a starting set rather than a
ranking. Following one call chain from the method the failure names removes the
relays and reaches the method that produced the value.
The agent must still read that method's own source line and confirm the value against the test's expectation.

See [`docs/trace-schema.md`](../../../docs/trace-schema.md) for every event field, and [`docs/evidence-schema.md`](../../../docs/evidence-schema.md) for the `replay` and `replay_reproduced` evidence fields.
