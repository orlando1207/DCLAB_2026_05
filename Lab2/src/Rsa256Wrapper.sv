module Rsa256Wrapper (
    input           i_clk,
    input           i_rst,
    input           rx,
	output          tx
);

//AXI command
localparam	AXI_IDLE 	        = 2'b00;
localparam	AXI_R		        = 2'b10;
localparam	AXI_W		        = 2'b01;

localparam   RX_BASE             = 0*4;
localparam   TX_BASE             = 1*4;
localparam   STATUS_BASE         = 2*4;
localparam   CTRL_BASE           = 3*4;

localparam   RX_OK_BIT           = 0;
localparam   TX_FULL_BIT         = 3;

// Feel free to design your own FSM!
localparam   S_GET_KEY           = 0; //get N, then get d
localparam   S_GET_DATA          = 1; //get y
localparam   S_WAIT_CALCULATE    = 2;
localparam   S_SEND_DATA         = 3;

/********************************************************
    RSA256Core
**********************************************************/
logic [255:0] n_r, n_w, d_r, d_w, enc_r, enc_w, dec_r, dec_w;
logic rsa_start_r, rsa_start_w;
logic rsa_finished;
logic [255:0] rsa_dec;

Rsa256Core rsa256_core(
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_start(rsa_start_r),
    .i_a(enc_r),
    .i_d(d_r),
    .i_n(n_r),
    .o_a_pow_d(rsa_dec),
    .o_finished(rsa_finished)
);

/********************************************************
    UART
**********************************************************/
//write address
logic[3:0]      s_axi_awaddr  ;  //input 	master write address
logic          	s_axi_awvalid ;  //input 	master write address valid
logic           s_axi_awready ;  //output	slave ready to receive write address
//write data                                
logic[31:0]     s_axi_wdata   ;  //input 	master write data	
logic           s_axi_wvalid  ;  //input 	master write data valid
logic           s_axi_wready  ;  //output	slave ready to receive write data
//write response
logic[1:0]      s_axi_bresp   ;  //output	slave write response
logic         	s_axi_bvalid  ;  //output	slave write response valid
logic        	s_axi_bready  ;  //input 	master ready to receive write response
//read address
logic[3:0]     	s_axi_araddr  ;  //input 	master read address
logic         	s_axi_arvalid ;  //input    master read address valid
logic          	s_axi_arready ;  //output	slave ready to receive read address
//read data
logic[31:0]    	s_axi_rdata   ;  //output	slave read data
logic[1:0]    	s_axi_rresp   ;  //output	slave read response
logic          	s_axi_rvalid  ;  //output	slave read data valid
logic         	s_axi_rready  ;  //input 	master ready to receive read data

axi_uartlite_0 uart 
(
  .s_axi_aclk(i_clk),             // input logic s_axi_aclk
  .s_axi_aresetn(!i_rst),         // input logic s_axi_aresetn
  .s_axi_awaddr(s_axi_awaddr),    // input logic [3 : 0] s_axi_awaddr
  .s_axi_awvalid(s_axi_awvalid),  // input logic s_axi_awvalid
  .s_axi_awready(s_axi_awready),  // output logic s_axi_awready
  .s_axi_wdata(s_axi_wdata),      // input logic [31 : 0] s_axi_wdata
  .s_axi_wstrb(4'b1111),		  // input logic [3 : 0] s_axi_wstrb
  .s_axi_wvalid(s_axi_wvalid),    // input logic s_axi_wvalid
  .s_axi_wready(s_axi_wready),    // output logic s_axi_wready
  .s_axi_bresp(s_axi_bresp),      // output logic [1 : 0] s_axi_bresp
  .s_axi_bvalid(s_axi_bvalid),    // output logic s_axi_bvalid
  .s_axi_bready(s_axi_bready),    // input logic s_axi_bready
  .s_axi_araddr(s_axi_araddr),    // input logic [3 : 0] s_axi_araddr
  .s_axi_arvalid(s_axi_arvalid),  // input logic s_axi_arvalid
  .s_axi_arready(s_axi_arready),  // output logic s_axi_arready
  .s_axi_rdata(s_axi_rdata),      // output logic [31 : 0] s_axi_rdata
  .s_axi_rresp(s_axi_rresp),      // output logic [1 : 0] s_axi_rresp
  .s_axi_rvalid(s_axi_rvalid),    // output logic s_axi_rvalid
  .s_axi_rready(s_axi_rready),    // input logic s_axi_rready
  .rx(rx),                        // input logic rx
  .tx(tx)                         // output logic tx
); 


logic[2:0] axi_cmd_r, axi_cmd_w;
logic[4:0] user_raddr_r, user_raddr_w;
logic[4:0] user_waddr_r, user_waddr_w;
logic[1:0] state_r, state_w;

always_comb begin
    // TODO
end

always_ff @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        n_r <= 0;
        d_r <= 0;
        enc_r <= 0;
        dec_r <= 0;
        state_r <= S_GET_KEY;
        rsa_start_r <= 0;
        user_raddr_r <= 0;
        user_waddr_r <= 0;
        axi_cmd_r <= AXI_IDLE;
    end else begin
        n_r <= n_w;
        d_r <= d_w;
        enc_r <= enc_w;
        dec_r <= dec_w;
        state_r <= state_w;
        rsa_start_r <= rsa_start_w;
        user_raddr_r <= user_raddr_w;
        user_waddr_r <= user_waddr_w;
        axi_cmd_r <= axi_cmd_w;
    end
end

endmodule
