`timescale 1ns/100ps

module tb;
	localparam CLK = 10;
	localparam HCLK = CLK/2;
	localparam W = 16;      // Rsa256Core word width
	localparam NW = 256/W;  // words per 256-bit value
	localparam WB = $clog2(NW);

	// Rsa256Core host port regions
	localparam logic [1:0] REG_A = 2'd0;
	localparam logic [1:0] REG_RESULT = 2'd1;
	localparam logic [1:0] REG_N = 2'd2;
	localparam logic [1:0] REG_D = 2'd3;

	logic clk, start_cal, fin, rst;
	initial clk = 0;
	always #HCLK clk = ~clk;
	logic [255:0] encrypted_data, decrypted_data;
	logic [247:0] golden;
	integer fp_e, fp_d;

	logic          host_we;
	logic [WB+1:0] host_addr;
	logic [W-1:0]  host_wdata, host_rdata;

	Rsa256Core #(.W(W)) core(
		.i_clk(clk),
		.i_rst(rst),
		.i_start(start_cal),
		.i_host_we(host_we),
		.i_host_addr(host_addr),
		.i_host_wdata(host_wdata),
		.o_host_rdata(host_rdata),
		.o_finished(fin)
	);

	// The core keeps every 256-bit value in RAM; move them one word at a time.
	task automatic write_value(input logic [1:0] region, input logic [255:0] value);
		for (int w = 0; w < NW; w++) begin
			host_we    <= 1'b1;
			host_addr  <= {region, w[WB-1:0]};
			host_wdata <= value[W*w +: W];
			@(posedge clk);
		end
		host_we <= 1'b0;
	endtask

	task automatic read_value(input logic [1:0] region, output logic [255:0] value);
		for (int w = 0; w < NW; w++) begin
			host_addr <= {region, w[WB-1:0]};
			@(posedge clk);
			value[W*w +: W] = host_rdata;
		end
	endtask

	initial begin
		$fsdbDumpfile("lab2.fsdb");
		$fsdbDumpvars;
		fp_e = $fopen("../pc_python/golden/enc1.bin", "rb");
		fp_d = $fopen("../pc_python/golden/dec1.txt", "rb");
		start_cal = 0;
		host_we = 0;
		host_addr = 0;
		host_wdata = 0;
		rst = 1;
		#(2*CLK)
		rst = 0;
		@(posedge clk);
		write_value(REG_N, 256'hCA3586E7EA485F3B0A222A4C79F7DD12E85388ECCDEE4035940D774C029CF831);
		write_value(REG_D, 256'hB6ACE0B14720169839B15FD13326CF1A1829BEAFC37BB937BEC8802FBCF46BD9);
		for (int i = 0; i < 5; i++) begin
			for (int j = 0; j < 10; j++) begin
				@(posedge clk);
			end
			$fread(encrypted_data, fp_e);
			$fread(golden, fp_d);
			$display("=========");
			$display("enc  %2d = %64x", i, encrypted_data);
			$display("=========");
			write_value(REG_A, encrypted_data);
			start_cal <= 1;
			@(posedge clk)
			start_cal <= 0;
			@(posedge fin)
			read_value(REG_RESULT, decrypted_data);
			$display("=========");
			$display("dec  %2d = %64x", i, decrypted_data);
			$display("gold %2d = %64x", i, golden);
			$display("=========");
		end
		$finish;
	end

	initial begin
		#(12000000*CLK)
		$display("Too slow, abort.");
		$finish;
	end

endmodule
