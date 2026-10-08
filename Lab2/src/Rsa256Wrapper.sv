module Rsa256Wrapper (
    input           i_clk,
    input           i_rst,
    input           rx,
	output          tx
);

// Which transaction runs next
localparam   AXI_STATUS          = 1'b0;    // read STATUS register
localparam   AXI_RXTX            = 1'b1;    // read RX (GET) / write TX (SEND)

// UART Lite register addresses (byte addressed, 4 bytes each)
localparam   RX_BASE             = 0*4;
localparam   TX_BASE             = 1*4;
localparam   STATUS_BASE         = 2*4;
localparam   CTRL_BASE           = 3*4;

// STATUS register bits
localparam   RX_OK_BIT           = 0;       // 1 = RX FIFO has data
localparam   TX_FULL_BIT         = 3;       // 1 = TX FIFO is full

// FSM states
localparam   S_GET_N             = 0;       // receive N (32 bytes)
localparam   S_GET_D             = 1;       // receive d (32 bytes)
localparam   S_GET_Y             = 2;       // receive y (32 bytes)
localparam   S_WAIT_CALCULATE    = 3;       // wait for Rsa256Core
localparam   S_SEND_DATA         = 4;       // send result (31 bytes)

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

/********************************************************
    Control FSM
**********************************************************/
logic       axi_cmd_r, axi_cmd_w;                   // AXI_STATUS or AXI_RXTX
logic       axi_raddr_done_r, axi_raddr_done_w;     // ar accepted, waiting for r
logic       axi_waddr_done_r, axi_waddr_done_w;     // aw accepted
logic       axi_wdata_done_r, axi_wdata_done_w;     // w accepted
logic [4:0] user_raddr_r, user_raddr_w;             // bytes received
logic [4:0] user_waddr_r, user_waddr_w;             // bytes sent
logic [2:0] state_r, state_w;

always_comb begin
    // AXI master outputs: idle by default
    s_axi_awaddr  = 0;
    s_axi_awvalid = 0;
    s_axi_wdata   = 0;
    s_axi_wvalid  = 0;
    s_axi_bready  = 0;
    s_axi_araddr  = 0;
    s_axi_arvalid = 0;
    s_axi_rready  = 0;

    // Registers: hold by default
    n_w              = n_r;
    d_w              = d_r;
    enc_w            = enc_r;
    dec_w            = dec_r;
    rsa_start_w      = 0;                           // one-cycle pulse
    axi_cmd_w        = axi_cmd_r;
    axi_raddr_done_w = axi_raddr_done_r;
    axi_waddr_done_w = axi_waddr_done_r;
    axi_wdata_done_w = axi_wdata_done_r;
    user_raddr_w     = user_raddr_r;
    user_waddr_w     = user_waddr_r;
    state_w          = state_r;

    // ---------------- Receive N, d, y ----------------
    // Per byte: read STATUS until RX_OK, then read RX
    if (state_r == S_GET_N || state_r == S_GET_D || state_r == S_GET_Y) begin
        if (!axi_raddr_done_r) begin                // ar phase
            s_axi_arvalid = 1;
            s_axi_araddr  = (axi_cmd_r == AXI_STATUS) ? STATUS_BASE : RX_BASE;
            if (s_axi_arready)
                axi_raddr_done_w = 1;
        end else begin                              // r phase
            s_axi_rready = 1;
            if (s_axi_rvalid) begin
                axi_raddr_done_w = 0;

                if (axi_cmd_r == AXI_STATUS) begin  // STATUS read
                    if (s_axi_rdata[RX_OK_BIT])
                        axi_cmd_w = AXI_RXTX;
                end else begin                      // RX read: store byte (MSB first)
                    axi_cmd_w = AXI_STATUS;
                    case (state_r)
                        S_GET_N: begin
                            n_w = {n_r[247:0], s_axi_rdata[7:0]};
                            if (user_raddr_r == 31) begin   // 32nd byte
                                state_w      = S_GET_D;
                                user_raddr_w = 0;
                            end else user_raddr_w = user_raddr_r + 5'd1;
                        end
                        S_GET_D: begin
                            d_w = {d_r[247:0], s_axi_rdata[7:0]};
                            if (user_raddr_r == 31) begin   // 32nd byte
                                state_w      = S_GET_Y;
                                user_raddr_w = 0;
                            end else user_raddr_w = user_raddr_r + 5'd1;
                        end
                        S_GET_Y: begin
                            enc_w = {enc_r[247:0], s_axi_rdata[7:0]};
                            if (user_raddr_r == 31) begin   // 32nd byte
                                state_w      = S_WAIT_CALCULATE;
                                rsa_start_w  = 1;
                                user_raddr_w = 0;
                            end else user_raddr_w = user_raddr_r + 5'd1;
                        end
                    endcase
                end
            end
        end
    end

    // ---------------- Wait for RSA core ----------------
    else if (state_r == S_WAIT_CALCULATE) begin
        if (rsa_finished) begin
            dec_w   = rsa_dec;
            state_w = S_SEND_DATA;
        end
    end

    // ---------------- Send result ----------------
    // Per byte: read STATUS until TX not full, then write TX
    else if (state_r == S_SEND_DATA) begin
        if (axi_cmd_r == AXI_STATUS) begin          // STATUS read
            if (!axi_raddr_done_r) begin            // ar phase
                s_axi_arvalid = 1;
                s_axi_araddr  = STATUS_BASE;
                if (s_axi_arready)
                    axi_raddr_done_w = 1;
            end else begin                          // r phase
                s_axi_rready = 1;
                if (s_axi_rvalid) begin
                    axi_raddr_done_w = 0;
                    if (!s_axi_rdata[TX_FULL_BIT])
                        axi_cmd_w = AXI_RXTX;
                end
            end
        end else begin                              // TX write
            if (!(axi_waddr_done_r && axi_wdata_done_r)) begin  // aw + w phase
                s_axi_awvalid = !axi_waddr_done_r;
                s_axi_awaddr  = TX_BASE;
                s_axi_wvalid  = !axi_wdata_done_r;
                s_axi_wdata   = dec_r[247:240];     // top byte of 31-byte message
                if (s_axi_awready)
                    axi_waddr_done_w = 1;
                if (s_axi_wready)
                    axi_wdata_done_w = 1;
            end else begin                          // b phase
                s_axi_bready = 1;
                if (s_axi_bvalid) begin             // byte sent
                    axi_cmd_w        = AXI_STATUS;
                    axi_waddr_done_w = 0;
                    axi_wdata_done_w = 0;
                    dec_w            = dec_r << 8;
                    if (user_waddr_r == 30) begin   // 31st byte
                        state_w      = S_GET_Y;     // key stays, wait for next y
                        user_waddr_w = 0;
                    end else user_waddr_w = user_waddr_r + 5'd1;
                end
            end
        end
    end
end

always_ff @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        n_r              <= 0;
        d_r              <= 0;
        enc_r            <= 0;
        dec_r            <= 0;
        state_r          <= S_GET_N;
        rsa_start_r      <= 0;
        user_raddr_r     <= 0;
        user_waddr_r     <= 0;
        axi_cmd_r        <= AXI_STATUS;
        axi_raddr_done_r <= 0;
        axi_waddr_done_r <= 0;
        axi_wdata_done_r <= 0;
    end else begin
        n_r              <= n_w;
        d_r              <= d_w;
        enc_r            <= enc_w;
        dec_r            <= dec_w;
        state_r          <= state_w;
        rsa_start_r      <= rsa_start_w;
        user_raddr_r     <= user_raddr_w;
        user_waddr_r     <= user_waddr_w;
        axi_cmd_r        <= axi_cmd_w;
        axi_raddr_done_r <= axi_raddr_done_w;
        axi_waddr_done_r <= axi_waddr_done_w;
        axi_wdata_done_r <= axi_wdata_done_w;
    end
end

endmodule
