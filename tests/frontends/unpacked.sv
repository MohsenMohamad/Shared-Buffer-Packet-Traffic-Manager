module unpacked_ports(input logic [7:0] values[0:3],input logic [1:0] index,output logic [7:0] value);
    assign value=values[index];
endmodule
