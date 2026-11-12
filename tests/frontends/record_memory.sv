// Isolate array-of-packed-record inference from imports/type parameters.
module record_memory(input logic clk,we,input logic [1:0] wa,ra,
                     input logic [9:0] wd,output logic [9:0] rd
`ifdef FORMAL
                     ,output wire [39:0] contents
`endif
                     );
    typedef struct packed {logic [7:0] payload;logic [1:0] tag;} word_t;
    word_t slots[0:3];
`ifdef FORMAL
    // Proof-only observation; these ports are absent from synthesis capability runs.
    for(genvar i=0;i<4;i++)assign contents[10*i +:10]=slots[i];
`endif
    always_ff @(posedge clk) begin
        if(we)slots[wa]<=wd;
        rd<=slots[ra];
    end
endmodule
