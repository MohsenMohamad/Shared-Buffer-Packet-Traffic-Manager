// Independent bounded examples complement the production-derived audit cases.
package fixed_types;
    typedef enum logic [1:0] {IDLE, VALID, ERROR} state_t;
    typedef struct packed {logic signed [7:0] data; state_t state;} sample_t;
endpackage

module typed_memory #(
    parameter integer WIDTH=8, DEPTH=4,
    parameter type WORD=logic [WIDTH-1:0]
)(input logic clk,we,input logic [$clog2(DEPTH)-1:0] wa,ra,
  input WORD wd,output WORD rd);
    WORD mem [0:DEPTH-1];
    always_ff @(posedge clk) begin
        if(we) mem[wa]<=wd;
        rd<=mem[ra];
    end
endmodule

interface lane_if #(parameter integer WIDTH=8);
    logic [WIDTH-1:0] data;
    logic valid,ready;
    modport source(output data,valid,input ready);
    modport sink(input data,valid,output ready);
endinterface
module lane_sink(lane_if.sink bus, output logic [7:0] result);
    assign bus.ready=1'b1;
    assign result=8'(bus.data);
endmodule

module feature_top(input logic clk,we,input logic [1:0] wa,ra,
 input logic [9:0] wd0,input logic [15:0] wd1,
 input logic signed [7:0] a,b,
 input logic [7:0] lanes [0:1],
 output logic [9:0] rd0,output logic [15:0] rd1,
 output logic signed [8:0] sum,
 output logic [7:0] selected,echo,
 output logic [15:0] delayed);
    import fixed_types::*;
    typedef struct packed {logic [12:0] data; logic [2:0] tag;} wider_t;
    sample_t v0,r0;
    wider_t v1,r1;
    localparam integer W0=$bits(sample_t),W1=$bits(wider_t);
    assign v0=wd0;
    assign v1=wd1;
    assign rd0=r0;
    assign rd1=r1;
    typed_memory #(.WIDTH(W0),.WORD(sample_t)) m0(clk,we,wa,ra,v0,r0);
    typed_memory #(.WIDTH(W1),.WORD(wider_t)) m1(clk,we,wa,ra,v1,r1);
    always_ff @(posedge clk) delayed<=r1;
    // Nine-bit context must sign extend each operand before addition.
    assign sum=$signed(a)+$signed(b);
    assign selected=lanes[wa[0]];
    lane_if #(.WIDTH(8)) lane();
    assign lane.data=lanes[1];
    assign lane.valid=we;
    lane_sink sink(lane,echo);
endmodule
