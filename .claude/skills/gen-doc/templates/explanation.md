<!-- doc-type: explanation -->
# <!-- claim: what it does, as a sentence, e.g. "FLAT stores reach memory through seven stages; the TA adapter is the choke point" -->

*<Audience> · <Status, YYYY-MM-DD> · <Scope: the code, mechanism or concept covered, with repo@commit if code>*

!!! abstract "In short"
    <!-- one sentence: what it does and why it exists -->

    1. <!-- key fact about how it works, e.g. "Every FLAT op is split into one request per active lane" -->
    2. <!-- key fact -->
    3. <!-- key fact (3-5 in total) -->

    **Where it sits:** <!-- the component it belongs to, what calls it, what it calls -->

## <!-- what happens end to end, e.g. "A store travels decode → issue → SQ → TA adapter → VCA" -->

<!-- the big picture: one diagram or a numbered flow; name the running example used in every later section -->
<!-- if the flow crosses functions/threads/libraries, use STYLE.md section 3a: an actors table, a numbered overview,
     then per step a claim heading + short "A → B → C" chain + "Full call tree: step N" toggle
     (see examples/call-tree-walkthrough.md) -->

## <!-- step 1 as a claim about what happens, e.g. "Decode marks the instruction as a VMEM write" -->

<!-- first sentence = what happens; then the minimal code at file:line@commit; explain the why, not each line -->

```cpp
// file.cpp:123 @ <commit>
```

## <!-- step 2: what happens next -->

<!-- follow the running example through the flow, in execution order -->

## <!-- where it goes wrong or surprises people, e.g. "Requests stall when the FIFO is full" -->

<!-- gotchas, edge cases, limits; say what is unknown -->

## Related

<!-- the how-to for using it, the reference for exact fields, the source location; descriptive link names -->

<details markdown="1">
<summary>Full deep dive: <!-- e.g. the state machine, every field, the history --></summary>

<!-- detail most readers skip; glossary of terms at the end -->

</details>
