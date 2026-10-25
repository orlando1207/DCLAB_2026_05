module Rsa256Core (
	input          i_clk,
	input          i_rst,
	input          i_start,
	input  [255:0] i_a,
	input  [255:0] i_d,
	input  [255:0] i_n,
	output [255:0] o_a_pow_d,
	output         o_finished
);

// Area-first RSA engine. All 256-bit arithmetic is performed a 32-bit word
// at a time. The wrapper holds i_d and i_n stable while the core is busy.
typedef enum logic [3:0] {
	S_IDLE,
	S_PREP_SUB,
	S_PREP_WRITE,
	S_MONT_INIT,
	S_MONT_WORD,
	S_MONT_FLUSH,
	S_REDUCE_CHECK,
	S_REDUCE_WRITE,
	S_DONE
} state_t;

state_t state_r;

logic [255:0] t_r;
logic [255:0] result_r;
logic [287:0] mont_r;

logic [7:0] prep_count_r;
logic [7:0] mont_count_r;
logic [7:0] exp_count_r;
logic [3:0] word_count_r;
logic       mont_is_square_r;

logic        prep_borrow_r;
logic        prep_final_borrow_r;
logic        prep_shift_carry_r;
logic        reduce_borrow_r;
logic        reduce_final_borrow_r;
logic [1:0]  mont_carry_r;
logic [30:0] mont_upper_r;
logic        mont_ai_r;
logic        mont_q_r;

logic [31:0] n_word;
logic [31:0] t_word;
logic [31:0] prep_raw_word;
logic [32:0] prep_sub_ext;
logic [31:0] prep_write_word;

logic        mont_next_source_bit;
logic        mont_q_first;
logic        mont_q;
logic [1:0]  mont_carry_in;
logic [33:0] mont_total;
logic [31:0] mont_insert_word;

logic [32:0] reduce_sub_ext;
logic [31:0] reduce_write_word;

assign o_a_pow_d = result_r;
assign o_finished = (state_r == S_DONE);

// Eight-to-one word selection is smaller than another rotating 256-bit copy
// of the modulus.
always_comb begin
	case (word_count_r)
		4'd0: n_word = i_n[ 31:  0];
		4'd1: n_word = i_n[ 63: 32];
		4'd2: n_word = i_n[ 95: 64];
		4'd3: n_word = i_n[127: 96];
		4'd4: n_word = i_n[159:128];
		4'd5: n_word = i_n[191:160];
		4'd6: n_word = i_n[223:192];
		4'd7: n_word = i_n[255:224];
		default: n_word = 32'd0;
	endcase
end

assign t_word = t_r[31:0];

// Preparation computes (2*t)-n into mont_r. A second pass selects the
// subtraction or unreduced 2*t after the final borrow is known.
assign prep_raw_word = (word_count_r == 4'd8)
	? {31'd0, prep_shift_carry_r}
	: {t_word[30:0], prep_shift_carry_r};
assign prep_sub_ext = {1'b0, prep_raw_word}
	                    - {1'b0, n_word} - prep_borrow_r;
assign prep_write_word = prep_final_borrow_r
	? {t_word[30:0], prep_shift_carry_r}
	: mont_r[31:0];

// The next multiplier bit is prefetched during S_MONT_FLUSH. This keeps the
// 256-to-1 indexed selection out of the following 32-bit adder path.
assign mont_next_source_bit = mont_is_square_r
	? t_r[mont_count_r + 8'd1] : result_r[mont_count_r + 8'd1];
assign mont_q_first = mont_r[0] ^ (mont_ai_r & t_r[0]);
assign mont_q = (word_count_r == 4'd0) ? mont_q_first : mont_q_r;
assign mont_carry_in = (word_count_r == 4'd0) ? 2'd0 : mont_carry_r;

// One radix-2 Montgomery iteration is evaluated least-significant word first.
// Division by two is assembled across adjacent words.
assign mont_total = {2'b00, mont_r[31:0]}
	                + {2'b00, ((mont_ai_r && word_count_r < 4'd8)
	                            ? t_word : 32'd0)}
	                + {2'b00, (mont_q  ? n_word : 32'd0)}
	                + {{32{1'b0}}, mont_carry_in};
assign mont_insert_word = (word_count_r == 4'd0)
	? 32'd0 : {mont_total[0], mont_upper_r};

// Final correction first finds whether m<n, then writes either m or m-n to
// the selected destination one word per cycle.
assign reduce_sub_ext = {1'b0, mont_r[31:0]}
	                   - {1'b0, n_word} - reduce_borrow_r;
assign reduce_write_word = reduce_final_borrow_r
	? mont_r[31:0] : reduce_sub_ext[31:0];

// Small control registers retain the required asynchronous reset behavior.
always_ff @(posedge i_clk or posedge i_rst) begin
	if (i_rst) begin
		state_r          <= S_IDLE;
		prep_count_r     <= 8'd0;
		mont_count_r     <= 8'd0;
		exp_count_r      <= 8'd0;
		word_count_r     <= 4'd0;
		mont_is_square_r <= 1'b0;
	end else begin
		case (state_r)
			S_IDLE: begin
				if (i_start) begin
					prep_count_r <= 8'd0;
					exp_count_r  <= 8'd0;
					word_count_r <= 4'd0;
					state_r      <= S_PREP_SUB;
				end
			end

			S_PREP_SUB: begin
				if (word_count_r == 4'd8) begin
					word_count_r <= 4'd0;
					state_r      <= S_PREP_WRITE;
				end else begin
					word_count_r <= word_count_r + 4'd1;
				end
			end

			S_PREP_WRITE: begin
				if (word_count_r == 4'd7) begin
					word_count_r <= 4'd0;
					if (prep_count_r == 8'd255) begin
						mont_is_square_r <= !i_d[0];
						state_r          <= S_MONT_INIT;
					end else begin
						prep_count_r <= prep_count_r + 8'd1;
						state_r      <= S_PREP_SUB;
					end
				end else begin
					word_count_r <= word_count_r + 4'd1;
				end
			end

			S_MONT_INIT: begin
				mont_count_r <= 8'd0;
				word_count_r <= 4'd0;
				state_r      <= S_MONT_WORD;
			end

			S_MONT_WORD: begin
				if (word_count_r == 4'd8) begin
					word_count_r <= 4'd0;
					state_r      <= S_MONT_FLUSH;
				end else begin
					word_count_r <= word_count_r + 4'd1;
				end
			end

			S_MONT_FLUSH: begin
				word_count_r <= 4'd0;
				if (mont_count_r == 8'd255) begin
					state_r <= S_REDUCE_CHECK;
				end else begin
					mont_count_r <= mont_count_r + 8'd1;
					state_r      <= S_MONT_WORD;
				end
			end

			S_REDUCE_CHECK: begin
				if (word_count_r == 4'd8) begin
					word_count_r <= 4'd0;
					state_r      <= S_REDUCE_WRITE;
				end else begin
					word_count_r <= word_count_r + 4'd1;
				end
			end

			S_REDUCE_WRITE: begin
				if (word_count_r == 4'd7) begin
					word_count_r <= 4'd0;
					if (mont_is_square_r) begin
						if (exp_count_r == 8'd254) begin
							exp_count_r <= 8'd255;
							if (i_d[255]) begin
								mont_is_square_r <= 1'b0;
								state_r          <= S_MONT_INIT;
							end else begin
								state_r <= S_DONE;
							end
						end else begin
							exp_count_r      <= exp_count_r + 8'd1;
							mont_is_square_r <= !i_d[exp_count_r + 8'd1];
							state_r          <= S_MONT_INIT;
						end
					end else if (exp_count_r == 8'd255) begin
						state_r <= S_DONE;
					end else begin
						mont_is_square_r <= 1'b1;
						state_r          <= S_MONT_INIT;
					end
				end else begin
					word_count_r <= word_count_r + 4'd1;
				end
			end

			S_DONE: state_r <= S_IDLE;
			default: state_r <= S_IDLE;
		endcase
	end
end

// Wide datapath registers intentionally have no reset. The control state
// initializes every value before it is consumed.
always_ff @(posedge i_clk) begin
	case (state_r)
		S_IDLE: begin
			if (i_start) begin
				t_r                   <= i_a;
				result_r              <= 256'd1;
				mont_r                <= 288'd0;
				prep_borrow_r         <= 1'b0;
				prep_final_borrow_r   <= 1'b0;
				prep_shift_carry_r    <= 1'b0;
				reduce_borrow_r       <= 1'b0;
				reduce_final_borrow_r <= 1'b0;
				mont_carry_r          <= 2'd0;
				mont_upper_r          <= 31'd0;
				mont_ai_r             <= 1'b0;
				mont_q_r              <= 1'b0;
			end
		end

		S_PREP_SUB: begin
			mont_r        <= {prep_sub_ext[31:0], mont_r[287:32]};
			prep_borrow_r <= prep_sub_ext[32];
			if (word_count_r < 4'd8) begin
				t_r                <= {t_word, t_r[255:32]};
				prep_shift_carry_r <= t_word[31];
			end else begin
				prep_final_borrow_r <= prep_sub_ext[32];
				prep_shift_carry_r  <= 1'b0;
			end
		end

		S_PREP_WRITE: begin
			t_r                <= {prep_write_word, t_r[255:32]};
			mont_r             <= {32'd0, mont_r[287:32]};
			prep_shift_carry_r <= t_word[31];
			if (word_count_r == 4'd7) begin
				mont_r             <= 288'd0;
				prep_borrow_r      <= 1'b0;
				prep_shift_carry_r <= 1'b0;
			end
		end

		S_MONT_INIT: begin
			mont_r        <= 288'd0;
			mont_carry_r <= 2'd0;
			mont_upper_r <= 31'd0;
			mont_ai_r    <= mont_is_square_r ? t_r[0] : result_r[0];
		end

		S_MONT_WORD: begin
			mont_r        <= {mont_insert_word, mont_r[287:32]};
			mont_carry_r <= mont_total[33:32];
			mont_upper_r <= mont_total[31:1];
			if (word_count_r == 4'd0) begin
				mont_q_r  <= mont_q_first;
			end
			if (word_count_r < 4'd8)
				t_r <= {t_word, t_r[255:32]};
		end

		S_MONT_FLUSH: begin
			mont_r <= {{mont_carry_r[0], mont_upper_r}, mont_r[287:32]};
			if (mont_count_r != 8'd255)
				mont_ai_r <= mont_next_source_bit;
		end

		S_REDUCE_CHECK: begin
			mont_r          <= {mont_r[31:0], mont_r[287:32]};
			reduce_borrow_r <= reduce_sub_ext[32];
			if (word_count_r == 4'd8) begin
				reduce_final_borrow_r <= reduce_sub_ext[32];
				reduce_borrow_r       <= 1'b0;
			end
		end

		S_REDUCE_WRITE: begin
			mont_r          <= {32'd0, mont_r[287:32]};
			reduce_borrow_r <= reduce_sub_ext[32];
			if (mont_is_square_r)
				t_r <= {reduce_write_word, t_r[255:32]};
			else
				result_r <= {reduce_write_word, result_r[255:32]};
		end

		default: begin
			// Hold datapath state.
		end
	endcase
end

endmodule
