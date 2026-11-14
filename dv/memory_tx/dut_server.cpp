// Clock/transport adapter: log public levels before every active edge.
#include "Vmemory_tx_dut_top.h"
#include "verilated.h"
#include "verilated_cov.h"
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <memory>

template<size_t N> void read_hex(VlWide<N>& value, std::string text) {
    for(size_t i=0;i<N;i++) {
        const auto n=text.size();
        value[i]=n?std::stoul(text.substr(n>8?n-8:0),nullptr,16):0;
        text=n>8?text.substr(0,n-8):"";
    }
    if(!text.empty()) throw std::runtime_error("input width overflow");
}
template<size_t N> void write_hex(const VlWide<N>& value) {
    for(size_t i=N;i>0;i--) std::cout<<std::setw(8)<<std::setfill('0')<<value[i-1];
}
int main(int argc,char** argv) {
    auto context=std::make_unique<VerilatedContext>(); context->commandArgs(argc,argv);
    auto top=std::make_unique<Vmemory_tx_dut_top>(context.get());
    std::string line,stimulus,heads;
    while(std::getline(std::cin,line)) {
        std::istringstream input(line);
        unsigned reset,ready,abort_cell,qvalid,qid,qnext,qquery;
        if(!(input>>std::hex>>reset>>ready>>stimulus>>heads>>abort_cell>>qvalid>>qid>>qnext>>qquery)) return 2;
        top->clk=0;top->rst_n=reset;top->sink_ready=ready;
        read_hex(top->stimulus,stimulus);read_hex(top->heads,heads);
        top->abort_cell=abort_cell;top->queue_write_valid=qvalid;top->queue_id=qid;
        top->queue_value=qnext;top->queue_query=qquery;top->eval();
        std::cout<<"TM_EDGE "<<std::hex;
        write_hex(top->observed);
        std::cout<<' '<<unsigned(top->output_valid)<<' '<<top->output_data<<' '<<unsigned(top->output_keep)
                 <<' '<<unsigned(top->output_last)<<' '<<top->output_user<<' '<<unsigned(top->dispatch_ready)
                 <<' '<<unsigned(top->idle)<<' ';
        write_hex(top->head_fields);
        std::cout<<' '<<top->abort_next_value<<' '<<top->queue_next_value<<std::endl;
        top->clk=1;top->eval();context->timeInc(1);
    }
    top->final();context->coveragep()->write("coverage.dat");
    std::cout<<"TM_SERVER_DONE"<<std::endl;
    return 0;
}
