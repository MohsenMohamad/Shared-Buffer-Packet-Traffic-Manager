# F01: Fixed and time-varying symbolic inputs

## Objective and entry

Close the formal-frontend prerequisite for P03 without changing production RTL,
tool versions or the required property set. Consume the selected Slang frontend
and [formal rules](../../spec/formal.md). All production harnesses now use
explicit arbitrary-input ports and follow one source policy.

## Work

1. Qualify the selected frontend's explicit-input semantics; unsupported symbolic
   declarations are rejected by the uniform source guard.
2. All harnesses expose arbitrary stimulus through explicit top-level input ports.
   A fixed witness is arbitrary at the first sample and held across every later
   sample by a documented assumption. The history-valid bit is initialized once
   and is not reset with the DUT; the witness cannot change across later resets.
3. Qualify time-varying and fixed recipes with assert/cover pairs, distinct
   reachable witness values, a later reset, and a missing-stability-assumption
   negative control. Do not add a witness-range restriction without a property-
   specific reason or constrain a witness to a value derived from the DUT.
4. Fail closed on unqualified `anyseq`/`anyconst` attributes and `$anyseq`/
   `$anyconst` functions in new Slang formal harness sources and included headers.
   Apply this policy to every production harness without exceptions. Handle
   declaration formatting and comments deliberately.
5. Register the small recipe qualification and guard checks through the existing
   runner/formal registry. Keep parsing failure, property failure, unreachable
   cover and tool error distinct. Check affected production property inventories;
   reuse unchanged recorded results rather than repeating unrelated studies.

## Completion

The recipe has actual prove/cover/negative evidence on the selected stack, the
guard rejects an unsupported new harness, and documentation identifies executable
commands and source scope. New harnesses consume the qualified recipe directly.
F01 blocks P03; writing this card or its example alone does not close the gate.

## Qualified result

Complete at the configurations and limits in the [F01 results](../../results/F01-formal-symbols.md).
Run `make formal-symbols RUN_ARGS='--timeout 120'` for the width-1/width-4
recipe, named missing-assumption detection, distinct-value and later-reset
covers, and source/registry guard checks. The recipe is qualified for production
harnesses; this fixture does not establish FP-QUEUE or FP-ORDER.
