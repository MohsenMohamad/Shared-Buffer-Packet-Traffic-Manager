module bits_type(input logic [$bits(tm_fixed::axil_request_t)-1:0] req_bits, output logic [31:0] address);
tm_fixed::axil_request_t req;
assign req=req_bits;
assign address=req.awaddr;
endmodule
module bits_type_test;
logic [110:0] req_bits;
wire [31:0] address;
bits_type dut(.*);
initial begin
req_bits='0;req_bits[109 -:32]=32'h12345678;
#1;assert(address==32'h12345678) else $fatal(1,"BITS_FAIL");
$display("BITS_TYPE_PASS");$finish;
end
endmodule
