module record_memory_formal(input clk,we,input [1:0] wa,ra,input [9:0] wd);
    wire [9:0] rd;
    wire [39:0] contents;
    record_memory dut(.*);
    // Plain-vector independent read-first memory model. Validity avoids making
    // any claim about unwritten storage or its initial values.
    reg [9:0] reference[0:3];
    reg [3:0] written=0;
    reg read_known=0;
    reg [9:0] expected;
    // Explicit labels avoid the native frontend's generated-label collision.
    always @(posedge clk) begin
        if(written[0]) a_contents0: assert(contents[0 +:10]==reference[0]);
        if(written[1]) a_contents1: assert(contents[10+:10]==reference[1]);
        if(written[2]) a_contents2: assert(contents[20+:10]==reference[2]);
        if(written[3]) a_contents3: assert(contents[30+:10]==reference[3]);
    end
    always @(posedge clk) begin
        if(read_known) a_word: assert(rd==expected);
        read_known<=written[ra];
        expected<=reference[ra];
        if(we)begin reference[wa]<=wd;written[wa]<=1;end
        c_read: cover(read_known && rd==10'h3ff);
        c_collision: cover(read_known && we && wa==ra);
        c_last: cover(read_known && ra==3);
    end
endmodule
