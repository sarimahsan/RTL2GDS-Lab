`timescale 1ns / 1ps

// Week 2: 16-bit Signed Arithmetic & Saturation Unit
// Supports 2's complement add/sub/neg, 1's complement, Signed-Magnitude <-> 2's complement,
// Excess-32768 biased conversions, optional saturation, and N/Z/V/C status flags.
module signed_arith_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [2:0]  op_sel,
    input  wire        sat_en,
    input  wire [15:0] a_in,
    input  wire [15:0] b_in,
    output reg  [15:0] result_out,
    output reg         flag_n,
    output reg         flag_z,
    output reg         flag_v,
    output reg         flag_c,
    output reg         out_valid
);

    // Operation encodings
    localparam [2:0] OP_ADD     = 3'b000; // 2's complement A + B
    localparam [2:0] OP_SUB     = 3'b001; // 2's complement A - B
    localparam [2:0] OP_NEG     = 3'b010; // 2's complement -A
    localparam [2:0] OP_SM2TC   = 3'b011; // Signed-Magnitude -> 2's Complement
    localparam [2:0] OP_TC2SM   = 3'b100; // 2's Complement -> Signed-Magnitude
    localparam [2:0] OP_ONES    = 3'b101; // 1's Complement (~A)
    localparam [2:0] OP_TC2BIAS = 3'b110; // 2's Complement -> Biased (Excess-32768)
    localparam [2:0] OP_BIAS2TC = 3'b111; // Biased (Excess-32768) -> 2's Complement

    localparam [15:0] SAT_POS_TC = 16'h7FFF; // +32767 (2's complement max)
    localparam [15:0] SAT_NEG_TC = 16'h8000; // -32768 (2's complement min)
    localparam [15:0] SAT_NEG_SM = 16'hFFFF; // -32767 (Signed-Magnitude min)

    // Combinational datapath signals
    wire [16:0] add_ext = {1'b0, a_in} + {1'b0, b_in};
    wire [16:0] sub_ext = {1'b0, a_in} + {1'b0, ~b_in} + 17'd1;
    wire [16:0] neg_ext = {1'b0, ~a_in} + 17'd1;

    wire add_ovf = (a_in[15] == b_in[15]) && (add_ext[15] != a_in[15]);
    wire sub_ovf = (a_in[15] != b_in[15]) && (sub_ext[15] != a_in[15]);
    wire neg_ovf = (a_in == 16'h8000);
    wire tc2sm_ovf = (a_in == 16'h8000);

    // Signed-Magnitude -> 2's Complement
    wire [15:0] sm_mag_ext = {1'b0, a_in[14:0]};
    wire [15:0] sm2tc_res  = (a_in[14:0] == 15'd0) ? 16'h0000 :
                             (a_in[15]             ? (~sm_mag_ext + 16'd1) : sm_mag_ext);

    // 2's Complement -> Signed-Magnitude
    wire [15:0] tc_abs     = a_in[15] ? (~a_in + 16'd1) : a_in;
    wire [15:0] tc2sm_raw  = tc2sm_ovf ? 16'h8000 : {a_in[15], tc_abs[14:0]};

    reg [15:0] comb_res;
    reg        comb_v;
    reg        comb_c;

    always @(*) begin
        comb_res = 16'd0;
        comb_v   = 1'b0;
        comb_c   = 1'b0;

        case (op_sel)
            OP_ADD: begin
                comb_v   = add_ovf;
                comb_c   = add_ext[16];
                if (sat_en && add_ovf)
                    comb_res = a_in[15] ? SAT_NEG_TC : SAT_POS_TC;
                else
                    comb_res = add_ext[15:0];
            end

            OP_SUB: begin
                comb_v   = sub_ovf;
                comb_c   = sub_ext[16];
                if (sat_en && sub_ovf)
                    comb_res = a_in[15] ? SAT_NEG_TC : SAT_POS_TC;
                else
                    comb_res = sub_ext[15:0];
            end

            OP_NEG: begin
                comb_v   = neg_ovf;
                comb_c   = neg_ext[16];
                if (sat_en && neg_ovf)
                    comb_res = SAT_POS_TC;
                else
                    comb_res = neg_ext[15:0];
            end

            OP_SM2TC: begin
                comb_res = sm2tc_res;
                comb_v   = 1'b0;
                comb_c   = 1'b0;
            end

            OP_TC2SM: begin
                comb_v   = tc2sm_ovf;
                comb_c   = 1'b0;
                if (sat_en && tc2sm_ovf)
                    comb_res = SAT_NEG_SM;
                else
                    comb_res = tc2sm_raw;
            end

            OP_ONES: begin
                comb_res = ~a_in;
                comb_v   = 1'b0;
                comb_c   = 1'b0;
            end

            OP_TC2BIAS: begin
                comb_res = a_in ^ 16'h8000;
                comb_v   = 1'b0;
                comb_c   = 1'b0;
            end

            OP_BIAS2TC: begin
                comb_res = a_in ^ 16'h8000;
                comb_v   = 1'b0;
                comb_c   = 1'b0;
            end

            default: begin
                comb_res = 16'd0;
                comb_v   = 1'b0;
                comb_c   = 1'b0;
            end
        endcase
    end

    // Registered output stage
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_out <= 16'd0;
            flag_n     <= 1'b0;
            flag_z     <= 1'b0;
            flag_v     <= 1'b0;
            flag_c     <= 1'b0;
            out_valid  <= 1'b0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                result_out <= comb_res;
                flag_n     <= comb_res[15];
                flag_z     <= (comb_res == 16'd0);
                flag_v     <= comb_v;
                flag_c     <= comb_c;
            end
        end
    end

endmodule
