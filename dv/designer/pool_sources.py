"""Exact production source order for the pool designer checks and timing study."""

INCLUDE = "rtl/include/multi_egress"
PUBLIC = [f"{INCLUDE}/{name}" for name in (
    "tm_multi_fixed.sv", "tm_multi_parameters.svh", "tm_multi_types.svh",
    "tm_multi_validate.svh", "tm_multi_ports.sv", "tm_multi_ports.svh",
    "tm_multi_csr.sv",
)]
RTL = [PUBLIC[0]] + [f"rtl/multi_egress/{name}.sv" for name in (
    "tm_pool_first_free", "tm_cell_pool", "tm_descriptor_pool",
    "tm_reservation_accounting", "tm_resource_pools",
)]
PROFILES = {"primary": 0, "small": 1}
LOCKS = ["tools/dependencies.json", "tools/packages.lock.json"]
