// Isolate array-of-packed-record inference from imports/type parameters.
module record_memory(input logic clk,we,input logic [1:0] wa,ra,
                     input logic [9:0] wd,output logic [9:0] rd);
    typedef struct packed {logic [7:0] payload;logic [1:0] tag;} word_t;
    word_t slots[0:3];
    always_ff @(posedge clk) begin
        if(we)slots[wa]<=wd;
        rd<=slots[ra];
    end
endmodule
