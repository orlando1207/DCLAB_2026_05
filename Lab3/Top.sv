module Seven_Segment_Display(
    input i_clk,
    input i_rst,
    input [3:0] i_digit0,
    input [3:0] i_digit1,
    input [3:0] i_digit2,
    input [3:0] i_digit3,
    input [3:0] i_digit4,
    input [3:0] i_digit5,
    input [3:0] i_digit6,
    input [3:0] i_digit7,
    output reg CA,
    output reg CB,
    output reg CC,
    output reg CD,
    output reg CE,
    output reg CF,
    output reg CG,
    output logic [7:0] o_an
);
logic [6:0] seg[7:0];
logic [7:0] an;
logic [2:0] state_r, state_w;
logic [9:0] counter_r, counter_w;
logic [3:0] i_digit[0:7];

assign i_digit[0] = i_digit0;
assign i_digit[1] = i_digit1;
assign i_digit[2] = i_digit2;
assign i_digit[3] = i_digit3;
assign i_digit[4] = i_digit4;
assign i_digit[5] = i_digit5;
assign i_digit[6] = i_digit6;
assign i_digit[7] = i_digit7;

integer i;

genvar gen_i;

generate 
    for(gen_i=0;gen_i<8;gen_i++)begin:gen_disp
        Display_digit disp(
            .i_digit(i_digit[gen_i]),
            .seg(seg[gen_i]), 
            .an(an[gen_i])
        );
    end
endgenerate

always_comb begin
    state_w = state_r;
    counter_w = counter_r;
    {CG,CF,CE,CD,CC,CB,CA} = seg[state_r];
    for (i = 0; i < 8; i = i + 1) begin
        if (i == state_r) begin
            o_an[i] = an[i];
        end else begin
            o_an[i] = 1'b1;
        end
    end    
    if(counter_r < 10'd1000)begin
        counter_w = counter_r + 1;    
    end else begin 
        counter_w = 10'd0;
        state_w = state_r + 1;
        if (state_r == 7) begin
            state_w = 3'b000;
        end
    end
end

always_ff @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        state_r <= 3'b000;
        counter_r <= 10'd0;
        
    end else begin
        state_r <= state_w;
        counter_r <= counter_w;
    end

end

endmodule

module Display_digit (
    input [3:0] i_digit,
    output logic [6:0] seg,
    output logic an
);

    // Segment encoding for digits 0-9
    always_comb begin
        an = 1'b0; // Enable the digit
        case (i_digit)
            4'd0: seg = 7'b1000000;
            4'd1: seg = 7'b1111001;
            4'd2: seg = 7'b0100100;
            4'd3: seg = 7'b0110000;
            4'd4: seg = 7'b0011001;
            4'd5: seg = 7'b0010010;
            4'd6: seg = 7'b0000010;
            4'd7: seg = 7'b1011000;
            4'd8: seg = 7'b0000000;
            4'd9: seg = 7'b0010000;
            default: begin
                seg = 7'b1111111; // All segments off
                an = 1'b1; // Disable the digit
            end
        endcase
    end

endmodule