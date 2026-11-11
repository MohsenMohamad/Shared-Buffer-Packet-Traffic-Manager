interface transfer_if #(parameter integer WIDTH=8);
    logic valid,ready;
    logic [WIDTH-1:0] data;
    modport sink(input valid,data,output ready);
endinterface
module interface_sink(transfer_if.sink port,output logic [7:0] data);
    assign port.ready=1'b1;
    assign data=port.data;
endmodule
module interface_top(input logic [7:0] data,input logic valid,output logic [7:0] result,output logic ready);
    transfer_if bus();
    assign bus.valid=valid;
    assign bus.data=data;
    assign ready=bus.ready;
    interface_sink sink(bus,result);
endmodule
