module feature_test;
    logic clk=0;
    always #5 clk=~clk;
    logic we=0;
    logic [1:0] wa=0,ra=0;
    logic [9:0] wd0=0,rd0;
    logic [15:0] wd1=0,rd1,delayed;
    logic signed [7:0] a,b;
    logic signed [8:0] sum;
    logic [7:0] lanes[0:1],selected,echo;
    feature_top dut(.*);
    logic [9:0] ref0[0:3];
    logic [15:0] ref1[0:3],previous_read;
    task automatic cycle(input bit check_read);
        logic [9:0] expected0;
        logic [15:0] expected1;
        expected0=ref0[ra];expected1=ref1[ra];
        @(posedge clk);#1;
        if(check_read) begin
            assert(rd0===expected0 && rd1===expected1) else $fatal(1,"MEMORY_LATENCY_DATA");
            assert(delayed===previous_read) else $fatal(1,"MEMORY_SECOND_STAGE");
        end
        if(we) begin ref0[wa]=wd0;ref1[wa]=wd1;end
        previous_read=rd1;
        @(negedge clk);
    endtask
    initial begin
        a=-128;b=-1;lanes[0]=8'h12;lanes[1]=8'haf;
        #1;assert(sum==-129 && selected==8'h12 && echo==8'haf) else $fatal(1,"SIGNED_OR_UNPACKED");
        for(int i=0;i<4;i++) begin
            we=1;wa=2'(i);ra=2'(i);wd0=10'(10'h120+i);wd1=16'(16'hab00+i);cycle(0);
        end
        we=0;ra=0;cycle(0);
        for(int i=0;i<16;i++) begin
            ra=2'(i);wa=2'(i+1);we=(i%3==0);wd0=10'(i+17);wd1=16'(i+500);
            a=8'(i-8);b=8'(i+100);#1;
            assert(sum==9'((i-8)+(i+100))) else $fatal(1,"SIGNED_WIDTH");
            cycle(1);
        end
        $display("TM_FEATURE_PASS reads=16 memories=2 latency=1,2 signed=9 unpacked=2 interface=1");$finish;
    end
endmodule
