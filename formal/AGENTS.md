# Formal guidance

Use formal.md and the module's behavioral contract. Target production RTL. Document assumptions, configurations, abstractions, reset model and result per property family. Keep progressing-sink assumptions out of safety tasks. Reach relevant covers, test selected mutations and inspect counterexamples. Do not replace an unbounded claim with a bounded result without reporting that changed scope.

Follow the [root ownership and preparation policy](../AGENTS.md#separate-rtl-and-independent-dv-ownership)
for role-specific source access and task gates.
