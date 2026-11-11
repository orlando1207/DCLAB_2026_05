//The MIG is configured to operate with a 2:1 PHY-to-controller clock ratio,
//which reduces the clock frequency required by the user logic. Although the
//user interface transfers 64 bits per cycle in this mode, each DDR memory
//transaction still spans 128 bits. As a result, every read or write operation
//must be completed over two consecutive ui_clk cycles.
//
//To keep the external interface simple, this module still exposes a 128-bit
//data port. Since this example only uses the lower 64 bits, the upper half
//is ignored during reads and masked during writes.
//
//Compared with the 4:1 configuration, the 2:1 mode provides a faster ui_clk,
//which helps reduce the latency when transferring requests between the CPU
//clock domain and the MIG user interface.
module ddr2_interface(
    input clk_mem,
    input rst_n,

    inout[15:0] ddr2_dq,
    inout[1:0] ddr2_dqs_n,
    inout[1:0] ddr2_dqs_p,
    output[12:0] ddr2_addr,
    output[2:0] ddr2_ba,
    output ddr2_ras_n,
    output ddr2_cas_n,
    output ddr2_we_n,
    output[0:0] ddr2_ck_p,
    output[0:0] ddr2_ck_n,
    output[0:0] ddr2_cke,
    output[0:0] ddr2_cs_n,
    output[1:0] ddr2_dm,
    output[0:0] ddr2_odt,

    input cpu_clk,
    input[23:0] addr,
    input[63:0] data_in,
    output [63:0] data_out,
    input rstrobe,
    input wstrobe,
    output transaction_complete,
    output ready
    );

    logic ui_clk, ui_clk_sync_rst;

    logic[2:0] mem_cmd;
    logic mem_en;
    logic mem_rdy;
    wire mem_rd_data_end, mem_rd_data_valid;
    wire [63:0] mem_rd_data;
    logic mem_wdf_end;
    logic mem_wdf_wren;
    logic[7:0] mem_wdf_mask;
    logic mem_wdf_rdy;
    logic complete_r;

    mig_7series_0 mig1 (
        .ddr2_addr(ddr2_addr),
        .ddr2_ba(ddr2_ba),
        .ddr2_cas_n(ddr2_cas_n),
        .ddr2_ck_n(ddr2_ck_n),
        .ddr2_ck_p(ddr2_ck_p),
        .ddr2_cke(ddr2_cke),
        .ddr2_ras_n(ddr2_ras_n),
        .ddr2_we_n(ddr2_we_n),
        .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n),
        .ddr2_dqs_p(ddr2_dqs_p),
        .init_calib_complete(),

        .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm),
        .ddr2_odt(ddr2_odt),

        .app_addr({addr,3'b0}),

        .app_cmd(mem_cmd),
        .app_en(mem_en),
        .app_wdf_data(data_in),
        .app_wdf_end(mem_wdf_end),
        .app_wdf_wren(mem_wdf_wren),
        .app_rd_data(mem_rd_data),
        .app_rd_data_end(mem_rd_data_end),
        .app_rd_data_valid(mem_rd_data_valid),
        .app_rdy(mem_rdy),
        .app_wdf_rdy(mem_wdf_rdy),
        .app_sr_req(1'b0),
        .app_ref_req(1'b0),
        .app_zq_req(1'b0),
        .app_sr_active(),
        .app_ref_ack(),
        .app_zq_ack(),
        .ui_clk(ui_clk),
        .ui_clk_sync_rst(ui_clk_sync_rst),
        .app_wdf_mask(mem_wdf_mask),

        .sys_clk_i(clk_mem),
        .sys_rst(rst_n)
        );

    //Addresses and data remain stable from the initial strobe till the end of
    //the transaction. It is only necessary to synchronize the strobes.
    logic rstrobe_sync, wstrobe_sync;

    flag_sync rs_sync(
        .a_rst_n(rst_n),
        .a_clk(cpu_clk),
        .a_flag(rstrobe),
        .b_rst_n(~ui_clk_sync_rst),
        .b_clk(ui_clk),
        .b_flag(rstrobe_sync)
        );

    flag_sync ws_sync(
        .a_rst_n(rst_n),
        .a_clk(cpu_clk),
        .a_flag(wstrobe),
        .b_rst_n(~ui_clk_sync_rst),
        .b_clk(ui_clk),
        .b_flag(wstrobe_sync)
        );

    flag_sync complete_sync(
        .a_rst_n(~ui_clk_sync_rst),
        .a_clk(ui_clk),
        .a_flag(complete_r),
        .b_rst_n(rst_n),
        .b_clk(cpu_clk),
        .b_flag(transaction_complete)
        );

    ff_sync ready_sync(
        .clk(cpu_clk),
        .rst_p(~rst_n),
        .in_async(~ui_clk_sync_rst),
        .out(ready)
        );

    localparam STATE_IDLE = 3'h0;
    localparam STATE_PREREAD = 3'h1;
    localparam STATE_READ = 3'h2;
    localparam STATE_WRITE = 3'h4;
    localparam STATE_WRITEDATA_H = 3'h5;
    localparam STATE_WRITEDATA_L = 3'h6;

    //parameters for mem_cmd
    localparam CMD_READ = 3'h1;
    localparam CMD_WRITE = 3'h0;


    // TODO
    logic [63:0] rd_data_r;
    logic [2:0] state_r;
    assign data_out = rd_data_r;

    always @(posedge ui_clk) begin
        if(ui_clk_sync_rst) begin
            complete_r <= 1'b0;
            state_r <= STATE_IDLE;
            rd_data_r <= 64'h0;
            mem_en <= 0;
            mem_cmd <= CMD_READ;
            mem_wdf_mask <= 8'hff;
            mem_wdf_wren <= 0;
            mem_wdf_end <=  0;
        end else begin
            complete_r <= 1'b0;
            if (mem_rd_data_valid && !mem_rd_data_end) begin
                rd_data_r <= mem_rd_data;
            end
            case (state_r)
                STATE_IDLE: begin
                    if(mem_wdf_rdy) begin
                        mem_wdf_wren <= 1'b0;
                        mem_wdf_end  <= 1'b0;
                    end
                    if (wstrobe_sync) begin
                        mem_wdf_wren <= 1'b0;
                        mem_wdf_end  <= 1'b0;
                        state_r <= STATE_WRITE;
                        mem_en <= 1'b1;
                        mem_cmd <= CMD_WRITE;
                    end
                    else if (rstrobe_sync) begin
                        state_r <= STATE_PREREAD;
                        mem_en <= 1'b1;
                        mem_cmd <= CMD_READ;
                    end
                end
                STATE_WRITE: begin
                    if (mem_rdy) begin
                        state_r <= STATE_WRITEDATA_H;
                        mem_en  <= 1'b0;
                    end
                end
                STATE_WRITEDATA_H: begin
                    if (mem_wdf_rdy) begin
                        mem_wdf_mask <= 8'h00;
                        mem_wdf_wren <= 1'b1;
                        state_r <= STATE_WRITEDATA_L;
                    end
                end
                STATE_WRITEDATA_L: begin
                    if (mem_wdf_rdy) begin
                        mem_wdf_mask <= 8'hff;
                        mem_wdf_wren <= 1'b1;
                        mem_wdf_end <= 1'b1;
                        state_r <= STATE_IDLE;
                        complete_r <= 1'b1;
                    end
                end
                STATE_PREREAD: begin
                    if (mem_rdy) begin
                        mem_en <= 1'b0;
                        state_r <= STATE_READ;
                    end
                    if (mem_rd_data_valid && mem_rd_data_end) begin
                        complete_r <= 1'b1;
                        state_r <= STATE_IDLE;
                    end
                end
                STATE_READ: begin
                    if (mem_rd_data_valid && mem_rd_data_end) begin
                        state_r <= STATE_IDLE;
                        complete_r <= 1'b1;
                    end
                end
                default: 
                    state_r <= STATE_IDLE;
            endcase
            
        end
    end
endmodule

module ff_sync #(parameter WIDTH=1)(
    input clk,
    input rst_p,
    input[WIDTH-1:0] in_async,
    output reg[WIDTH-1:0] out);
    
    (* ASYNC_REG = "TRUE" *) reg[WIDTH-1:0] sync_reg;
    always @(posedge clk, posedge rst_p) begin
        if(rst_p) begin
            sync_reg <= 0;
            out <= 0;
        end else begin
            {out, sync_reg} <= {sync_reg, in_async};
        end
    end
    
endmodule

module flag_sync(
    input a_rst_n,
    input a_clk,
    input a_flag,
    input b_rst_n,
    input b_clk,
    output b_flag
    );

    reg flag;
    always @(posedge a_clk or negedge a_rst_n) begin
        if(~a_rst_n) flag <= 0;
	else flag <= flag ^ a_flag;
    end

    (* ASYNC_REG = "TRUE" *) reg[2:0] flag_sync;
    always @(posedge b_clk or negedge b_rst_n) begin
        if(~b_rst_n) flag_sync <= 3'h0;
	else flag_sync <= {flag_sync[1:0], flag};
    end

    assign b_flag = flag_sync[1] ^ flag_sync[2];

endmodule