//===================================
//author : 
//data   : 
//version:
//===================================

module sync_fifo #(
    parameter WD = 8,
    parameter DEEP = 16,
)(
    input    clk,
    input    rst_n,
    input    wr_en,
    input [WD-1:0] wr_data,
    
)