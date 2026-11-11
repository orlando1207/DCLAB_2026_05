module Top(
    input clk,
    input locked,
    input rst,
    input data_in,
    output data_out,

    //Record and Replay button
    input record_btn,
    input replay_btn,
    input speed_up_btn, 
    input speed_down_btn,

    // for bonus
    output o_state, 
    output o_forward, 
    output o_step, 

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
    
    localparam IDLE = 3'd0, RECORD = 3'd1, LOAD = 3'd2, PLAY = 3'd3, PAUSE = 3'd4;
    logic [2:0] state_r;
    logic [63:0] shift_r, next_word;
    logic [5:0] cnt_r;
    logic record_start, replay_start; // To indicate if recording or replaying is still running
    logic loaded;
    logic signed[3:0] speed_idx;
    logic forward;
    logic [2:0] step;
    logic [2:0] step_cnt;
    logic [2:0] acc; 
    logic out_bit_r;

    wire [3:0] n = {1'b0, step} + 4'd1;
    wire [6:0]   valid_cnt = 7'd64 - {1'b0, cnt_r}; 
    wire [127:0] stream    = {shift_r, 64'b0} | ({next_word, 64'b0} >> valid_cnt);
    wire [7:0] top8 = stream[127:120];
    wire [7:0] sel  = top8 & (8'hFF << (4'd8 - n)); 
    wire [3:0] k    = {3'b0,sel[0]} + {3'b0,sel[1]} + {3'b0,sel[2]} + {3'b0,sel[3]}
                + {3'b0,sel[4]} + {3'b0,sel[5]} + {3'b0,sel[6]} + {3'b0,sel[7]};
    wire [4:0] sum  = {2'b0, acc} + {1'b0, k};
    wire       out_one = (sum >= {1'b0, n});
    wire [6:0] cnt_sum = {1'b0, cnt_r} + {3'b0, n};
    wire       carry   = (cnt_sum >= 7'd64);    

    wire cur_bit = forward ? out_bit_r : shift_r[63];
    assign data_out = (state_r == PLAY && cur_bit) ? 1'bz : 1'b0;

    // for bonus 
    assign o_state = state_r;
    assign o_forward = forward;
    assign o_step = step;

    always @(*) begin 
        if (speed_idx > 0) begin 
            forward = 1'b1;
            step = speed_idx;
        end else begin 
            forward = 1'b0;
            step = ~speed_idx + 1;
        end 
    end

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
            next_word <= 64'h0;
            cnt_r <= 6'd0;
            loaded <= 1'b0;
            end_addr <= 24'h0;
            state_r <= IDLE;
            step_cnt <= 3'd0;
            acc <= 3'd0; 
            out_bit_r <= 1'b0; 
            speed_idx <= 4'sd0;
        end else begin
            mem_wstrobe <= 0;
            mem_rstrobe <= 0;
            if (mem_transaction_complete) begin // To check if writing to ddr2 or reading from ddr2 is done before moving to another addr
                mem_addr <= mem_addr + 1;
            end
            
            // speed control
            if (speed_up_btn && speed_idx != 4'sd7) begin 
                speed_idx <= speed_idx + 4'sd1;
                acc <= 3'd0;
                step_cnt <= 3'd0;
            end else if (speed_down_btn && speed_idx != -4'sd7) begin 
                speed_idx <= speed_idx - 4'sd1;
                acc <= 3'd0;
                step_cnt <= 3'd0;
            end
            
            case(state_r)
                IDLE: begin
                    /*
                        next state: RECORD or PLAY
                    */
                    mem_addr <= 24'h0;
                    cnt_r <= 6'd0;
                    shift_r <= 64'h0;
                    next_word <= 64'h0;
                    loaded <= 1'b0;
                    step_cnt <= 3'd0;
                    acc <= 3'd0; 
                    out_bit_r <= 1'b0;

                    if (record_btn && !record_start && mem_ready) begin // should check if ddr2 memory is ready before sending data
                        record_start <= 1; // start recording
                        state_r <= RECORD;
                    end else if (replay_btn && !replay_start) begin
                        replay_start <= 1; 
                        mem_addr <= 24'd0;
                        mem_rstrobe <= 1'b1; // start reading from ddr2
                        state_r <= LOAD;
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
                        mem_d_to_ram <= {shift_r[62:0], data_in};
                        mem_wstrobe <= 1'b1;
                        cnt_r <= 6'd0;
                    end else begin
                        mem_wstrobe <= 1'b0;
                    end
                end
                LOAD: begin 
                    if (mem_transaction_complete && mem_addr == 24'd0) begin
                        shift_r <= mem_d_from_ram;
                        mem_addr <= 24'd1;
                        mem_rstrobe <= 1'b1;
                    end else if (mem_transaction_complete && mem_addr == 24'd1) begin
                        next_word <= mem_d_from_ram;
                        mem_addr <= 24'd2;
                        loaded <= 1'b1;
                        state_r <= PLAY;
                    end
                end 
                PLAY: begin
                    /*
                        next state: IDLE or PAUSE
                    */
                    // replay_btn 當 play/pause 開關（需為單 cycle 脈衝）
                    if (replay_btn && replay_start) begin
                        replay_start <= 0;
                        state_r <= PAUSE;
                    end

                    if (record_btn) begin
                        replay_start <= 0;
                        state_r <= IDLE;
                    end

                    if (!loaded && mem_transaction_complete) begin
                        next_word <= mem_d_from_ram;
                        loaded <= 1'b1;
                    end

                    // logic about speeding
                    // normal or slow
                    if (!forward) begin
                        if (step_cnt >= step) begin
                            if (cnt_r == 6'd63) begin
                                if (loaded) begin  
                                    if (mem_addr >= end_addr + 24'd1) begin
                                        replay_start <= 0;
                                        state_r <= IDLE;
                                    end else begin
                                        step_cnt    <= 3'd0;
                                        cnt_r       <= 6'd0;
                                        shift_r     <= next_word;
                                        mem_rstrobe <= 1'b1;       
                                        loaded      <= 1'b0;
                                    end
                                end
                            end else begin
                                step_cnt <= 3'd0;
                                shift_r  <= {shift_r[62:0], 1'b0};
                                cnt_r    <= cnt_r + 6'd1;
                            end
                        end
                        else step_cnt <= step_cnt + 3'd1;
                    end else begin
                        if (carry && !loaded) begin
                            
                        end else begin
                            out_bit_r <= out_one;
                            acc       <= out_one ? (sum - {1'b0, n}) : sum;  

                            if (carry) begin
                                if (mem_addr >= end_addr + 24'd1) begin
                                    replay_start <= 0;
                                    state_r      <= IDLE;
                                end else begin
                                    shift_r     <= next_word << (cnt_sum - 7'd64);   
                                    cnt_r       <= cnt_sum - 7'd64;
                                    mem_rstrobe <= 1'b1;      
                                    loaded      <= 1'b0;
                                end
                            end else begin
                                shift_r <= shift_r << n;
                                cnt_r   <= cnt_sum[5:0];
                            end
                        end
                    end
                end
                PAUSE: begin
                    if (!loaded && mem_transaction_complete) begin
                        next_word <= mem_d_from_ram;
                        loaded    <= 1'b1;
                    end

                    if (record_btn) begin
                        replay_start <= 0;
                        state_r <= IDLE;
                    end

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