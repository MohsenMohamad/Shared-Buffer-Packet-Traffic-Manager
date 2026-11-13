# Formal guidance

Use formal.md and the module's behavioral contract. Target production RTL. Document assumptions, configurations, abstractions, reset model and result per property family. Keep progressing-sink assumptions out of safety tasks. Reach relevant covers, test selected mutations and inspect counterexamples. Do not replace an unbounded claim with a bounded result without reporting that changed scope.

## Independent proof ownership

Independent DV owns harnesses, binds, assumptions, covers, mutations and formal
registration. Production RTL and embedded assertions belong to the RTL owner.
Audit retained designer properties/models before reuse and record their provenance.
Use explicit qualified fixed witnesses where needed, stable through later resets;
state the caller ownership/not-already-queued assumptions that composition must
discharge. Keep detecting failures open for separate RTL fixes, then rebase and
reverify the affected merged implementation.
