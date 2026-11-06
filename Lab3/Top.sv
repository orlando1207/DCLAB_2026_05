module Top(
    input clk,
    input locked,
    input rst,
    input data_in,
    output data_out,

    //Record and Replay button
    input record_btn,
    input replay_btn,

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
    logic[23:0] end_addr;
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
    logic record_start, replay_start; // To indicate if recording or replaying is still running
    logic loaded;

    assign data_out = (state_r == PLAY && shift_r[63]) ? 1'bz : 1'b0; 

    //sequential block
    always@(posedge clk or posedge rst)begin
	    if((!locked)||rst) begin
            // ddr2 interface param
            mem_addr <= 24'h0;
            mem_d_to_ram <= 64'h0;
            mem_wstrobe <= 0;
            mem_rstrobe <= 0;

            record_start <= 0;
            replay_start <= 0;
            shift_r <= 64'h0;
            cnt_r <= 6'd0;
            loaded <= 1'b0;
            end_addr <= 24'h0;
            state_r <= IDLE;
        end else begin
            mem_wstrobe <= 0;
            mem_rstrobe <= 0;
            if (mem_transaction_complete) begin // To check if writing to ddr2 or reading from ddr2 is done before moving to another addr
                mem_addr <= mem_addr + 1;
            end
            
            case(state_r)
                IDLE: begin
                    /*
                        next state: RECORD or PLAY
                    */
                    mem_addr <= 24'h0;
                    cnt_r <= 6'd0;
                    shift_r <= 64'h0;
                    loaded <= 1'b0;
                    if (record_btn && !record_start && mem_ready) begin // should check if ddr2 memory is ready before sending data
                        record_start <= 1; // start recording
                        state_r <= RECORD;
                    end else if (replay_btn && !replay_start) begin
                        replay_start <= 1; 
                        mem_rstrobe <= 1'b1; // start reading from ddr2
                        state_r <= PLAY;
                    end
                end
                RECORD: begin
                    /*
                        next state: IDLE
                    */
                    if (record_btn && record_start) begin
                        record_start <= 0; // stop recording
                        mem_wstrobe <= 0; // stop writing to ddr2
                        end_addr <= mem_addr;
                        state_r <= IDLE;
                    end
                    shift_r <= {shift_r[62:0], data_in};
                    cnt_r <= cnt_r + 1;
                    if(cnt_r == 6'd63) begin
                        mem_d_to_ram <= shift_r[63:0];
                        mem_wstrobe <= 1'b1;
                        cnt_r <= 6'd0;
                    end else begin
                        mem_wstrobe <= 1'b0;
                    end
                end
                PLAY: begin
                    /*
                        next state: IDLE or PAUSE
                    */
                    
                    if (replay_btn && replay_start) begin
                        replay_start <= 0;
                        state_r <= PAUSE;
                    end

                    if(!loaded) begin 
                        if(mem_transaction_complete) begin
                            shift_r <= mem_d_from_ram;
                            mem_rstrobe <= 1'b1;
                            loaded <= 1'b1;
                            cnt_r <= 6'd0;
                        end
                    end else begin
                        if (mem_addr == end_addr + 1) begin
                            cnt_r <= 6'd0;
                            if (mem_addr == end_addr) begin
                                replay_start <= 0;
                                state_r <= IDLE;
                            end else begin
                                shift_r <= mem_d_from_ram;
                                mem_rstrobe <= 1'b1;
                            end
                        end else begin
                            mem_rstrobe <= 1'b0;
                            // output data_out
                            shift_r <= {shift_r[62:0], 1'b0};
                            cnt_r <= cnt_r + 1;
                        end
                    end
                end
                PAUSE: begin
                    if (replay_btn && !replay_start) begin
                        replay_start <= 1; 
                        state_r <= PLAY;
                    end
                end
                default: begin
                    state_r <= IDLE;
                end
            endcase
            
        end
    end
    
endmodule
