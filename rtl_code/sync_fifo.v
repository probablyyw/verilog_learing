//===================================
//author : 
//data   : 
//version:
//===================================

module sync_fifo #(
    parameter DW = 8,
    parameter DEEP = 16,
    parameter RDATA_MODE = 0 // 0 FWT MODE
                             // 1 
)(
    input          clk,
    input          rst_n,
    input          wr_en,
    input [DW-1:0] wr_data,

    input          rd_en, 
    output [DW-1:0] rd_data,
    output          full,
    output          empty
    
);

localparam ADDR_WIDTH = (DEEP > 1) ? $clog2(DEEP) : 1;
//-----------------------
// signal declare

reg [ADDR_WIDTH-1:0]   wr_ptr;
reg [ADDR_WIDTH-1:0]   rd_ptr;
reg [ADDR_WIDTH:0]     fifo_cnt;
wire                   rd_en_ture;
wire                   wr_en_ture;

//------------------------------------
// wr_en_ture gen and fifo_cnt gen

assign wr_en_ture = (wr_en & ~full) 1'b1 : 1'b0;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
       fifo_cnt <= {(ADDR_WIDTH+1){1'b0}};
    else if(wr_en_ture && rd_en_ture)
        fifo_cnt <= fifo_cnt;
    else if(wr_en_ture)
        fifo_cnt <= fifo_cnt + 1'd1;
    else if(rd_en_ture)
        fifo_cnt <= fifo_cnt - 1'd;
end

//----------------------------------------------
// wr_ptr gen 
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        wr_ptr <= {ADDR_WIDTH{1'b0}};
    else begin
        if(wr_en_ture & (DEEP > 1))
            if(wr_ptr == DEEP - 1)
                wr_ptr <= {ADDR_WIDTH{1'b0}};
            else
                wr_ptr <= wr_ptr + 1'd1;
    end
end

//---------------------------------------------
// rd_ptr gen
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        wr_ptr <= {ADDR_WIDTH{1'b0}};
    else begin
        if(rd_en_ture & (DEEP > 1))
            if(rd_ptr == DEEP - 1)
                rd_ptr <= {ADDR_WIDTH{1'b0}};
            else
                rd_ptr <= rd_ptr + 1'd1;
    end
end

//-----------------------------------------
// three mode read data 
// 0: from dual sram, need prefetch 
// 1: same as mode 0
// 2: normal read
generate
    if(RDATA_MODE == 0) begin: RDATA_MODE_0
    wire     mem_empty;
    reg      mem_empty_d;
    reg      valid;       //incdiate fifo data is valid 
    
    //------------------------------
    // mem_empty and mem_empty_d gen
    assign mem_empty = (fifo_cnt == {(ADDR_WIDTH+1){1'b0}}) ? 1'b1 : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            mem_empty_d <= 1'd0;
        else
            mem_empty_d <= mem_empty;
    end

    assign rd_en_ture = !mem_empty & (mem_empty_d | rd_en);

    //--------------------------------
    // instance dual sram
    dual_sram #(
        .DATA_WIDTH(DW),
        .ADDR_WIDTH($clog2(DEEP))
    ) U_mem(
        .RST_N     (rst_n     ),
        .CLK_W     (clk       ),
        .WR_EN     (wr_en_ture),
        .ADDR_W    (wr_ptr    ),
        .DATA_I    (wr_ptr    ),
        .CLK_R     (clk       ),
        .RD_EN     (rd_en_ture),
        .ADDR_R    (rd_ptr    ),
        .DATA_O    (rd_data   )
    );
    //---------------------------------------------------------------------------------------------
    // valid gen: real empty signal
    // when !mem_empty & mem_empty_d , prefetch data gen rd_en_ture next cycle data is valid
    // when  mem_empty & rd_en, last data output and not gen rd_en_ture ,next cycle data is invalid
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            valid <= 1'b0;
        else if(!mem_empty & mem_empty_d)
            valid <= 1'b1;
        else if(mem_empty & rd_en)
            valid <= 1'b0;
    end
    assign empty = !valid;
    end else if(RDATA_MODE == 1) begin
        wire     mem_empty;
        reg      mem_empty_d;
        reg      valid;       //incdiate fifo data is valid 
        reg [DW-1:0] buf_mem [DEEP-1:0] ;
        integer  II                     ;
        reg [DW-1:0] data_out;
    
        //------------------------------
        // mem_empty and mem_empty_d gen
        assign mem_empty = (fifo_cnt == {(ADDR_WIDTH+1){1'b0}}) ? 1'b1 : 1'b0;
    
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n)
                mem_empty_d <= 1'd0;
            else
                mem_empty_d <= mem_empty;
        end

        assign rd_en_ture = !mem_empty & (mem_empty_d | rd_en);

        //-------------------------------------------
        // wr data
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                for(II = 0; II < DEEP; II = II +1) begin
                    buf_mem[II] <= {(DW){1'b0}};
                end
            end else if(wr_en_ture)
                buf_mem[wr_ptr] <= wr_data;
        end

        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) 
                data_out <= {(DW){1'b0}};
            else if(rd_en_ture)
                data_out <= buf_mem[rd_ptr];
        end
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n)
                valid <= 1'b0;
            else if(!mem_empty & mem_empty_d)
                valid <= 1'b1;
            else if(mem_empty & rd_en)
                valid <= 1'b0;
        end
        assign empty = !valid;
        assign rd_data = data_out;
    end else if(RDATA_MODE == 2) begin
        reg [DW-1:0] buf_mem [DEEP-1:0] ;
        integer  II                     ;
        reg [DW-1:0] data_out           ;
        
        assign rd_en_ture = (rd_en & !empty);
        assign empty = (fifo_cnt == {(ADDR_WIDTH+1){1'b0}}) ? 1'b1 : 1'b0;

        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                for(II = 0; II < DEEP; II = II +1) begin
                    buf_mem[II] <= {(DW){1'b0}};
                end
            end else if(wr_en_ture)
                buf_mem[wr_ptr] <= wr_data;
        end

        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) 
                data_out <= {(DW){1'b0}};
            else if(rd_en_ture)
                data_out <= buf_mem[rd_ptr];
        end

        assign rd_data = data_out;
        
    end
endgenerate

assign full = (fifo_cnt == DEEP);

endmodule