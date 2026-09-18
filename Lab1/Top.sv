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

    logic [26:0] timer_r, timer_w;
    logic [26:0] interval_r, interval_w;
    
    logic [4:0] update_count_r, update_count_w;
    logic [3:0] random_out_r, random_out_w;

    localparam logic [26:0] INITIAL_INTERVAL = 27'd1_000_000;
    localparam logic [26:0] INTERVAL_STEP = 27'd1_000_000 ;
    localparam logic [4:0] LAST_UPDATE = 5'd31;
    
    assign feedback = lfsr_r[15] ^ lfsr_r[13] ^ lfsr_r[12] ^ lfsr_r[10];
    assign  o_random_out = random_out_r;

    always_comb begin
        // keep every param
        state_w = state_r;
        lfsr_w =  lfsr_r;
        timer_w = timer_r;
        interval_w = interval_r;
        update_count_w = update_count_r;
        random_out_w = random_out_r;

        if (state_r == S_IDLE) begin
            if (i_start) begin
                state_w = S_RUN;
                timer_w = 27'd0;
                interval_w = INITIAL_INTERVAL;
                update_count_w = 3'd0;
            end
        end
        else if (state_r == S_RUN) begin
            if (i_start) begin
                state_w = S_DONE;
            end
            
            lfsr_w = {lfsr_r[14:0], feedback};
            
            if (timer_r >= interval_r) begin
                timer_w = 27'd0;
                random_out_w = lfsr_r[3:0];
                if (update_count_r >= LAST_UPDATE) state_w = S_DONE;
                else begin
                    update_count_w += 3'd1;
                    interval_w += INTERVAL_STEP;
                end                
            end
            else timer_w += 27'd1;
        end
        else if (state_r == S_DONE) begin
            if (i_start) begin
                state_w = S_RUN;
                timer_w = 27'd0;
                update_count_w = 3'd0;
                interval_w = INITIAL_INTERVAL;
            end
        end

        else state_w = S_IDLE;
    end

    always_ff @(posedge i_clk or posedge i_rst) begin 
        if (i_rst) begin
            state_r        <= S_IDLE;
            lfsr_r         <= 16'h1ACE;
            timer_r        <= 27'd0;
            interval_r     <= INITIAL_INTERVAL;
            update_count_r <= 3'd0;
            random_out_r   <= 4'd0;
        end
        else begin
            state_r        <= state_w;
            lfsr_r         <= lfsr_w;
            timer_r        <= timer_w;
            interval_r     <= interval_w;
            update_count_r <= update_count_w;
            random_out_r   <= random_out_w;
        end
    end
endmodule
