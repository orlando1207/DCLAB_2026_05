// Debounce with a shared sample tick (generated once in NEXYS_A7).
// Input must differ from the debounced value for CNT_N consecutive ticks
// (tick period = 7813 cycles @ 3.125 MHz = 2.5 ms, CNT_N = 4 -> 7.5~10 ms).
module Debounce (
	input  i_in,
	input  i_clk,
	input  i_rst,
	input  i_tick,
	output o_debounced,
	output o_neg,
	output o_pos
);

parameter CNT_N = 4;
localparam CNT_BIT = $clog2(CNT_N);

logic o_debounced_r;
logic [CNT_BIT-1:0] counter_r;
logic neg_r, pos_r;

wire differ = (i_in != o_debounced_r);
wire fire   = i_tick && differ && (counter_r == CNT_N-1);

assign o_debounced = o_debounced_r;
assign o_pos = pos_r;
assign o_neg = neg_r;

always_ff @(posedge i_clk or posedge i_rst) begin
	if (i_rst) begin
		o_debounced_r <= '0;
		counter_r <= '0;
		neg_r <= '0;
		pos_r <= '0;
	end else begin
		if (i_tick) begin
			if (!differ)    counter_r <= '0;
			else if (fire)  counter_r <= '0;
			else            counter_r <= counter_r + 1'b1;
		end
		if (fire) o_debounced_r <= ~o_debounced_r;
		pos_r <= fire & ~o_debounced_r;
		neg_r <= fire &  o_debounced_r;
	end
end

endmodule
