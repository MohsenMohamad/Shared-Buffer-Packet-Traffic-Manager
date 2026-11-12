# F01: Fixed and time-varying symbolic inputs

## Objective and entry

Close the formal-frontend prerequisite for P03 without changing production RTL,
tool versions or the required property set. Consume the selected Slang frontend
and [formal rules](../../spec/formal.md). The legacy adapter in
`tools/frontend.py` is restricted to `storage_formal` and `csr_formal`; it is not
a qualified general symbolic translator.

## Work

1. Reproduce on the pinned stack the difference between native `anyconst` and an
   undriven Slang signal. Retain its spurious assertion failure and false cover
   reach as the rejected control, never as production evidence.
2. New harnesses expose arbitrary stimulus through explicit top-level input ports.
   A fixed witness is arbitrary at the first sample and held across every later
   sample by a documented assumption. The history-valid bit is initialized once
   and is not reset with the DUT; the witness cannot change across later resets.
3. Qualify time-varying and fixed recipes with assert/cover pairs, distinct
   reachable witness values, a later reset, and a missing-stability-assumption
   negative control. Compare the intended semantics with a native-supported
   minimized control. Do not add a witness-range restriction without a property-
   specific reason or constrain a witness to a value derived from the DUT.
4. Fail closed on unqualified `anyseq`/`anyconst` attributes and `$anyseq`/
   `$anyconst` functions in new Slang formal harness sources and included headers.
   Keep the existing two-harness `anyseq` bridge and its qualification unchanged.
   Unsupported-feature fixtures are explicit diagnostic exceptions, not a broad
   production bypass. Handle declaration formatting and comments deliberately.
5. Register the small recipe qualification and guard checks through the existing
   runner/formal registry. Keep parsing failure, property failure, unreachable
   cover and tool error distinct. Check affected legacy bridge/property inventory;
   reuse unchanged recorded results rather than repeating unrelated studies.

## Completion

The recipe has actual prove/cover/negative evidence on the selected stack, the
guard rejects an unsupported new harness, and documentation identifies executable
commands and source scope. New harnesses consume the qualified recipe directly.
F01 blocks P03; writing this card or its example alone does not close the gate.
