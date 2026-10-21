module Rsa256Core (
	input          i_clk,
	input          i_rst,
	input          i_start,
	input  [255:0] i_a, // cipher text y
	input  [255:0] i_d, // private key; held by Rsa256Wrapper while busy
	input  [255:0] i_n, // modulus; held by Rsa256Wrapper while busy
	output [255:0] o_a_pow_d, // plain text x
	output         o_finished
);

// Area-oriented RSA engine.
//
// Multiplication and squaring are scheduled on one iterative Montgomery
// datapath instead of being calculated by two parallel RsaMont blocks. The
// long arithmetic operations use independent carry chains for timing.
typedef enum logic [3:0] {
	S_IDLE,
	S_PREP,
	S_MONT_START,
	S_MONT_RUN,
	S_MONT_FINAL,
	S_DONE
} state_t;

state_t state_r;

logic [255:0] t_r;          // a*2^256 mod n; repeatedly squared
logic [255:0] result_r;     // accumulated exponentiation result
logic [255:0] op_a_r;       // shifting Montgomery multiplier operand
logic [257:0] mont_r;       // Montgomery partial result
logic [7:0]   prep_count_r;
logic [7:0]   exp_count_r;
logic [7:0]   mont_count_r;
logic         mont_is_square_r;
logic [257:0] mont_addend_r;

logic [258:0] prep_full;
logic [258:0] mont_sum_full;
logic [258:0] mont_sub_full;
logic [256:0] t_plus_n_r;
logic [256:0] t_plus_n_comb;
logic [255:0] prep_next;
logic [255:0] mont_reduced;
logic [257:0] start_addend;
logic         start_next_q;
logic [257:0] start_next_addend;
logic         next_mont_q;
logic [257:0] next_mont_addend;

assign o_a_pow_d = result_r;
assign o_finished = (state_r == S_DONE);

// q is the parity of m + a_i*b. The modulus is odd, so adding n when q=1
// makes the value even before the divide-by-two operation.
// Compute t+n only in S_MONT_START, after t has been registered. The start
// state also executes Montgomery iteration zero, so this register boundary
// fixes timing without increasing the operation's cycle count.
assign t_plus_n_comb = {1'b0, t_r} + {1'b0, i_n};

always_comb begin
	if (!op_a_r[0])
		start_addend = 258'd0;
	else if (t_r[0])
		start_addend = {1'b0, t_plus_n_comb};
	else
		start_addend = {2'b00, t_r};

	start_next_q = start_addend[1] ^ (op_a_r[1] & t_r[0]);
	case ({op_a_r[1], start_next_q})
		2'b00: start_next_addend = 258'd0;
		2'b10: start_next_addend = {2'b00, t_r};
		2'b01: start_next_addend = {2'b00, i_n};
		2'b11: start_next_addend = {1'b0, t_plus_n_comb};
	endcase
end

// Look one bit ahead while the current Montgomery addition is running.  Only
// mont_sum_full[1] is needed, so this logic does not depend on the wide
// carry-out.
// Registering the complete addend keeps its selection mux out of the next
// cycle's 258-bit carry chain.
assign next_mont_q = mont_sum_full[1] ^ (op_a_r[1] & t_r[0]);
always_comb begin
	case ({op_a_r[1], next_mont_q})
		2'b00: next_mont_addend = 258'd0;
		2'b10: next_mont_addend = {2'b00, t_r};
		2'b01: next_mont_addend = {2'b00, i_n};
		2'b11: next_mont_addend = {1'b0, t_plus_n_r};
	endcase
end

// Keep each carry chain independent. Sharing these operations behind a wide
// state-controlled mux made the FSM state itself a critical arithmetic input.
assign prep_full = {2'b00, t_r, 1'b0}
	               + {1'b0, ~{2'b00, i_n}} + 259'd1;
assign mont_sum_full = {1'b0, mont_r} + {1'b0, mont_addend_r};
assign mont_sub_full = {1'b0, mont_r}
	                   + {1'b0, ~{2'b00, i_n}} + 259'd1;

assign prep_next = prep_full[258] ? prep_full[255:0]
                                 : {t_r[254:0], 1'b0};
assign mont_reduced = mont_sub_full[258] ? mont_sub_full[255:0]
                                    : mont_r[255:0];

// Control registers keep the required asynchronous reset behavior.
always_ff @(posedge i_clk or posedge i_rst) begin
	if (i_rst) begin
		state_r          <= S_IDLE;
		prep_count_r     <= 8'd0;
		exp_count_r      <= 8'd0;
		mont_count_r     <= 8'd0;
		mont_is_square_r <= 1'b0;
	end else begin
		case (state_r)
			S_IDLE: begin
				if (i_start) begin
					prep_count_r <= 8'd0;
					exp_count_r  <= 8'd0;
					state_r      <= S_PREP;
				end
			end

			S_PREP: begin
				if (prep_count_r == 8'd255) begin
					mont_is_square_r <= !i_d[0];
					state_r          <= S_MONT_START;
				end else begin
					prep_count_r <= prep_count_r + 8'd1;
				end
			end

			S_MONT_START: begin
				mont_count_r <= 8'd1;
				state_r      <= S_MONT_RUN;
			end

			S_MONT_RUN: begin
				if (mont_count_r == 8'd255) begin
					state_r <= S_MONT_FINAL;
				end else begin
					mont_count_r <= mont_count_r + 8'd1;
				end
			end

			S_MONT_FINAL: begin
				if (mont_is_square_r) begin
					if (exp_count_r == 8'd255) begin
						state_r <= S_DONE;
					end else if (exp_count_r == 8'd254) begin
						exp_count_r <= 8'd255;
						if (i_d[255]) begin
							mont_is_square_r <= 1'b0;
							state_r          <= S_MONT_START;
						end else begin
							state_r <= S_DONE;
						end
					end else begin
						exp_count_r      <= exp_count_r + 8'd1;
						mont_is_square_r <= !i_d[exp_count_r + 8'd1];
						state_r          <= S_MONT_START;
					end
				end else if (exp_count_r == 8'd255) begin
					state_r <= S_DONE;
				end else begin
					mont_is_square_r <= 1'b1;
					state_r          <= S_MONT_START;
				end
			end

			S_DONE: state_r <= S_IDLE;
			default: state_r <= S_IDLE;
		endcase
	end
end

// Wide datapath registers intentionally have no reset. The reset control
// state prevents them from being consumed before i_start initializes them.
always_ff @(posedge i_clk) begin
	case (state_r)
		S_IDLE: begin
			if (i_start) begin
				// i_a is captured immediately; i_d and i_n stay stable in the
				// wrapper for the entire calculation.
				t_r      <= i_a;
				result_r <= 256'd1;
			end
		end

		S_PREP: begin
			t_r <= prep_next;
			if (prep_count_r == 8'd255) begin
				mont_r <= 258'd0;
				op_a_r <= i_d[0] ? result_r : prep_next;
			end
		end

		S_MONT_START: begin
			t_plus_n_r   <= t_plus_n_comb;
			mont_r        <= start_addend >> 1;
			op_a_r        <= op_a_r >> 1;
			mont_addend_r <= start_next_addend;
		end

		S_MONT_RUN: begin
			mont_r <= mont_sum_full[258:1];
			op_a_r <= op_a_r >> 1;
			mont_addend_r <= next_mont_addend;
		end

		S_MONT_FINAL: begin
			if (mont_is_square_r) begin
				t_r <= mont_reduced;
				if (exp_count_r == 8'd254 && i_d[255]) begin
					op_a_r <= result_r;
					mont_r <= 258'd0;
				end else if (exp_count_r < 8'd254) begin
					op_a_r <= i_d[exp_count_r + 8'd1]
					        ? result_r : mont_reduced;
					mont_r <= 258'd0;
				end
			end else begin
				result_r <= mont_reduced;
				if (exp_count_r != 8'd255) begin
					op_a_r <= t_r;
					mont_r <= 258'd0;
				end
			end
		end

		default: begin
			// Hold datapath state.
		end
	endcase
end

endmodule
