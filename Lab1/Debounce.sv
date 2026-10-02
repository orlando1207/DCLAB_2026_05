module Debounce (
	input  i_in,
	input  i_clk,
	input  i_rst,
	output o_debounced,
	output o_neg,
	output o_pos
);

parameter CNT_N = 1_000_000; // 7;
localparam CNT_BIT = 20;

localparam logic [CNT_BIT-1:0] CNT_LAST = (CNT_N == 7) ? 20'h0007F : 20'h875EA;

logic o_debounced_r, o_debounced_w;
logic [CNT_BIT-1:0] counter_r = '0;   // 初值 0 = 種子（上電值，模擬也不會是 X）
logic [CNT_BIT-1:0] counter_w;
logic neg_r, neg_w, pos_r, pos_w;

assign o_debounced = o_debounced_r;
assign o_pos = pos_r;
assign o_neg = neg_r;

always_comb begin
	// LFSR 走一步
	counter_w = {counter_r[CNT_BIT-2:0], ~(counter_r[19] ^ counter_r[16])};

	if (counter_r == CNT_LAST) begin
		o_debounced_w = ~o_debounced_r;
	end else begin
		o_debounced_w = o_debounced_r;
	end
	pos_w = ~o_debounced_r &  o_debounced_w; // detect i_in posedge
	neg_w =  o_debounced_r & ~o_debounced_w; // detect i_in negedge
end

always_ff @(posedge i_clk or posedge i_rst) begin
	if (i_rst) begin
		o_debounced_r <= '0;
		neg_r <= '0;
		pos_r <= '0;
	end else begin
		o_debounced_r <= o_debounced_w;
		neg_r <= neg_w;
		pos_r <= pos_w;
	end
end

// counter 不用 async reset：輸入與輸出相同時同步歸零（接 SR 腳，不佔 LUT）
always_ff @(posedge i_clk) begin
	if (i_in == o_debounced_r) counter_r <= '0;
	else                       counter_r <= counter_w;
end

endmodule