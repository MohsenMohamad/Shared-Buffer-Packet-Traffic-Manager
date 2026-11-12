# Current frontend acceptance

`make frontends` runs standalone packed-record memory, unpacked-port and
interface parse/elaboration/synthesis checks; a heterogeneous-instance simulation;
and record-memory formal proof and reachability checks.

`make formal-symbols` runs the explicit arbitrary-input recipe and the deliberate
missing-stability negative, plus the production source-policy tests.

Production formal harnesses use explicit input ports and run directly through
`formal-rtl`. Historical parser comparisons, production snapshots and generated
harness adapters are removed. These fixtures establish frontend capabilities,
not production traffic-manager correctness.
