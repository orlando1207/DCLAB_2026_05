module Rsa256Core #(
	parameter int W = 16 // datapath word width: 16 or 32
) (
	input                       i_clk,
	input                       i_rst,
	input                       i_start,
	// Host port into the working RAMs, used only while the core is idle.
	// Address = {region, word}; word 0 is the least-significant word.
	//   region 0: a (write before i_start; overwritten during the calculation)
	//   region 1: a^d mod n (read after o_finished)
	//   region 2: n (write only)
	//   region 3: d (write only)
	input                       i_host_we,
	input  [$clog2(256/W)+1:0]  i_host_addr,
	input  [W-1:0]              i_host_wdata,
	output [W-1:0]              o_host_rdata,
	output                      o_finished
);

// Area-first RSA engine. All 256-bit arithmetic is performed one W-bit word
// at a time, and every 256-bit value lives in distributed RAM. Words are
// addressed instead of rotated through shift registers.
localparam int NW = 256 / W;        // words per 256-bit value
localparam int WB = $clog2(NW);     // word index bits
localparam int BB = $clog2(W);      // bit-in-word index bits
localparam int CW = $clog2(NW + 2); // word counter bits, counts 0..NW+1

typedef enum logic [2:0] {
	S_IDLE,
	S_LOAD,      // write 1 into R
	S_SUB_CHECK, // borrow of x-n; x = 2t (prep) or m (reduce)
	S_SUB_WRITE, // write x or x-n back to T or R
	S_MONT_INIT, // fetch multiplier bit 0
	S_MONT_WORD, // one Montgomery iteration: words 0..NW, then a flush word
	S_DONE
} state_t;

// Three RAMs, each with a single read port:
//   TR RAM:  T = t at {1'b0, word} (a is loaded here), R = result at {1'b1, word}
//   M RAM:   Montgomery accumulator words 0..NW
//   key RAM: N = n at {1'b0, word}, D = d at {1'b1, word}
state_t state_r;

(* ram_style = "distributed" *) logic [W-1:0] tr_ram  [0:2*NW-1];
(* ram_style = "distributed" *) logic [W-1:0] m_ram   [0:NW];
(* ram_style = "distributed" *) logic [W-1:0] key_ram [0:2*NW-1];
logic [WB:0]   tr_raddr;   // t word, a_i fetch, or host read
logic [WB:0]   tr_waddr;
logic [W-1:0]  tr_rd;
logic [W-1:0]  tr_wd;
logic          tr_we;
logic [W-1:0]  m_rd;
logic          m_we;
logic [WB:0]   key_raddr;  // n word or d bit fetch
logic [W-1:0]  key_rd;
logic          key_we;

logic [7:0]    bit_count_r; // prep step or Montgomery iteration
logic [7:0]    exp_count_r;
logic [CW-1:0] word_count_r;
logic          mont_is_square_r;
logic          sub_is_prep_r;
logic          d_bit_r;     // d[exp_count_r+1], fetched ahead of its use

logic          sub_borrow_r;
logic          sub_final_borrow_r;
logic          prep_shift_carry_r;
logic [1:0]    mont_carry_r;
logic [W-2:0]  mont_upper_r;
logic          mont_ai_r;
logic          mont_q_r;

logic          host_access;
logic [W-1:0]  n_word;
logic [7:0]    ai_index;
logic          ai_fetch;
logic [7:0]    d_index;
logic          d_fetch;

logic [W-1:0]  sub_x;
logic [W:0]    sub_ext;
logic [W-1:0]  sub_write_word;

logic [W-1:0]  mont_m_word;
logic          mont_q;
logic [1:0]    mont_carry_in;
logic [W+1:0]  mont_total;

assign o_host_rdata = tr_rd;
assign o_finished = (state_r == S_DONE);

assign host_access = (state_r == S_IDLE) || (state_r == S_DONE);

// The multiplier bit a_i is read from RAM: bit 0 in S_MONT_INIT, bit i+1 in
// the flush word of iteration i. bit_count_r is 255 in S_MONT_INIT, so
// bit_count_r+1 wraps to 0 there.
assign ai_index = bit_count_r + 8'd1;
assign ai_fetch = (state_r == S_MONT_INIT)
	|| (state_r == S_MONT_WORD && word_count_r == NW + 1);

// The exponent bit for the next decision is read while n is not needed:
// d[0] in S_LOAD (exp_count_r is 255, so +1 wraps to 0), and d[exp_count_r+1]
// in S_MONT_INIT, before the operation that ends with the decision.
assign d_index = exp_count_r + 8'd1;
assign d_fetch = (state_r == S_LOAD && word_count_r == 0)
	|| (state_r == S_MONT_INIT);

always_comb begin
	if (ai_fetch)
		tr_raddr = {!mont_is_square_r, ai_index[7:BB]};
	else if (host_access)
		tr_raddr = i_host_addr[WB:0];
	else
		tr_raddr = {1'b0, word_count_r[WB-1:0]};
end
assign key_raddr = d_fetch ? {1'b1, d_index[7:BB]}
                           : {1'b0, word_count_r[WB-1:0]};
assign n_word = (word_count_r >= NW) ? '0 : key_rd;

always_comb begin
	tr_we    = 1'b0;
	tr_waddr = i_host_addr[WB:0];
	tr_wd    = i_host_wdata;
	case (state_r)
		S_IDLE, S_DONE: begin
			tr_we = i_host_we && !i_host_addr[WB+1];
		end
		S_LOAD: begin
			tr_we    = 1'b1;
			tr_waddr = {1'b1, word_count_r[WB-1:0]};
			tr_wd    = {{(W-1){1'b0}}, word_count_r == 0};
		end
		S_SUB_WRITE: begin
			tr_we    = 1'b1;
			tr_waddr = {!(sub_is_prep_r || mont_is_square_r),
			            word_count_r[WB-1:0]};
			tr_wd    = sub_write_word;
		end
		default: begin
		end
	endcase
end

// Word w of m/2 is complete one cycle after word w is read.
assign m_we = (state_r == S_MONT_WORD) && (word_count_r != 0);
assign key_we = host_access && i_host_we && i_host_addr[WB+1];

always_ff @(posedge i_clk) begin
	if (tr_we)
		tr_ram[tr_waddr] <= tr_wd;
	if (m_we)
		m_ram[word_count_r - 1'b1] <= {mont_total[0], mont_upper_r};
	if (key_we)
		key_ram[i_host_addr[WB:0]] <= i_host_wdata;
end
assign tr_rd  = tr_ram[tr_raddr];
assign m_rd   = m_ram[word_count_r];
assign key_rd = key_ram[key_raddr];

// Conditional subtraction shared by preparation (t = 2t mod n) and the final
// Montgomery correction (m mod n). The first pass only finds the final
// borrow; the second pass recomputes x-n and writes x or x-n.
always_comb begin
	if (!sub_is_prep_r)
		sub_x = m_rd;
	else if (word_count_r == NW)
		sub_x = {{(W-1){1'b0}}, prep_shift_carry_r};
	else
		sub_x = {tr_rd[W-2:0], prep_shift_carry_r};
end
assign sub_ext = {1'b0, sub_x} - {1'b0, n_word} - sub_borrow_r;
assign sub_write_word = sub_final_borrow_r ? sub_x : sub_ext[W-1:0];

// One radix-2 Montgomery iteration is evaluated least-significant word first.
// M is treated as zero in the first iteration, so it never needs clearing.
// Word NW+1 adds only the carry and flushes the top word of m/2.
assign mont_m_word = (bit_count_r == 8'd0 || word_count_r == NW + 1)
	? '0 : m_rd;
assign mont_q = (word_count_r == 0)
	? mont_m_word[0] ^ (mont_ai_r & tr_rd[0]) : mont_q_r;
assign mont_carry_in = (word_count_r == 0) ? 2'd0 : mont_carry_r;
assign mont_total = {2'b00, mont_m_word}
	                + {2'b00, ((mont_ai_r && word_count_r < NW) ? tr_rd : {W{1'b0}})}
	                + {2'b00, (mont_q ? n_word : {W{1'b0}})}
	                + {{W{1'b0}}, mont_carry_in};

// Small control registers retain the required asynchronous reset behavior.
always_ff @(posedge i_clk or posedge i_rst) begin
	if (i_rst) begin
		state_r          <= S_IDLE;
		bit_count_r      <= 8'd0;
		exp_count_r      <= 8'd0;
		word_count_r     <= '0;
		mont_is_square_r <= 1'b0;
		sub_is_prep_r    <= 1'b0;
	end else begin
		case (state_r)
			S_IDLE: begin
				if (i_start) begin
					bit_count_r   <= 8'd0;
					exp_count_r   <= 8'd255;
					word_count_r  <= '0;
					sub_is_prep_r <= 1'b1;
					state_r       <= S_LOAD;
				end
			end

			S_LOAD: begin
				if (word_count_r == NW - 1) begin
					word_count_r <= '0;
					state_r      <= S_SUB_CHECK;
				end else begin
					word_count_r <= word_count_r + 1'b1;
				end
			end

			S_SUB_CHECK: begin
				if (word_count_r == NW) begin
					word_count_r <= '0;
					state_r      <= S_SUB_WRITE;
				end else begin
					word_count_r <= word_count_r + 1'b1;
				end
			end

			S_SUB_WRITE: begin
				if (word_count_r == NW - 1) begin
					word_count_r <= '0;
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
					word_count_r <= word_count_r + 1'b1;
				end
			end

			S_MONT_INIT: begin
				bit_count_r <= bit_count_r + 8'd1; // 255 wraps to 0
				state_r     <= S_MONT_WORD;
			end

			S_MONT_WORD: begin
				if (word_count_r == NW + 1) begin
					word_count_r <= '0;
					if (bit_count_r == 8'd255)
						state_r <= S_SUB_CHECK;
					else
						bit_count_r <= bit_count_r + 8'd1;
				end else begin
					word_count_r <= word_count_r + 1'b1;
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
		d_bit_r <= key_rd[d_index[BB-1:0]];

	case (state_r)
		S_IDLE: begin
			if (i_start) begin
				sub_borrow_r       <= 1'b0;
				prep_shift_carry_r <= 1'b0;
			end
		end

		S_SUB_CHECK: begin
			sub_borrow_r       <= sub_ext[W];
			prep_shift_carry_r <= tr_rd[W-1];
			if (word_count_r == NW) begin
				sub_final_borrow_r <= sub_ext[W];
				sub_borrow_r       <= 1'b0;
				prep_shift_carry_r <= 1'b0;
			end
		end

		S_SUB_WRITE: begin
			sub_borrow_r       <= sub_ext[W];
			prep_shift_carry_r <= tr_rd[W-1];
			if (word_count_r == NW - 1) begin
				sub_borrow_r       <= 1'b0;
				prep_shift_carry_r <= 1'b0;
			end
		end

		S_MONT_INIT: mont_ai_r <= tr_rd[ai_index[BB-1:0]];

		S_MONT_WORD: begin
			mont_carry_r <= mont_total[W+1:W];
			mont_upper_r <= mont_total[W-1:1];
			if (word_count_r == 0)
				mont_q_r <= mont_q;
			if (word_count_r == NW + 1)
				mont_ai_r <= tr_rd[ai_index[BB-1:0]];
		end

		default: begin
			// Hold datapath state.
		end
	endcase
end

endmodule
