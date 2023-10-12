


module axi_register_slice #(
    parameter PLD_W   = 32,  // payload width
    parameter RS_MODE = 0 ,  // 0: insert one rs , 1: insert muti rs
    parameter TMO     = 0 ,  // when RS_MODE == 0, it works.
                             // 0 - pass through mode
                             // 1 - forward timing mode
                             // 2 - full timing mode
                             // 3 - backward timing mode
    parameter PIPE_DEPTH = ls
    2 // when RS_MODE == 1, it works, and it must grate than 2

) (
    input                clk,
    input                rst_n,

    input                i_valid,
    output               o_ready,
    input [PLD_W-1:0]    i_payload,

    output               o_valid,
    input                i_ready,
    output [PLD_W-1:0]   o_payload
);

//------------------------------------------------------
// loop value declare
//-------------------------------------------------------
genvar   i;

//-------------------------------------------------------
// forward timing mode 
// i_payload and i_valid have to be registered
//-------------------------------------------------------
generate if(RS_MODE == 0) begin:
    if(TMO == 0) begin: PASSTHROUGH
        assign o_valid   = i_valid;
        assign o_payload = i_payload;
        assign o_ready   = i_ready;
    end
    else if(TMO == 1) begin: FORWARD_REGISTERED
        wire [PLD_W-1:0] s_pld_fd;
        wire             s_ready_fd;
        wire             s_valid_fd;
        reg              r_valid_fd;
        reg  [PLD_W-1:0] r_pld_fd;
//--------------------------------------------------------
//o_ready (s_ready_fd) gen
//--------------------------------------------------------
        assign s_ready_fd = i_ready | (!r_valid_fd);

//-------------------------------------------------------
//o_valid (r_valid_fd) gen
//-------------------------------------------------------
        assign s_valid_fd = (s_ready_fd) ? i_valid : r_valid_fd;

        always@(posedge clk or negedge rst_n) begin
            if(rst_n == 1'b0) begin
                r_valid_fd <= 1'b0;
            end else begin
                r_valid_fd <= s_valid_fd;
            end
        end

//---------------------------------------------------------
//o_payload (r_pld_fd) loading
//---------------------------------------------------------
        assign s_pld_fd = (s_ready_fd & i_valid) ? i_payload : r_pld_fd;

        always @(posedge clk or negedge rst_n) begin
            if(rst_n == 1'b0) begin
                r_pld_fd <= {PLD_W{1'b0}};
            end
            else begin
                r_pld_fd <= s_pld_fd;
            end
        end

        assign o_valid   = r_valid_fd;
        assign o_payload = r_pld_fd;
        assign o_ready   = s_ready_fd;
    end
    else if(TMO == 2) begin: PLD_FL_PROC
//----------------------------------------------------------------
// FULL timing mode
// all i_ready, i_valid and i_paylod have to be registered
// use two payload registers to store payload and the two registers
// organized as FIFO
//-----------------------------------------------------------------
        reg [1:0]      r_cnt;
        reg            r_ready_f1;
        reg            r_valid_f1;

        wire [1:0]     s_cnt;
        wire [1:0]     ss_cnt;
        wire [1:0]     sss_cnt;
        wire           s_ready_f1;
        wire           ss_ready_f1;
        wire           s_ready_mux;
        wire           s_valid_f1;
        wire           ss_valid_f1;
        wire           s_valid_mux;
//------------------------------------------------------------------
// pointer_in gen. which payload register is for loading payload.
// if i_valid and o_ready high ,pointer_in increases by 1
//------------------------------------------------------------------
        wire [PLD_W-1:0]  s_pld_f1;
        wire [PLD_W-1:0]  s_pld_f1_zero;
        wire [PLD_W-1:0]  s_pld_f1_one;
        wire              s_pointer_in;
        wire              s_pointer_out;
        reg  [PLD_W-1:0]  r_pld_f1_zero;
        reg  [PLD_W-1:0]  r_pld_f1_one;
        reg               pointer_in;
        reg               pointer_out;

//-------------------------------------------------------------------
// r_cnt gen ,which indicates the two registers full or empty
// if i_ready and o_valid high , r_cnt -1;
// if o_ready and i_valid high , r_cnt +1;
// if all the four signal high, r_cnt = r_cnt;
// if r_cnt == 2 , two registers full;
// if r_cnt == 0 , two registers empty;
//--------------------------------------------------------------------
        assign sss_cnt = (i_ready & r_valid_f1) ? (r_cnt - 2'h1) : r_cnt;
        assign ss_cnt  = (r_ready_f1 & i_valid) ? (r_cnt + 2'h1) : sss_cnt;
        assign s_cnt   = (i_ready & r_valid_f1 & r_ready_f1 & i_valid) ? r_cnt : ss_cnt;

        always @(posedge clk or negedge rst_n) begin
            if(rst_n == 1'b0) begin
                r_cnt <= 2'b0;
            end
            else begin
                r_cnt <= s_cnt;
            end
        end

//---------------------------------------------------------------------------
// o_ready (r_ready_f1) gen
//---------------------------------------------------------------------------
        assign s_ready_mux = r_ready_f1 & i_valid & (!(r_valid_f1 & i_ready)) & (r_cnt == 2'b0);
        assign ss_ready_f1 = s_ready_mux ? 1'b0 : r_ready_f1;
        assign s_ready_f1  = i_ready | ss_ready_f1;

        always @(posedge clk or negedge rst_n) begin
            if(rst_n == 1'b0) begin
                r_ready_f1 <= 1'b1;
            end
            else begin
                r_ready_f1 <= s_ready_f1;
            end
        end
//---------------------------------------------------------------------------
// o_valid (r_valid_f1) gen
//---------------------------------------------------------------------------
        assign s_valid_mux = r_valid_f1 & i_ready & (!(r_ready_f1 & i_valid)) & (r_cnt == 2'b01);
        assign ss_valid_f1 = s_valid_mux ? 1'b0 : r_valid_f1;
        assign s_valid_f1  = i_valid | ss_valid_f1;

        always @(posedge clk or negedge rst_n) begin
            if(rst_n == 1'b0) begin
                r_valid_f1 <= 1'b0;
            end
            else begin
                r_valid_f1 <= s_valid_f1;
            end
        end

        assign s_pointer_in = ( i_valid & r_ready_f1) ? !pointer_in : pointer_in;

        always @(posedge clk or negedge rst_n) begin
            if(rst_n == 1'b0) begin
                pointer_in <= 1'b0;
            end
            else begin
                pointer_in <= s_pointer_in;
        end
//---------------------------------------------------------------------------
// payload registers loading and sample 
// if i_valid and o_ready high and pointer_in low , payload should be load
// into paylod register 0. if i_valid and o_ready high and pointer_in high,
// payload should be load into paylod register 1.
// on the sample side ,if pointer_out low, pick up payload from register 0
//----------------------------------------------------------------------------
        assign s_pld_f1_zero = ( i_valid & r_ready_f1 & (!pointer_in) ) ? i_paylod : r_pld_f1_zero;
        assign s_pld_f1_one  = ( i_valid & r_ready_f1 & pointer_in    ) ? i_payload: r_pld_f1_one ;

        always @(posedge clk or negedge rst_n) begin
            if(rst_n == 1'b0) begin
                r_pld_f1_zero <= {PLD_W{1'b0}};
            end
            else begin
                r_pld_f1_zero <= s_pld_f1_zero;
            end
        end

        always @(posedge clk or negedge rst_n) begin
            if(rst_n == 1'b0) begin
                r_pld_f1_one <= {PLD_W{1'b0}};
            end
            else begin
                r_pld_f1_one <= s_pld_f1_one;
            end
        end

//---------------------------------------------------------------------------
// pointer_out gen
//---------------------------------------------------------------------------

        assign s_pointer_out = ( r_valid_f1 & i_ready) ? !pointer_out : pointer_out;

        always @(posedge clk or negedge rst_n) begin
            if( rst_n == 1'b0) begin
                pointer_out <= 1'b0;
            end
            else begin
                pointer_out <= s_pointer_out;
            end
        end

        assign s_pld_f1  = pointer_out ? r_pld_f1_one : r_pld_f1_zero;
        assign o_payload = s_pld_f1;
        assign o_ready   = r_ready_f1;
        assign o_valid   = r_valid_f1;

    end
    else if(TMO == 3) begin: BACKWARD_REGISTERED
        reg             r_ready_bd;
        reg             r_sel     ;
        reg             r_valid_bd;
        reg [PLD_W-1:0] r_pld_bd;
        
        wire            s_ready_bd;
        wire            s_valid_bd;
        wire            ss_valid_bd;
        wire            sss_valid_bd;
        wire            s_sel;
        wire            ss_sel;
        wire [PLD_W-1:0] s_pld_bd;
        wire [PLD_W-1:0] ss_pld_bd;

//-----------------------------------------------------------------
// o_valid (s_valid_bd) gen
//-----------------------------------------------------------------
        assign sss_valid_bd = r_ready_bd ? i_valid : r_valid_bd;

        always @(posedge clk or negedge rst_n) begin
            if( rst_n == 1'b0) begin
                r_valid_bd <= 1'b0;
            end
            else begin
                r_valid_bd <= sss_valid_bd;
            end
        end

        assign ss_valid_bd = r_sel ? r_valid_bd : i_valid;
        assign s_valid_bd  = ss_valid_bd | (!r_ready_bd) ;

//-----------------------------------------------------------------
// o_ready (r_ready_bd) gen
//-----------------------------------------------------------------
        assign s_ready_bd = s_valid_bd ? i_ready : r_ready_bd;

        always @(posedge clk or negedge rst_n) begin
            if( rst_n == 1'b0) begin
                r_ready_bd <= 1'b1;
            end
            else begin
                r_ready_bd <= s_ready_bd;
            end
        end
//-------------------------------------------------------------------
//r_sel gen .used to select payload from i_payload or from payload 
//register. if i_ready low and i_valid high ,payload not sampled
// if i_ready hihg, i_valid low and o_valid high, payload sampled
//-------------------------------------------------------------------
        assign ss_sel = ( s_valid_bd & i_ready & (!r_ready_bd) ) ? 1'b0 : r_sel;
        assign s_sel  = ( i_valid & (!i_ready)) | ss_sel;

        always @(posedge clk or negedge rst_n) begin
            if( rst_n == 1'b0) begin
                r_sel <= 1'b0;
            end
            else begin
                r_sel <= s_sel;
            end
        end

//---------------------------------------------------------------------
// payload loading and select
// if r_sel is 0 , o_payload (s_pld_bd) from i_payload.
// if r_sel is 1 , o_payload (s_pld_bd) from register.
//----------------------------------------------------------------------

        assign ss_pld_bd = (r_ready_bd & i_valid) ? i_payload : r_pld_bd;

        always @(posedge clk or negedge rst_n) begin
            if(rst_n == 1'b0) begin
                r_pld_bd <= {PLD_W{1'b0}};
            end
            else begin
                r_pld_bd <= ss_pld_bd;
            end
        end

        assign s_pld_bd  = r_sel ? r_pld_bd : i_payload;
        assign o_payload = s_pld_bd;
        assign o_ready   = r_ready_bd;
        assign o_valid   = s_valid_bd;
    end
endgenerate

generate if(RS_MODE == 1) begin: PIPELINE
    reg              valid_l[PIPE_DEPTH];
    wire             ready_l[PIPE_DEPTH];
    reg [PLD_W-1:0]  payload_l[PIPE_DEPTH];

//------------------------------------------------------
// o_ready gen
//------------------------------------------------------

    for(i=0; i < PIPE_DEPTH; i = i + 1) begin
        if( i == PIPE_DEPTH -1) begin
            assign ready_l[i] = i_ready;
        end
        else begin
            assign ready_l[i] = ~valid_l[i+1] || ready_l[i+1];
        end
    end
    assign o_ready = ~valid_l[0] || ready_l[0];
//------------------------------------------------------------
// o_valid gen
//------------------------------------------------------------
    always @ (posedge clk or negedge rst_n) begin
	    if(rst_n == 1'b0) begin
		    valid_l[0] <= 0;
        end
	    else if(o_ready)
		    valid_l[0] <= i_valid;
    end
 for(i = 1; i < PIPE_DEPTH; i = i+1) begin
    always @(posedge clk or negedge rst_n) begin
        if(rst_n == 1'b0) begin
            valid_l[i] <= 1'b0;
        end
        else if(ready_l[i-1]) begin
            valid_l[i] <= valid_l[i-1];
        end            
    end
 end

    assign o_valid = valid_l[PIPE_DEPTH-1];

//-----------------------------------------------------------------
// payload gen
//-----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if(rst_n == 1'b0) begin
            payload_l[0] <= {PLD_W{1'b0}};
        end
        else if(o_ready & i_valid) begin
            payload_l[0] <= i_payload;
        end
    end
for( i = 1; i < PIPE_DEPTH-1; i = i+1) begin
    always @(posedge clk or rst_n) begin
        if( rst_n == 1'b0) begin
            payload_l[i] <= {PLD_W{1'b0}};
        end
        else if(ready_l[i-1] & valid_l[i-1]) begin
            payload_l[i] <= payload_l[i-1]
        end
    end
end
    assign o_payload = payload_l[PIPE_DEPTH-1];
end
endgenerate

endmodule

