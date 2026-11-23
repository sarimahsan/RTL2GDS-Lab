`timescale 1ns / 1ps

// Week 3: IEEE-754 FP16 (binary16) Unpack, Align & Normalize Core
// 2-stage registered pipeline supporting FP16 ADD, SUB, MUL, and ABS
// with subnormals, Inf/NaN handling, Leading-Zero Normalization, and Round-to-Nearest-Even.
module fp16_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [1:0]  op_sel,     // 00: ADD, 01: SUB, 10: MUL, 11: ABS(a_in)
    input  wire [15:0] a_in,
    input  wire [15:0] b_in,
    output reg  [15:0] result_out,
    output reg         flag_zero,
    output reg         flag_inf,
    output reg         flag_nan,
    output reg         flag_ovf,
    output reg         flag_udf,
    output reg         out_valid
);

    localparam [1:0] OP_ADD = 2'b00;
    localparam [1:0] OP_SUB = 2'b01;
    localparam [1:0] OP_MUL = 2'b10;
    localparam [1:0] OP_ABS = 2'b11;

    localparam [15:0] FP16_QNAN = 16'h7E00;

    // -------------------------------------------------------------------------
    // Stage 1 Combinational: Unpack & Align / Multiply Setup
    // -------------------------------------------------------------------------
    wire        a_sign    = a_in[15];
    wire [4:0]  a_exp_raw = a_in[14:10];
    wire [9:0]  a_frac    = a_in[9:0];
    wire        a_is_zero = (a_exp_raw == 5'd0)  && (a_frac == 10'd0);
    wire        a_is_inf  = (a_exp_raw == 5'd31) && (a_frac == 10'd0);
    wire        a_is_nan  = (a_exp_raw == 5'd31) && (a_frac != 10'd0);
    wire [10:0] a_mant    = (a_exp_raw == 5'd0) ? {1'b0, a_frac} : {1'b1, a_frac};
    wire [4:0]  a_exp_eff = (a_exp_raw == 5'd0) ? 5'd1 : a_exp_raw;

    wire        b_sign_raw = b_in[15];
    wire        b_sign     = (op_sel == OP_SUB) ? ~b_sign_raw : b_sign_raw;
    wire [4:0]  b_exp_raw  = b_in[14:10];
    wire [9:0]  b_frac     = b_in[9:0];
    wire        b_is_zero  = (b_exp_raw == 5'd0)  && (b_frac == 10'd0);
    wire        b_is_inf   = (b_exp_raw == 5'd31) && (b_frac == 10'd0);
    wire        b_is_nan   = (b_exp_raw == 5'd31) && (b_frac != 10'd0);
    wire [10:0] b_mant     = (b_exp_raw == 5'd0) ? {1'b0, b_frac} : {1'b1, b_frac};
    wire [4:0]  b_exp_eff  = (b_exp_raw == 5'd0) ? 5'd1 : b_exp_raw;

    // ADD/SUB: Magnitude comparison to order lg >= sm
    wire a_ge_b = (a_exp_eff > b_exp_eff) ||
                  ((a_exp_eff == b_exp_eff) && (a_mant >= b_mant));

    wire        lg_sign = a_ge_b ? a_sign    : b_sign;
    wire [4:0]  lg_exp  = a_ge_b ? a_exp_eff : b_exp_eff;
    wire [10:0] lg_mant = a_ge_b ? a_mant    : b_mant;

    wire        sm_sign = a_ge_b ? b_sign    : a_sign;
    wire [4:0]  sm_exp  = a_ge_b ? b_exp_eff : a_exp_eff;
    wire [10:0] sm_mant = a_ge_b ? b_mant    : a_mant;

    wire [4:0]  exp_diff = lg_exp - sm_exp;

    // Align sm_mant into {11-bit mant, G, R, S} = 14 bits
    reg [13:0] sm_aligned_comb;
    reg [13:0] sm_ext;
    reg        sticky_comb;
    integer    k;

    always @(*) begin
        sm_ext = {sm_mant, 3'b000};
        if (exp_diff >= 5'd14) begin
            sm_aligned_comb = {13'd0, (sm_mant != 11'd0)};
        end else begin
            sm_aligned_comb = sm_ext >> exp_diff;
            sticky_comb = 1'b0;
            for (k = 0; k < 14; k = k + 1) begin
                if (k < exp_diff)
                    sticky_comb = sticky_comb | sm_ext[k];
            end
            sm_aligned_comb[0] = sm_aligned_comb[0] | sticky_comb;
        end
    end

    // Special-case resolution in Stage 1
    reg        s1_special_comb;
    reg [15:0] s1_special_res_comb;
    reg        s1_sp_zero_comb;
    reg        s1_sp_inf_comb;
    reg        s1_sp_nan_comb;

    always @(*) begin
        s1_special_comb     = 1'b0;
        s1_special_res_comb = 16'd0;
        s1_sp_zero_comb     = 1'b0;
        s1_sp_inf_comb      = 1'b0;
        s1_sp_nan_comb      = 1'b0;

        case (op_sel)
            OP_ADD, OP_SUB: begin
                if (a_is_nan || b_is_nan) begin
                    s1_special_comb     = 1'b1;
                    s1_special_res_comb = FP16_QNAN;
                    s1_sp_nan_comb      = 1'b1;
                end else if (a_is_inf && b_is_inf) begin
                    s1_special_comb = 1'b1;
                    if (a_sign == b_sign) begin
                        s1_special_res_comb = {a_sign, 5'd31, 10'd0};
                        s1_sp_inf_comb      = 1'b1;
                    end else begin
                        s1_special_res_comb = FP16_QNAN;
                        s1_sp_nan_comb      = 1'b1;
                    end
                end else if (a_is_inf) begin
                    s1_special_comb     = 1'b1;
                    s1_special_res_comb = {a_sign, 5'd31, 10'd0};
                    s1_sp_inf_comb      = 1'b1;
                end else if (b_is_inf) begin
                    s1_special_comb     = 1'b1;
                    s1_special_res_comb = {b_sign, 5'd31, 10'd0};
                    s1_sp_inf_comb      = 1'b1;
                end else if (a_is_zero && b_is_zero) begin
                    s1_special_comb     = 1'b1;
                    s1_special_res_comb = {(a_sign & b_sign), 15'd0};
                    s1_sp_zero_comb     = 1'b1;
                end else if (a_is_zero) begin
                    s1_special_comb     = 1'b1;
                    s1_special_res_comb = {b_sign, b_in[14:0]};
                end else if (b_is_zero) begin
                    s1_special_comb     = 1'b1;
                    s1_special_res_comb = a_in;
                end
            end

            OP_MUL: begin
                if (a_is_nan || b_is_nan) begin
                    s1_special_comb     = 1'b1;
                    s1_special_res_comb = FP16_QNAN;
                    s1_sp_nan_comb      = 1'b1;
                end else if ((a_is_zero && b_is_inf) || (a_is_inf && b_is_zero)) begin
                    s1_special_comb     = 1'b1;
                    s1_special_res_comb = FP16_QNAN;
                    s1_sp_nan_comb      = 1'b1;
                end else if (a_is_inf || b_is_inf) begin
                    s1_special_comb     = 1'b1;
                    s1_special_res_comb = {(a_sign ^ b_sign_raw), 5'd31, 10'd0};
                    s1_sp_inf_comb      = 1'b1;
                end else if (a_is_zero || b_is_zero) begin
                    s1_special_comb     = 1'b1;
                    s1_special_res_comb = {(a_sign ^ b_sign_raw), 15'd0};
                    s1_sp_zero_comb     = 1'b1;
                end
            end

            OP_ABS: begin
                s1_special_comb = 1'b1;
                if (a_is_nan) begin
                    s1_special_res_comb = FP16_QNAN;
                    s1_sp_nan_comb      = 1'b1;
                end else begin
                    s1_special_res_comb = {1'b0, a_in[14:0]};
                    s1_sp_inf_comb      = a_is_inf;
                    s1_sp_zero_comb     = a_is_zero;
                end
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Stage 1 Pipeline Registers
    // -------------------------------------------------------------------------
    reg        s1_valid;
    reg [1:0]  s1_op;
    reg        s1_special;
    reg [15:0] s1_special_res;
    reg        s1_sp_zero;
    reg        s1_sp_inf;
    reg        s1_sp_nan;

    // ADD/SUB registers
    reg        s1_eff_sub;
    reg        s1_lg_sign;
    reg [4:0]  s1_lg_exp;
    reg [13:0] s1_lg_mant;
    reg [13:0] s1_sm_mant;

    // MUL registers
    reg               s1_mul_sign;
    reg signed [6:0]  s1_mul_exp;
    reg [21:0]        s1_mul_prod;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid       <= 1'b0;
            s1_op          <= 2'b00;
            s1_special     <= 1'b0;
            s1_special_res <= 16'd0;
            s1_sp_zero     <= 1'b0;
            s1_sp_inf      <= 1'b0;
            s1_sp_nan      <= 1'b0;
            s1_eff_sub     <= 1'b0;
            s1_lg_sign     <= 1'b0;
            s1_lg_exp      <= 5'd0;
            s1_lg_mant     <= 14'd0;
            s1_sm_mant     <= 14'd0;
            s1_mul_sign    <= 1'b0;
            s1_mul_exp     <= 7'sd0;
            s1_mul_prod    <= 22'd0;
        end else begin
            s1_valid <= in_valid;
            if (in_valid) begin
                s1_op          <= op_sel;
                s1_special     <= s1_special_comb;
                s1_special_res <= s1_special_res_comb;
                s1_sp_zero     <= s1_sp_zero_comb;
                s1_sp_inf      <= s1_sp_inf_comb;
                s1_sp_nan      <= s1_sp_nan_comb;

                s1_eff_sub     <= (lg_sign != sm_sign);
                s1_lg_sign     <= lg_sign;
                s1_lg_exp      <= lg_exp;
                s1_lg_mant     <= {lg_mant, 3'b000};
                s1_sm_mant     <= sm_aligned_comb;

                s1_mul_sign    <= a_sign ^ b_sign_raw;
                s1_mul_exp     <= $signed({2'b00, a_exp_eff}) + $signed({2'b00, b_exp_eff}) - 7'sd15;
                s1_mul_prod    <= a_mant * b_mant;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2 Combinational: Execute, LZC Normalize, Round-to-Nearest-Even, Pack
    // -------------------------------------------------------------------------
    reg [15:0] s2_res_comb;
    reg        s2_zero_comb;
    reg        s2_inf_comb;
    reg        s2_nan_comb;
    reg        s2_ovf_comb;
    reg        s2_udf_comb;

    // ADD/SUB temporaries
    reg [14:0] addsub_raw;
    reg [3:0]  lzc_add;
    reg [4:0]  shift_add;
    reg [13:0] norm_add;
    reg signed [6:0] exp_norm;
    reg        res_sign;
    reg [10:0] mant_11;
    reg        g_bit, r_bit, s_bit;

    // MUL temporaries
    reg [4:0]  lzc_mul;
    reg [21:0] prod_norm;
    reg [21:0] prod_shifted;
    reg [5:0]  sub_shift;
    reg        sticky_mul;

    // Rounding & packing temporaries
    reg        round_up;
    reg [11:0] mant_rnd;
    reg [10:0] mant_fin;
    reg signed [6:0] exp_fin;
    reg        found_lzc;
    integer    i;

    always @(*) begin
        s2_res_comb  = 16'd0;
        s2_zero_comb = 1'b0;
        s2_inf_comb  = 1'b0;
        s2_nan_comb  = 1'b0;
        s2_ovf_comb  = 1'b0;
        s2_udf_comb  = 1'b0;

        addsub_raw   = 15'd0;
        lzc_add      = 4'd0;
        shift_add    = 5'd0;
        norm_add     = 14'd0;
        exp_norm     = 7'sd0;
        res_sign     = 1'b0;
        mant_11      = 11'd0;
        g_bit        = 1'b0;
        r_bit        = 1'b0;
        s_bit        = 1'b0;

        lzc_mul      = 5'd0;
        prod_norm    = 22'd0;
        prod_shifted = 22'd0;
        sub_shift    = 6'd0;
        sticky_mul   = 1'b0;

        round_up     = 1'b0;
        mant_rnd     = 12'd0;
        mant_fin     = 11'd0;
        exp_fin      = 7'sd0;
        found_lzc    = 1'b0;

        if (s1_special) begin
            s2_res_comb  = s1_special_res;
            s2_zero_comb = s1_sp_zero;
            s2_inf_comb  = s1_sp_inf;
            s2_nan_comb  = s1_sp_nan;
        end else if (s1_op == OP_MUL) begin
            res_sign = s1_mul_sign;

            // Count leading zeros in 22-bit product [21:0]
            lzc_mul   = 5'd22;
            found_lzc = 1'b0;
            for (i = 21; i >= 0; i = i - 1) begin
                if (!found_lzc && s1_mul_prod[i]) begin
                    lzc_mul   = 5'd21 - i[4:0];
                    found_lzc = 1'b1;
                end
            end

            // Normalize so leading 1 is at bit 20 (since 1.xxx * 1.xxx has 1. at bit 20)
            if (lzc_mul == 5'd0) begin
                // Bit 21 is 1: shift right by 1, exponent + 1
                prod_norm = {1'b0, s1_mul_prod[21:1]};
                sticky_mul = s1_mul_prod[0];
                exp_norm  = s1_mul_exp + 7'sd1;
            end else begin
                prod_norm  = s1_mul_prod << (lzc_mul - 5'd1);
                sticky_mul = 1'b0;
                exp_norm   = s1_mul_exp - $signed({2'b00, (lzc_mul - 5'd1)});
            end

            // Handle subnormal / underflow if exp_norm <= 0
            if (exp_norm <= 7'sd0) begin
                sub_shift = 6'd1 - exp_norm[5:0];
                if (sub_shift >= 6'd22) begin
                    prod_shifted = 22'd0;
                    sticky_mul   = sticky_mul | (prod_norm != 22'd0);
                    s2_udf_comb  = 1'b1;
                end else begin
                    prod_shifted = prod_norm >> sub_shift;
                    for (i = 0; i < 22; i = i + 1) begin
                        if (i < sub_shift)
                            sticky_mul = sticky_mul | prod_norm[i];
                    end
                end
                exp_norm = 7'sd0;
                mant_11  = prod_shifted[20:10];
                g_bit    = prod_shifted[9];
                r_bit    = prod_shifted[8];
                s_bit    = (prod_shifted[7:0] != 8'd0) | sticky_mul;
                if (mant_11[10] == 1'b0)
                    s2_udf_comb = 1'b1;
            end else begin
                mant_11 = prod_norm[20:10];
                g_bit   = prod_norm[9];
                r_bit   = prod_norm[8];
                s_bit   = (prod_norm[7:0] != 8'd0) | sticky_mul;
            end

            // Round-to-Nearest-Even (RNE)
            round_up = g_bit & (r_bit | s_bit | mant_11[0]);
            mant_rnd = {1'b0, mant_11} + {11'd0, round_up};
            if (mant_rnd[11]) begin
                mant_fin = mant_rnd[11:1];
                exp_fin  = exp_norm + 7'sd1;
            end else begin
                mant_fin = mant_rnd[10:0];
                exp_fin  = (exp_norm == 7'sd0 && mant_rnd[10]) ? 7'sd1 : exp_norm;
            end

            // Pack result
            if (exp_fin >= 7'sd31) begin
                s2_res_comb = {res_sign, 5'd31, 10'd0};
                s2_inf_comb = 1'b1;
                s2_ovf_comb = 1'b1;
            end else if ((exp_fin == 7'sd0) && (mant_fin[9:0] == 10'd0)) begin
                s2_res_comb  = {res_sign, 15'd0};
                s2_zero_comb = 1'b1;
                s2_udf_comb  = 1'b1;
            end else if (mant_fin[10] == 1'b0) begin
                s2_res_comb = {res_sign, 5'd0, mant_fin[9:0]};
            end else begin
                s2_res_comb = {res_sign, exp_fin[4:0], mant_fin[9:0]};
            end
        end else begin
            // OP_ADD or OP_SUB
            res_sign = s1_lg_sign;
            if (!s1_eff_sub) begin
                addsub_raw = {1'b0, s1_lg_mant} + {1'b0, s1_sm_mant};
                if (addsub_raw[14]) begin
                    norm_add = addsub_raw[14:1];
                    norm_add[0] = addsub_raw[1] | addsub_raw[0];
                    exp_norm = $signed({2'b00, s1_lg_exp}) + 7'sd1;
                end else begin
                    norm_add = addsub_raw[13:0];
                    exp_norm = $signed({2'b00, s1_lg_exp});
                end
            end else begin
                addsub_raw = {1'b0, s1_lg_mant} - {1'b0, s1_sm_mant};
                if (addsub_raw == 15'd0) begin
                    norm_add = 14'd0;
                    exp_norm = 7'sd0;
                    res_sign = 1'b0; // IEEE-754 RNE: x - x = +0
                end else begin
                    lzc_add   = 4'd14;
                    found_lzc = 1'b0;
                    for (i = 13; i >= 0; i = i - 1) begin
                        if (!found_lzc && addsub_raw[i]) begin
                            lzc_add   = 4'd13 - i[3:0];
                            found_lzc = 1'b1;
                        end
                    end
                    if ({1'b0, lzc_add} < (s1_lg_exp - 5'd1))
                        shift_add = {1'b0, lzc_add};
                    else
                        shift_add = s1_lg_exp - 5'd1;

                    norm_add = addsub_raw[13:0] << shift_add;
                    exp_norm = $signed({2'b00, s1_lg_exp}) - $signed({2'b00, shift_add});
                end
            end

            if (addsub_raw == 15'd0 && s1_eff_sub) begin
                s2_res_comb  = 16'h0000;
                s2_zero_comb = 1'b1;
            end else begin
                mant_11 = norm_add[13:3];
                g_bit   = norm_add[2];
                r_bit   = norm_add[1];
                s_bit   = norm_add[0];

                round_up = g_bit & (r_bit | s_bit | mant_11[0]);
                mant_rnd = {1'b0, mant_11} + {11'd0, round_up};

                if (mant_rnd[11]) begin
                    mant_fin = mant_rnd[11:1];
                    exp_fin  = exp_norm + 7'sd1;
                end else begin
                    mant_fin = mant_rnd[10:0];
                    exp_fin  = exp_norm;
                end

                if (exp_fin >= 7'sd31) begin
                    s2_res_comb = {res_sign, 5'd31, 10'd0};
                    s2_inf_comb = 1'b1;
                    s2_ovf_comb = 1'b1;
                end else if ((exp_fin == 7'sd1) && (mant_fin[10] == 1'b0)) begin
                    if (mant_fin[9:0] == 10'd0) begin
                        s2_res_comb  = {res_sign, 15'd0};
                        s2_zero_comb = 1'b1;
                    end else begin
                        s2_res_comb = {res_sign, 5'd0, mant_fin[9:0]};
                    end
                end else begin
                    s2_res_comb = {res_sign, exp_fin[4:0], mant_fin[9:0]};
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2 Output Registers
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_out <= 16'd0;
            flag_zero  <= 1'b0;
            flag_inf   <= 1'b0;
            flag_nan   <= 1'b0;
            flag_ovf   <= 1'b0;
            flag_udf   <= 1'b0;
            out_valid  <= 1'b0;
        end else begin
            out_valid <= s1_valid;
            if (s1_valid) begin
                result_out <= s2_res_comb;
                flag_zero  <= s2_zero_comb;
                flag_inf   <= s2_inf_comb;
                flag_nan   <= s2_nan_comb;
                flag_ovf   <= s2_ovf_comb;
                flag_udf   <= s2_udf_comb;
            end
        end
    end

endmodule
