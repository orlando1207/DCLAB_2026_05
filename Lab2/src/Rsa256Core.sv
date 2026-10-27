module Rsa256Core (
	input         i_clk,
	input         i_rst,
	input         i_start,
	// Host port into the working RAM, used only while the core is idle.
	// Address = {region, word}; word 0 is the least-significant word.
	//   region 0: a (write before i_start; overwritten during the calculation)
	//   region 1: a^d mod n (read after o_finished)
	//   region 2: n
	//   region 3: d
	input         i_host_we,
	input  [4:0]  i_host_addr,
	input  [31:0] i_host_wdata,
	output [31:0] o_host_rdata,
	output        o_finished
);

// Area-first RSA engine. All 256-bit arithmetic is performed a 32-bit word
// at a time, and every 256-bit value lives in one distributed RAM. Words are
// addressed instead of rotated through shift registers.
typedef enum logic [2:0] {
	S_IDLE,
	S_LOAD,      // write 1 into R
	S_SUB_CHECK, // borrow of x-n; x = 2t (prep) or m (reduce)
	S_SUB_WRITE, // write x or x-n back to T or R
	S_MONT_INIT, // fetch multiplier bit 0
	S_MONT_WORD, // one Montgomery iteration: words 0..8, then a flush word
	S_DONE
} state_t;

// RAM map, 64 words x 32 bits:
//   T = t words 0-7       at {1'b0, REG_T, word} (a is loaded here)
//   R = result words 0-7  at {1'b0, REG_R, word}
//   N = n words 0-7       at {1'b0, REG_N, word}
//   D = d words 0-7       at {1'b0, REG_D, word}
//   M = accumulator 0-8   at {2'b10, word}
localparam logic [1:0] REG_T = 2'd0;
localparam logic [1:0] REG_R = 2'd1;
localparam logic [1:0] REG_N = 2'd2;
localparam logic [1:0] REG_D = 2'd3;

state_t state_r;

(* ram_style = "distributed" *) logic [31:0] ram [0:63];
logic [5:0]  ram_addr_a; // t word, a_i/d bit fetch, or host read
logic [5:0]  ram_addr_b; // M port
logic [5:0]  ram_addr_c; // N port
logic [5:0]  ram_addr_w;
logic [31:0] ram_rd_a;
logic [31:0] ram_rd_b;
logic [31:0] ram_rd_c;
logic [31:0] ram_wd;
logic        ram_we;

logic [7:0] bit_count_r; // prep step or Montgomery iteration
logic [7:0] exp_count_r;
logic [3:0] word_count_r;
logic       mont_is_square_r;
logic       sub_is_prep_r;
logic       d_bit_r;     // d[exp_count_r+1], fetched ahead of its use

logic        sub_borrow_r;
logic        sub_final_borrow_r;
logic        prep_shift_carry_r;
logic [1:0]  mont_carry_r;
logic [30:0] mont_upper_r;
logic        mont_ai_r;
logic        mont_q_r;

logic        host_access;
logic [31:0] n_word;
logic [7:0]  ai_index;
logic        ai_fetch;
logic [7:0]  d_index;
logic        d_fetch;

logic [31:0] sub_x;
logic [32:0] sub_ext;
logic [31:0] sub_write_word;

logic [31:0] mont_m_word;
logic        mont_q;
logic [1:0]  mont_carry_in;
logic [33:0] mont_total;

assign o_host_rdata = ram_rd_a;
assign o_finished = (state_r == S_DONE);

assign host_access = (state_r == S_IDLE) || (state_r == S_DONE);

// The multiplier bit a_i is read from RAM: bit 0 in S_MONT_INIT, bit i+1 in
// the flush word of iteration i. bit_count_r is 255 in S_MONT_INIT, so
// bit_count_r+1 wraps to 0 there.
assign ai_index = bit_count_r + 8'd1;
assign ai_fetch = (state_r == S_MONT_INIT)
	|| (state_r == S_MONT_WORD && word_count_r == 4'd9);

// The exponent bit for the next decision is read while port A is otherwise
// idle: d[0] in S_LOAD (exp_count_r is 255, so +1 wraps to 0), and
// d[exp_count_r+1] in the first word of each final reduction.
assign d_index = exp_count_r + 8'd1;
assign d_fetch = (state_r == S_LOAD && word_count_r == 4'd0)
	|| (state_r == S_SUB_CHECK && !sub_is_prep_r && word_count_r == 4'd0);

always_comb begin
	if (ai_fetch)
		ram_addr_a = {1'b0, mont_is_square_r ? REG_T : REG_R, ai_index[7:5]};
	else if (d_fetch)
		ram_addr_a = {1'b0, REG_D, d_index[7:5]};
	else if (host_access)
		ram_addr_a = {1'b0, i_host_addr};
	else
		ram_addr_a = {1'b0, REG_T, word_count_r[2:0]};
end
assign ram_addr_b = {2'b10, word_count_r};
assign ram_addr_c = {1'b0, REG_N, word_count_r[2:0]};
assign n_word = word_count_r[3] ? 32'd0 : ram_rd_c;

always_comb begin
	ram_we     = 1'b0;
	ram_addr_w = {2'b10, word_count_r - 4'd1};
	ram_wd     = {mont_total[0], mont_upper_r};
	case (state_r)
		S_IDLE, S_DONE: begin
			ram_we     = i_host_we;
			ram_addr_w = {1'b0, i_host_addr};
			ram_wd     = i_host_wdata;
		end
		S_LOAD: begin
			ram_we     = 1'b1;
			ram_addr_w = {1'b0, REG_R, word_count_r[2:0]};
			ram_wd     = {31'd0, word_count_r == 4'd0};
		end
		S_SUB_WRITE: begin
			ram_we     = 1'b1;
			ram_addr_w = {1'b0,
			              (sub_is_prep_r || mont_is_square_r) ? REG_T : REG_R,
			              word_count_r[2:0]};
			ram_wd     = sub_write_word;
		end
		S_MONT_WORD: begin
			// Word w of m/2 is complete one cycle after word w is read.
			ram_we = (word_count_r != 4'd0);
		end
		default: begin
		end
	endcase
end

always_ff @(posedge i_clk) begin
	if (ram_we)
		ram[ram_addr_w] <= ram_wd;
end
assign ram_rd_a = ram[ram_addr_a];
assign ram_rd_b = ram[ram_addr_b];
assign ram_rd_c = ram[ram_addr_c];

// Conditional subtraction shared by preparation (t = 2t mod n) and the final
// Montgomery correction (m mod n). The first pass only finds the final
// borrow; the second pass recomputes x-n and writes x or x-n.
always_comb begin
	if (!sub_is_prep_r)
		sub_x = ram_rd_b;
	else if (word_count_r == 4'd8)
		sub_x = {31'd0, prep_shift_carry_r};
	else
		sub_x = {ram_rd_a[30:0], prep_shift_carry_r};
end
assign sub_ext = {1'b0, sub_x} - {1'b0, n_word} - sub_borrow_r;
assign sub_write_word = sub_final_borrow_r ? sub_x : sub_ext[31:0];

// One radix-2 Montgomery iteration is evaluated least-significant word first.
// M is treated as zero in the first iteration, so it never needs clearing.
// Word 9 adds only the carry and flushes the top word of m/2.
assign mont_m_word = (bit_count_r == 8'd0 || word_count_r == 4'd9)
	? 32'd0 : ram_rd_b;
assign mont_q = (word_count_r == 4'd0)
	? mont_m_word[0] ^ (mont_ai_r & ram_rd_a[0]) : mont_q_r;
assign mont_carry_in = (word_count_r == 4'd0) ? 2'd0 : mont_carry_r;
assign mont_total = {2'b00, mont_m_word}
	                + {2'b00, ((mont_ai_r && word_count_r < 4'd8)
	                            ? ram_rd_a : 32'd0)}
	                + {2'b00, (mont_q ? n_word : 32'd0)}
	                + {{32{1'b0}}, mont_carry_in};

// Small control registers retain the required asynchronous reset behavior.
always_ff @(posedge i_clk or posedge i_rst) begin
	if (i_rst) begin
		state_r          <= S_IDLE;
		bit_count_r      <= 8'd0;
		exp_count_r      <= 8'd0;
		word_count_r     <= 4'd0;
		mont_is_square_r <= 1'b0;
		sub_is_prep_r    <= 1'b0;
	end else begin
		case (state_r)
			S_IDLE: begin
				if (i_start) begin
					bit_count_r   <= 8'd0;
					exp_count_r   <= 8'd255;
					word_count_r  <= 4'd0;
					sub_is_prep_r <= 1'b1;
					state_r       <= S_LOAD;
				end
			end

			S_LOAD: begin
				if (word_count_r == 4'd7) begin
					word_count_r <= 4'd0;
					state_r      <= S_SUB_CHECK;
				end else begin
					word_count_r <= word_count_r + 4'd1;
				end
			end

			S_SUB_CHECK: begin
				if (word_count_r == 4'd8) begin
					word_count_r <= 4'd0;
					state_r      <= S_SUB_WRITE;
				end else begin
					word_count_r <= word_count_r + 4'd1;
				end
			end

			S_SUB_WRITE: begin
				if (word_count_r == 4'd7) begin
					word_count_r <= 4'd0;
					if (sub_is_prep_r) begin
						if (bit_count_r == 8'd255) begin
							sub_is_prep_r    <= 1'b0;
							exp_count_r      <= 8'd0;
							mont_is_square_r <= !d_bit_r;
							state_r          <= S_MONT_INIT;
						end else begin
							bit_count_r <= bit_count_r + 8'd1;
							state_r     <= S_SUB_CHECK;
						end
					end else if (mont_is_square_r) begin
						if (exp_count_r == 8'd254) begin
							exp_count_r <= 8'd255;
							if (d_bit_r) begin
								mont_is_square_r <= 1'b0;
								state_r          <= S_MONT_INIT;
							end else begin
								state_r <= S_DONE;
							end
						end else begin
							exp_count_r      <= exp_count_r + 8'd1;
							mont_is_square_r <= !d_bit_r;
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

			S_MONT_INIT: begin
				bit_count_r <= bit_count_r + 8'd1; // 255 wraps to 0
				state_r     <= S_MONT_WORD;
			end

			S_MONT_WORD: begin
				if (word_count_r == 4'd9) begin
					word_count_r <= 4'd0;
					if (bit_count_r == 8'd255)
						state_r <= S_SUB_CHECK;
					else
						bit_count_r <= bit_count_r + 8'd1;
				end else begin
					word_count_r <= word_count_r + 4'd1;
				end
			end

			S_DONE: state_r <= S_IDLE;
			default: state_r <= S_IDLE;
		endcase
	end
end

// Datapath registers intentionally have no reset. The control state
// initializes every value before it is consumed.
always_ff @(posedge i_clk) begin
	if (d_fetch)
		d_bit_r <= ram_rd_a[d_index[4:0]];

	case (state_r)
		S_IDLE: begin
			if (i_start) begin
				sub_borrow_r       <= 1'b0;
				prep_shift_carry_r <= 1'b0;
			end
		end

		S_SUB_CHECK: begin
			sub_borrow_r       <= sub_ext[32];
			prep_shift_carry_r <= ram_rd_a[31];
			if (word_count_r == 4'd8) begin
				sub_final_borrow_r <= sub_ext[32];
				sub_borrow_r       <= 1'b0;
				prep_shift_carry_r <= 1'b0;
			end
		end

		S_SUB_WRITE: begin
			sub_borrow_r       <= sub_ext[32];
			prep_shift_carry_r <= ram_rd_a[31];
			if (word_count_r == 4'd7) begin
				sub_borrow_r       <= 1'b0;
				prep_shift_carry_r <= 1'b0;
			end
		end

		S_MONT_INIT: mont_ai_r <= ram_rd_a[ai_index[4:0]];

		S_MONT_WORD: begin
			mont_carry_r <= mont_total[33:32];
			mont_upper_r <= mont_total[31:1];
			if (word_count_r == 4'd0)
				mont_q_r <= mont_q;
			if (word_count_r == 4'd9)
				mont_ai_r <= ram_rd_a[ai_index[4:0]];
		end

		default: begin
			// Hold datapath state.
		end
	endcase
end

endmodule
