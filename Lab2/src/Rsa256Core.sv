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

// y*2^256 mod n
module RsaPrep (
	input          i_clk,
	input          i_rst,
	input          i_start,
	input  [255:0] i_n,
	// input  [255:0] i_a,
	input  [255:0] i_b,	
	output [255:0] o_result,
	output         o_finished
);

logic         busy_r, busy_w, finished_r, finished_w;
logic [7:0]   cnt_r, cnt_w;
logic [256:0] diff, tmp;
logic [255:0] t_w, t_r;

assign o_result = t_r;
assign o_finished = finished_r;
assign tmp = {t_r, 1'b0};
assign diff = tmp - {1'b0, i_n};

always_comb begin
	cnt_w = cnt_r;
	t_w = t_r;
	busy_w = busy_r;
	finished_w = 1'b0;
	if (busy_r) begin
		t_w = diff[256] ? tmp[255:0] : diff[255:0];
		cnt_w = cnt_r + 8'd1;
		if (cnt_r == 8'd255) begin
			busy_w     = 1'b0;
			finished_w = 1'b1;
		end
	end else if (i_start) begin
		busy_w = 1'b1;
		cnt_w  = 8'd0;
		t_w    = i_b;
	end
end

always_ff @(posedge i_clk or posedge i_rst) begin
	if (i_rst) begin
		finished_r <= 1'b0;
		busy_r     <= 1'b0;
		cnt_r      <= 8'd0;
		t_r		   <= 256'd0;
	end else begin
		finished_r <= finished_w;
		busy_r     <= busy_w;
		cnt_r      <= cnt_w;
		t_r		   <= t_w;
	end
end

endmodule

// Montgomery multiplication: (a*b*2^(-256)) mod n
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
