module Top (
    input  logic       i_clk,
    input  logic       i_rst,
    input  logic       i_start,
    output logic [3:0] o_random_out
);
    typedef enum logic {
        S_WAIT, 
        S_RUN
    } state_t;
    state_t state_r, state_w;

    // Define parameters
    logic [15:0] lfsr_r, lfsr_w;
    logic feedback; // 1 bit 

    logic [20:0] base_timer_r, base_timer_w;
    logic [5:0]  step_count_r, step_count_w;
    wire is_fire = ((step_count_r & (step_count_r + 6'd1)) == 6'd0);
    logic [3:0] random_out_r, random_out_w;

    localparam logic [20:0] TIMER_SEED = 21'h00001;
    localparam logic [20:0] TIMER_LAST = 21'h0F87BE;

    logic tick;
    
    assign feedback = lfsr_r[15] ^ lfsr_r[13] ^ lfsr_r[12] ^ lfsr_r[10];
    assign tick = (base_timer_r == TIMER_LAST);
    assign  o_random_out = random_out_r;

    always_comb begin
        // keep every param
        state_w = state_r;
        lfsr_w =  lfsr_r;
        base_timer_w = base_timer_r; 
        step_count_w = step_count_r;
        random_out_w = random_out_r;

        case (state_r)
            S_WAIT: begin
                if (i_start) begin
                    state_w        = S_RUN;
                    base_timer_w   = TIMER_SEED;
                    step_count_w   = 6'd1;
                end
            end

            S_RUN: begin
                lfsr_w = {lfsr_r[14:0], feedback};

                if (tick) begin
                    base_timer_w = TIMER_SEED;
                    if (is_fire) begin
                        random_out_w = lfsr_r[3:0];    
                        if (&step_count_r) state_w = S_WAIT; 
                    end 
                    step_count_w = step_count_r + 6'd1;
                end else begin
                    base_timer_w = {base_timer_r[19:0], base_timer_r[20] ^ base_timer_r[18]};
                end
            end

            default: state_w = S_WAIT;
        endcase
    end

    always_ff @(posedge i_clk or posedge i_rst) begin 
        if (i_rst) begin
            state_r        <= S_WAIT;
            lfsr_r         <= 16'h1ACE;
            base_timer_r <= TIMER_SEED;
            step_count_r <= 6'd0;
            random_out_r   <= 4'd0;
        end
        else begin
            state_r        <= state_w;
            lfsr_r         <= lfsr_w;
            base_timer_r <= base_timer_w;
            step_count_r <= step_count_w;
            random_out_r   <= random_out_w;
        end
    end
endmodule
