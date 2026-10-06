module Rsa256Core (
	input          i_clk,
	input          i_rst,
	input          i_start,
	input  [255:0] i_a, // cipher text y
	input  [255:0] i_d, // private key
	input  [255:0] i_n,
	output [255:0] o_a_pow_d, // plain text x
	output         o_finished
);

// operations for RSA256 decryption
// namely, the Montgomery algorithm

endmodule

module RsaMont (
	input          i_clk,
	input          i_rst,
	input          i_start,
	input  [255:0] i_n,
	input  [255:0] i_a,
	input  [255:0] i_b,
	output logic [255:0] o_m,
	output logic   o_finished
);

typedef enum logic [1:0] {
	S_IDLE,  
	S_RUN, 
	S_SUB, 
	S_DONE
} state_t;

state_t state_r, state_w;

logic [255:0] a_r, a_w;
logic [255:0] b_r, b_w;
logic [255:0] n_r, n_w;

logic [257:0] m_r, m_w;
logic [7:0] count_r, count_w;

logic [257:0] b_ext, n_ext; 

localparam logic [7:0] MAX_ITER = 8'd255;
assign b_ext = {2'b00, b_r};
assign n_ext = {2'b00, n_r};

always_comb begin
	// keep every value
	a_w = a_r;
	b_w = b_r;
	n_w = n_r;

	m_w = m_r;
	count_w = count_r;
	state_w = state_r;

	o_finished = 1'b0;
	o_m = m_r[255:0];

	case (state_r)
		S_IDLE: begin
			if (i_start) begin
				a_w  = i_a;
				b_w  = i_b;
				n_w  = i_n;
				state_w = S_RUN;
				count_w = 8'd0;
				m_w = 258'd0;
			end
		end
		S_RUN: begin	
			if (a_r[count_r]) begin
				m_w = m_w + b_ext;
			end
			if (m_w[0]) begin
				m_w = m_w + n_ext;
			end
			m_w = m_w >> 1;

			if (count_r == MAX_ITER) begin
				state_w = S_SUB;				
			end else begin
				count_w = count_w + 8'd1;
			end
		end
		S_SUB: begin
			m_w = (m_w >= n_ext) ? (m_w - n_ext) : (m_w);
			state_w = S_DONE;
		end
		S_DONE: begin 
			o_finished = 1;
			state_w = S_IDLE;
		end
		default: begin
			state_w = S_IDLE;
		end
	endcase
end

always_ff @(posedge i_clk or posedge i_rst) begin
	if (i_rst) begin
		// reset logic
		a_r <= 256'd0;
		b_r <= 256'd0;
		n_r <= 256'd0
		m_r <= 258'd0;
		count_r <= 8'd0;
		state_r <= S_IDLE;
	end
	else begin
		a_r = a_w;
		b_r = b_w;
		n_r = n_w;
		m_r <= m_w;
		count_r <= count_w;
		state_r <= state_w;
	end
end
endmodule
