module Top (
    input  logic       i_clk,
    input  logic       i_rst,
    input  logic       i_start,
    output logic [3:0] o_random_out
);
    typedef enum logic [1:0] {
        S_IDLE,
        S_RUN,
        S_DONE
    } state_t;

    // Define parameters
    state_t state_r, state_w;
    
    logic [15:0] lfsr_r, lfsr_w;
    logic feedback;  // 1-bit

    // no 27 bit addition
    logic [19:0] base_timer_r, base_timer_w;
    // count how many 1M cycle
    logic [4:0]  step_count_r, step_count_w;

    // logic [26:0] timer_r, timer_w;
    // logic [26:0] interval_r, interval_w;
    
    logic [4:0] update_count_r, update_count_w;
    logic [3:0] random_out_r, random_out_w;

    localparam logic [19:0] ONE_SECOND_CYCLES = 20'd999_999;
    // localparam logic [26:0] INITIAL_INTERVAL = 27'd1_000_000;
    // localparam logic [26:0] INTERVAL_STEP = 27'd1_000_000 ;
    localparam logic [4:0] LAST_UPDATE = 5'd31;
    
    assign feedback = lfsr_r[15] ^ lfsr_r[13] ^ lfsr_r[12] ^ lfsr_r[10];
    assign  o_random_out = random_out_r;

    always_comb begin
        // keep every param
        state_w = state_r;
        lfsr_w =  lfsr_r;
        // timer_w = timer_r;
        // interval_w = interval_r;
        base_timer_w = base_timer_r; 
        step_count_w = step_count_r;
        update_count_w = update_count_r;
        random_out_w = random_out_r;

        case (state_r)
            S_IDLE: begin
                if (i_start) begin
                    state_w        = S_RUN;
                    base_timer_w   = 20'd0;
                    step_count_w   = 5'd0;
                    update_count_w = 5'd0;
                end
            end

            S_RUN: begin
                if (i_start) begin
                    state_w = S_DONE;
                end

                lfsr_w = {lfsr_r[14:0], feedback};

                // 每 1,000,000 個時脈觸發一次 base_timer 歸零
                if (base_timer_r == ONE_SECOND_CYCLES) begin
                    base_timer_w = 20'd0;

                    // 檢查累積的 1M 次數是否達到當前目標 (update_count_r)
                    if (step_count_r == update_count_r) begin
                        step_count_w = 5'd0;             // 重置 step 計數
                        random_out_w = lfsr_r[3:0];      // 更新隨機輸出

                        if (update_count_r >= LAST_UPDATE) begin
                            state_w = S_DONE;
                        end else begin
                            update_count_w = update_count_r + 5'd1;
                        end
                    end else begin
                        step_count_w = step_count_r + 5'd1; // 還沒到指定間隔，累積 1M 週期數
                    end
                end else begin
                    base_timer_w = base_timer_r + 20'd1;
                end
            end

            S_DONE: begin
                if (i_start) begin
                    state_w        = S_RUN;
                    base_timer_w   = 20'd0;
                    step_count_w   = 5'd0;
                    update_count_w = 5'd0;
                end
            end

            default: state_w = S_IDLE;
        endcase
    end

    always_ff @(posedge i_clk or posedge i_rst) begin 
        if (i_rst) begin
            state_r        <= S_IDLE;
            lfsr_r         <= 16'h1ACE;
            base_timer_r <= 20'd0;
            step_count_r <= 5'd0;
            // timer_r        <= 27'd0;
            // interval_r     <= INITIAL_INTERVAL;
            update_count_r <= 5'd0;
            random_out_r   <= 4'd0;
        end
        else begin
            state_r        <= state_w;
            lfsr_r         <= lfsr_w;
            base_timer_r <= base_timer_w;
            step_count_r <= step_count_w;
            // timer_r        <= timer_w;
            // interval_r     <= interval_w;
            update_count_r <= update_count_w;
            random_out_r   <= random_out_w;
        end
    end
endmodule
