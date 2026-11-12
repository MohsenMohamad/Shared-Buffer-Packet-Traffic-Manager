# Frontend qualification inputs

These tests complement the [preserved investigation](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/tree/a48286d51b9dd195b18388e9ee3c70c8403ccc0b/tests/investigations/rtl-frontend-probes).
`generate.py` and the production-behavior fixtures are adapted from that exact
revision. They create disposable FIFO/CSR/statistics candidates from the current
registered RTL. Production conversion is deferred to the P01 follow-up.

`features.sv` and its independent simulation model add signed width, packed-record
memory arrays, parameter type overrides, heterogeneous memories, unpacked ports,
interfaces/modports and one/two-cycle read latency. Native frontend rejection is
recorded separately from accepted slang elaboration and completed synthesis.

Generated copies and commands live under ignored `.build/frontends`. Saved
results must distinguish parsing/elaboration from synthesis and actual execution.
Neither these fixtures nor declaration checks validate the integrated TM.

Current production conversion is checked separately from the historical
capability candidates. `generate.py` retrieves the immutable baseline in
`verification/representation.json` with `git show`; missing history is an error.
No mutable production duplicate is maintained. Current registered sources are
used by the `production` parse/elaboration/synthesis/profile/heterogeneous cases.
`representation-formal` runs actual registered proofs and supplementary old/new
sequential equivalence; `fifo-mapping` also checks the current record-array
alternative. See [migration evidence](../../docs/results/rtl-representation.md).

`make formal-symbols RUN_ARGS='--timeout 120'` executes the small F01 recipe
qualification registered in `verification/formal.json`. The production-source
example is [symbolic_inputs.sv](../../formal/symbolic/symbolic_inputs.sv);
[results and negative identities](../../docs/results/F01-formal-symbols.md)
distinguish native fixedness, rejected Slang decoration, missing-assumption
counterexamples and frontend rejection. `anyconst_control.sv`,
`symbolic_attributes.sv` and `symbolic_functions.sv` are diagnostic fixtures;
the formal source registry cannot exempt or admit them as production harnesses.
