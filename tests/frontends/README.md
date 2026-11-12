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
