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
	output [255:0] o_m,
	output         o_finished
);

logic         busy_r, busy_w;
logic         finished_r, finished_w;
logic [7:0]   cnt_r, cnt_w;
logic [255:0] b_r, b_w;      // shifted right every cycle, only b_r[0] is used
logic [256:0] ret_r, ret_w;  // stays in [0, 2N) between iterations

logic [257:0] sum_a, sum_n;  // ret + a + N can reach 4N-2, needs 258 bits
logic [257:0] diff;

assign sum_a = ret_r + (b_r[0]   ? i_a : 256'd0);
assign sum_n = sum_a + (sum_a[0] ? i_n : 256'd0);

// final correction: ret in [0, 2N), subtract N once if ret >= N
assign diff       = {1'b0, ret_r} - {2'b00, i_n};
assign o_m        = diff[257] ? ret_r[255:0] : diff[255:0];
assign o_finished = finished_r;

always_comb begin
	busy_w     = busy_r;
	cnt_w      = cnt_r;
	b_w        = b_r;
	ret_w      = ret_r;
	finished_w = 1'b0;
	if (busy_r) begin
		ret_w = sum_n[257:1];
		b_w   = b_r >> 1;
		cnt_w = cnt_r + 8'd1;
		if (cnt_r == 8'd255) begin
			busy_w     = 1'b0;
			finished_w = 1'b1;
		end
	end else if (i_start) begin
		busy_w = 1'b1;
		cnt_w  = 8'd0;
		b_w    = i_b;
		ret_w  = 257'd0;
	end
end

always_ff @(posedge i_clk or posedge i_rst) begin
	if (i_rst) begin
		busy_r     <= 1'b0;
		finished_r <= 1'b0;
		cnt_r      <= 8'd0;
		b_r        <= 256'd0;
		ret_r      <= 257'd0;
	end else begin
		busy_r     <= busy_w;
		finished_r <= finished_w;
		cnt_r      <= cnt_w;
		b_r        <= b_w;
		ret_r      <= ret_w;
	end
end

endmodule
