# Technical references

The project contracts define its supported behavior and completion boundary. External references define the underlying protocols, algorithms and tool semantics; they do not imply product compliance beyond the specified subset.

| Reference | Application |
|---|---|
| [Arm AXI-Stream IHI 0051B](https://documentation-service.arm.com/static/64819f1516f0f201aa6b963c?token=) | Ready/valid transfer and byte/packet qualifiers; the endpoint accepts the specified contiguous-byte subset |
| [Arm AXI/AXI4-Lite IHI 0022H](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf) | Independent channels, register transfers, strobes and responses |
| [Shreedhar and Varghese: Efficient Fair Queuing Using Deficit Round-Robin](https://web.stanford.edu/class/ee384x/EE384X/papers/DRR.pdf) | Byte deficit carry-over and backlog-conditioned fairness |
| [Accellera UVM reference source](https://github.com/accellera-official/uvm-core) | Actual UVM classes, agents, sequences, phases and checking infrastructure |
| [SymbiYosys documentation](https://yosyshq.readthedocs.io/projects/sby/en/stable/) | Prove, bounded and cover semantics, frontend/property limitations |
| [Yosys documentation](https://yosyshq.readthedocs.io/projects/yosys/en/latest/) | Synthesis, memory treatment and technology mapping |
| [OpenSTA](https://github.com/The-OpenROAD-Project/OpenSTA) | Liberty/netlist/SDC timing analysis |

Exact external implementation dependencies and the reference library are pinned in `tools/dependencies.json`. Simulator support/qualification references are listed in toolchain.md.
