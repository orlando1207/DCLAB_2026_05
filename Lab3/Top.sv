module Top(
    input clk,
    input locked,
    input rst,
    input data_in,
    input start,
    output data_out,

    //RAM Interface
    inout[15:0] ddr2_dq,
    inout[1:0] ddr2_dqs_n,
    inout[1:0] ddr2_dqs_p,
    output[12:0] ddr2_addr,
    output[2:0] ddr2_ba,
    output ddr2_ras_n,
    output ddr2_cas_n,
    output ddr2_we_n,
    output ddr2_ck_p,
    output ddr2_ck_n,
    output ddr2_cke,
    output ddr2_cs_n,
    output[1:0] ddr2_dm,
    output ddr2_odt,
    input clk_mem
    );
    
    logic[63:0] mem_d_from_ram;
    logic mem_transaction_complete;
    logic mem_ready;
    
    logic[23:0] mem_addr;
    logic[63:0] mem_d_to_ram;
    logic mem_wstrobe, mem_rstrobe;

    ddr2_interface ddr2_interface0(
        .clk_mem(clk_mem),
        .rst_n(!rst),

        .ddr2_addr(ddr2_addr),
        .ddr2_ba(ddr2_ba),
        .ddr2_cas_n(ddr2_cas_n),
        .ddr2_ck_n(ddr2_ck_n),
        .ddr2_ck_p(ddr2_ck_p),
        .ddr2_cke(ddr2_cke),
        .ddr2_ras_n(ddr2_ras_n),
        .ddr2_we_n(ddr2_we_n),
        .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n),
        .ddr2_dqs_p(ddr2_dqs_p),
        .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm),
        .ddr2_odt(ddr2_odt),

        .cpu_clk(clk),
        .addr(mem_addr),
        .data_in(mem_d_to_ram),
        .data_out(mem_d_from_ram),
        .rstrobe(mem_rstrobe),
        .wstrobe(mem_wstrobe),
        .transaction_complete(mem_transaction_complete),
        .ready(mem_ready)
        );
    
    localparam IDLE = 2'd0, RECORD = 2'd1, PLAY = 2'd2, PAUSE = 2'd3;
    logic [1:0] state_w, state_r;
    logic [63:0] shift_r;
    logic [6:0] cnt_r;
    
    //sequential block
    always@(posedge clk or posedge rst)begin
	    if((!locked)||rst)begin
            shift_r <= 64'h0;
            cnt_r <= 7'd0;
            state_r <= IDLE;
        end else begin
            case(state_r)
                IDLE: begin
//todo begin        
                    mem_addr <= 24'h0;
                    if(start)begin
                        state_r <= RECORD;
                    end
                    
                end
                RECORD: begin
                    shift_r <= {shift_r[62:0], data_in};
                    cnt_r <= cnt_r + 1;
                    if(cnt_r == 7'd64)begin
                        mem_d_to_ram <= shift_r[63:0];
                        mem_addr <= mem_addr + 1;
                        mem_wstrobe <= 1'b1;
                        cnt_r <= 7'd0;
                    end else begin
                        mem_wstrobe <= 1'b0;
                    end
//todo stop change state
                end
                default: begin
                    state_r <= STATE_IDLE;
                end
            endcase
            
        end
    end
    
endmodule
