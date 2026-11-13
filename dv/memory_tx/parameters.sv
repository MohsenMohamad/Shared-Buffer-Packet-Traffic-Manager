// Parameter-contract probe only; contains no hardware implementation.
module memory_tx_parameters #(
`include "tm_parameters.svh"
)(output logic configuration_valid);
`include "tm_validate.svh"
assign configuration_valid=CONFIG_VALID;
endmodule
