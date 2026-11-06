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
    localparam IDLE = 2'd0, RECORD = 2'd1, PLAY = 2'd2, PAUSE = 2'd3;
    logic [1:0] state_w, state_r;
    logic [63:0] mem_d_from_ram;
    logic mem_transaction_complete;
    logic mem_ready;
    
<<<<<<< HEAD
    logic [23:0] mem_addr;
    logic [63:0] mem_d_to_ram;
=======
    logic[23:0] mem_addr;
    logic[23:0] end_addr;
    logic[63:0] mem_d_to_ram;
>>>>>>> d0e8209511ea8a7a8e32fa9f27effbbb8ff75038
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
    
<<<<<<< HEAD
    // player logic 
    logic signed [3:0] speed_idx;
    logic [26:0] cur_addr;
    logic [63:0] cur_word;
    logic [63:0] next_word;
    logic [5:0] cnt; 
    
    always @(*) begin
        state_w = state_r;
        case (state_r)
            IDLE: begin
                cur_addr = 27'd0;
                cur_word = 64'd0;
                next_word = 64'd0;
                cnt = 6'd0;
                if (/*recording trigger*/) state_w = RECODD;
                else if (/*playing trigger*/) steet_w = PLAY;
            end
            RECORD: begin
                // TODO
            end 
            PLAY: begin
                if (cnt == 6'd0) begin
                    // read from memory
                    
                end
            end
            PAUSE: begin

            end
            default: state_w = IDLE;
        endcase
    end
=======
    localparam IDLE = 2'd0, RECORD = 2'd1, PLAY = 2'd2, PAUSE = 2'd3;
    logic [1:0] state_w, state_r;
    logic [63:0] shift_r;
    logic [6:0] cnt_r;
    logic record_start, replay_start; // To indicate if recording or replaying is still running
    
>>>>>>> d0e8209511ea8a7a8e32fa9f27effbbb8ff75038
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
            cnt_r <= 7'd0;
            state_r <= IDLE;
        end else begin
            mem_wstrobe <= 0;
            mem_rstrobe <= 0;
            if (mem_transaction_complete) begin // To check if writing to ddr2 or reading from ddr2 is done before moving to another addr
                mem_addr <= mem_addr + 1;
            end
            
            case(state_r)
                IDLE: begin
                    mem_addr <= 24'h0;
                    if (record_btn && !record_start && mem_ready) begin // should check if ddr2 memory is ready before sending data
                        record_start <= 1; // start recording
                        state_r <= RECORD;
                    end else if (replay_btn && !replay_start) begin
                        replay_start <= 1; 
                        state_r <= PLAY;
                    end
                end
                RECORD: begin
                    if (record_btn && record_start) begin
                        record_start <= 0; // stop recording
                        end_addr <= mem_addr;
                        state_r <= IDLE;
                    end
                    shift_r <= {shift_r[62:0], data_in};
                    cnt_r <= cnt_r + 1;
                    if(cnt_r == 7'd64) begin
                        mem_d_to_ram <= shift_r[63:0];
                        mem_wstrobe <= 1'b1;
                        cnt_r <= 7'd1;
                    end else begin
                        mem_wstrobe <= 1'b0;
                    end
                end
                PLAY: begin
                    if (replay_btn && replay_start) begin
                        replay_start <= 0;
                        state_r <= PAUSE;
                    end

                    mem_rstrobe <= 1;
                    
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
