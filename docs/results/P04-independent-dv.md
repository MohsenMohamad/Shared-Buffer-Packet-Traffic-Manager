# Independent scheduler DV

This change audits and extends the retained P04 component checks on merged
production P03/P04 RTL. Production RTL is unchanged. Validation is in progress;
no final qualification result is claimed here yet. Historical author results
remain in [P04](P04-scheduler.md) with their original provenance.

## Audit and checking boundary

The retained P07 `tm_schedule_checker` derives committed FIFO packet lists,
head lengths, canonical visits, quanta and TX ownership without reading the
RTL FSM. It computes the expected dispatch before applying the current commit;
a singleton replacement preserves post-debit credit and only merged zero clears
it. It checks grant legality before a separate mandatory baseline timing check.
There is no grant-following or timing-disabling mode.

The component fixture previously passed its sequence packet directly into that
checker. The new passive event sampler reconstructs the packet from the sampled
commit API. A positive probe destroys the sequence object's length after driving
the API, demonstrating that it cannot supply the expectation. Descriptor
metadata and TX retirement remain fixture endpoints; no real payload engine or
external-input-to-output byte correctness is established.

The retained author formal properties use DUT cursor/visit state to compute
expected credit and grant eligibility. They remain at their original location.
The new `scheduler_policy.svh` derives its own policy history from reset,
pre-state queue queries, configuration and TX events. Expected dispatch advances
that history; observed dispatch and RTL state never supply its next state.
Independent grant/head, mandatory timing, credit, cursor, visit and ownership
assertions check production RTL. RTL state equalities are induction lemmas,
not assumptions or reference inputs.

Finite accounting retains both equations every checked edge:

```text
entered_visits * quantum = dispatched_bytes + deficit + discarded_empty_credit
dispatched_bytes = delivered_bytes + unretired_TX_bytes
```

## Qualification and evidence

The scheduler suite retains both production modes and the original directed
arithmetic, replacement, reactivation, same/different-qid, readiness, TX stalls,
maximum-bound and finite equal/unequal-quantum cases. New cases pause RUN during
a funded visit and reset while a maximum packet is owned and stalled.

Production source-copy mutations qualify an extra quantum on a continuing
packet and omitted dispatches in both modes. Formal additionally freezes the
cursor to qualify the independent policy-history detector. Required detector
names and nonempty counterexample waveforms distinguish intended failures from
crashes or missing tools. No production source is mutated in place.

Saved coverage extraction checks a passing unmutated case, exact profile and
parameters, current source fingerprints, raw artifact hashes and regenerated
functional counters. It rejects missing, duplicate and unhit mandatory bins.
DRR and packet-RR exclusions and code holes remain visible per elaboration;
collection does not establish system coverage closure.

## Remaining composition obligations

P09/P10 still own real metadata/TX composition, packet-rate attribution and a
reviewed baseline/optimization decision. P11B owns integrated proof closure;
P12 owns system fairness. No local safety result assumes sink progress. Finite
progressing-fixture tests are not unbounded liveness. Independent verified scope
is established only when the passing DV PR merges.
