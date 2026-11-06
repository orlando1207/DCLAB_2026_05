module NEXYS_A7(
    //Clock signal
    input CLK100MHZ,
    //Switches
    input [15:0]SW,
    //LEDs
    output [15:0]LED,
    //RGB LEDs
    output LED16_B,
    output LED16_G,
    output LED16_R,
    output LED17_B,
    output LED17_G,
    output LED17_R,
    //7 segment display
    output CA,
    output CB,
    output CC,
    output CD,
    output CE,
    output CF,
    output CG,
    output DP,
    output [7:0]AN,
    //CPU Reset Button
    input CPU_RESETN,
    //Buttons
    input BTNC,
    input BTNU,
    input BTNL,
    input BTNR,
    input BTND,
    //Pmod Headers
    inout [10:0]JA,
    inout [10:0]JB,
    inout [10:0]JC,
    inout [10:0]JD,
    inout [4:0]XA_N,
    inout [4:0]XA_P,
    //VGA Connector
    output [3:0]VGA_R,
    output [3:0]VGA_G,
    output [3:0]VGA_B,
    output VGA_HS,
    output VGA_VS,
    //Micro SD Connector
    output SD_RESET,
    input SD_CD,
    inout SD_SCK,
    inout SD_CMD,
    inout [3:0]SD_DAT,
    //Accelerometer
    input ACL_MISO,
    output ACL_MOSI,
    output ACL_SCLK,
    output ACL_CSN,
    input [2:0]ACL_INT,
    //Temperature Sensor
    output TMP_SCL,
    inout TMP_SDA,
    input TMP_INT,
    input TMP_CT,
    //Omnidirectional Microphone
    output M_CLK,
    input M_DATA,
    output M_LRSEL,
    //PWM Audio Amplifier
    output AUD_PWM,
    output AUD_SD,
    //USB-RS232 Interface
    input UART_TXD_IN,
    output UART_RXD_OUT,
    output UART_CTS,
    input UART_RTS,
    //USB HID (PS/2)
    inout PS2_CLK,
    inout PS2_DATA,
    //SMSC Ethernet PHY
    output ETH_MDC,
    inout ETH_MDIO,
    output ETH_RSTN,
    inout ETH_CRSDV,
    inout ETH_RXERR,
    inout [1:0]ETH_RXD,
    output ETH_TXEN,
    output [1:0]ETH_TXD,
    inout ETH_REFCLK,
    inout ETH_INTN,
    //Quad SPI Flash
    inout [3:0]QSPI_DQ,
    output QSPI_CSN,
    //ddr2 sdram
    output [12:0]ddr2_addr,
    output [2:0]ddr2_ba,
    output ddr2_ras_n,
    output ddr2_cas_n,
    output ddr2_we_n,
    output ddr2_ck_p,
    output ddr2_ck_n,
    output ddr2_cke,
    output ddr2_cs_n,
    output [1:0]ddr2_dm,
    output ddr2_odt,
    inout [15:0]ddr2_dq,
    inout [1:0]ddr2_dqs_p,
    inout [1:0]ddr2_dqs_n
    );

    logic BTNU_down,BTNR_down,BTND_down,locked,CLK200MHZ;
    logic[3:0] digit0,digit1,digit2,digit3,digit4,digit5,digit6,digit7;
    
    clk_wiz_0 clk_wiz(
    .reset(BTNC),
    .clk_in1(CLK100MHZ),
    .clk_out1(CLK200MHZ),
    .clk_out5(M_CLK),
    .locked(locked)
    );
    
    
    Top(
    .clk(M_CLK),
    .locked(locked),
    .rst(BTNC),
    .data_in(M_DATA),
    .data_out(AUD_PWM),

    .record_btn(BTNU_down),
    .replay_btn(BTND_down),

    //ddr2 Interface
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
    .ddr2_cs_n(ddr2_cs_n),
    .ddr2_dm(ddr2_dm),
    .ddr2_odt(ddr2_odt),
    .clk_mem(CLK200MHZ)
    );

    Seven_Segment_Display seven0(
        .i_clk(M_CLK),
        .i_rst(BTNC),
        .i_digit0(digit0),
        .i_digit1(digit1),
        .i_digit2(digit2),
        .i_digit3(digit3),
        .i_digit4(digit4),
        .i_digit5(digit5),
        .i_digit6(digit6),
        .i_digit7(digit7),
        .CA(CA),
        .CB(CB),
        .CC(CC),
        .CD(CD),
        .CE(CE),
        .CF(CF),
        .CG(CG),
        .o_an(AN)
    );
    Debounce deb0(
        .i_in(BTNU),
        .i_clk(M_CLK),
        .i_rst(BTNC),
        .o_pos(BTNU_down)
    );
    
    Debounce deb1(
        .i_in(BTNR),
        .i_clk(M_CLK),
        .i_rst(BTNC),
        .o_pos(BTNR_down)
    );
    
    Debounce deb2(
        .i_in(BTND),
        .i_clk(M_CLK),
        .i_rst(BTNC),
        .o_pos(BTND_down)
    );

endmodule


