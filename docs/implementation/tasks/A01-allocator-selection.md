# A01 allocator selection

The multi-egress allocator may choose any ID in the pre-edge free set.
Descriptor ranks must be distinct across up to four primary or two small
grants. One cell may materialize on each edge. Retirements and cleanup
are separately accepted and become reusable on the following edge.

Use the measured grouped cell selector in
[the cell-control fixture](../../../experiments/queue-control/cell_control.sv)
and ranked pre-edge descriptor selection in
[the admission fixture](../../../experiments/queue-control/admission.sv)
as design references. The [control decision](../../decisions/0010-multi-egress-queue-control.md)
keeps the same-edge service boundary. The
[historical scaling study](../../results/allocator-scaling.md) identified
the long dependency of scalar cell selection in the old design.

Measure selection arrival and mapped depth for each pool separately from
the full update and consumer paths. Keep grants, returns, count and ID
consumers live. Compare any alternative with matched capacities, legal
same-edge behavior, area and constraints. The small and primary RTL checks
are both required. Record any reset constraint or timing assumption using
[the reset convention](../../spec/reset-timing.md). Composed admission and
reset closure remain part of integration.
