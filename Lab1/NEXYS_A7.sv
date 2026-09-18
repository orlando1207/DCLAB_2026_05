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
    output QSPI_CSN
    );
    
    
wire BTNU_down;
wire [3:0] random_value;
wire[3:0] digit0,digit1,digit2,digit3,digit4,digit5,digit6,digit7;

    Seven_Segment_Display seven0(
    	.i_clk(CLK100MHZ),
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
        .i_clk(CLK100MHZ),
        .i_rst(BTNC),
        .o_pos(BTNU_down)
    );
    
    Top top0(
	.i_clk(CLK100MHZ),
	.i_rst(BTNC),
	.i_start(BTNU_down),
	.o_random_out(random_value)
    );

    assign LED = 16'b0;

    assign digit0 =
    (random_value >= 4'd10)
        ? random_value - 4'd10
        : random_value;
    assign digit1 =
        (random_value >= 4'd10)
            ? 4'd1
            : 4'd10;
    assign digit2 = 10;
    assign digit3 = 10;
    assign digit4 = 10;
    assign digit5 = 10;
    assign digit6 = 10;
    assign digit7 = 10;

    assign DP = 1'b1;

endmodule
