// Multi-egress boundary declaration. Production behavior is assigned separately.
module tm_multi_ports #(
`include "tm_multi_parameters.svh"
`define TM_MULTI_ANSI_TYPES
`include "tm_multi_types.svh"
`undef TM_MULTI_ANSI_TYPES
) (
`include "tm_multi_ports.svh"
);
`include "tm_multi_validate.svh"
endmodule
