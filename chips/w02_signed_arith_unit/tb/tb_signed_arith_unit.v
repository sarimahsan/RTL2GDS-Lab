`timescale 1ns / 1ps

module tb_signed_arith_unit;

    localparam [2:0] OP_ADD     = 3'b000;
    localparam [2:0] OP_SUB     = 3'b001;
    localparam [2:0] OP_NEG     = 3'b010;
    localparam [2:0] OP_SM2TC   = 3'b011;
    localparam [2:0] OP_TC2SM   = 3'b100;
    localparam [2:0] OP_ONES    = 3'b101;
    localparam [2:0] OP_TC2BIAS = 3'b110;
    localparam [2:0] OP_BIAS2TC = 3'b111;

    reg         clk;
    reg         rst_n;
    reg         in_valid;
    reg  [2:0]  op_sel;
    reg         sat_en;
    reg  [15:0] a_in;
    reg  [15:0] b_in;
    wire [15:0] result_out;
    wire        flag_n;
    wire        flag_z;
    wire        flag_v;
    wire        flag_c;
    wire        out_valid;

    integer errors = 0;

    signed_arith_unit dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .in_valid   (in_valid),
        .op_sel     (op_sel),
        .sat_en     (sat_en),
        .a_in       (a_in),
        .b_in       (b_in),
        .result_out (result_out),
        .flag_n     (flag_n),
        .flag_z     (flag_z),
        .flag_v     (flag_v),
        .flag_c     (flag_c),
        .out_valid  (out_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task reset_dut;
        begin
            rst_n    = 1'b0;
            in_valid = 1'b0;
            op_sel   = 3'b000;
            sat_en   = 1'b0;
            a_in     = 16'd0;
            b_in     = 16'd0;
            repeat (3) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    task run_op(
        input [2:0]   op,
        input         sat,
        input [15:0]  a,
        input [15:0]  b,
        input [15:0]  exp_res,
        input [3:0]   exp_nzvc, // {N, Z, V, C}
        input [159:0] label
    );
        reg [3:0] got_nzvc;
        begin
            @(negedge clk);
            op_sel   = op;
            sat_en   = sat;
            a_in     = a;
            b_in     = b;
            in_valid = 1'b1;
            @(posedge clk);
            #1;
            got_nzvc = {flag_n, flag_z, flag_v, flag_c};
            if (!out_valid || result_out !== exp_res || got_nzvc !== exp_nzvc) begin
                $display("[FAIL] %0s: got res=0x%04h NZVC=%b valid=%b | exp res=0x%04h NZVC=%b",
                         label, result_out, got_nzvc, out_valid, exp_res, exp_nzvc);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s: res=0x%04h NZVC=%b", label, result_out, got_nzvc);
            end
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_signed_arith_unit);

        reset_dut();

        // 1. 2's Complement Addition
        // 100 + 250 = 350 (0x015E), N=0 Z=0 V=0 C=0
        run_op(OP_ADD, 1'b0, 16'd100, 16'd250, 16'd350, 4'b0000, "ADD_Pos_Normal");
        // -50 + 50 = 0, N=0 Z=1 V=0 C=1
        run_op(OP_ADD, 1'b0, 16'hFFCE, 16'd50, 16'd0, 4'b0101, "ADD_Cancel_Zero");
        // +32767 + 1 = wrap 0x8000 (-32768), N=1 Z=0 V=1 C=0
        run_op(OP_ADD, 1'b0, 16'h7FFF, 16'd1, 16'h8000, 4'b1010, "ADD_PosOvf_Wrap");
        // +32767 + 1 = sat 0x7FFF (+32767), N=0 Z=0 V=1 C=0
        run_op(OP_ADD, 1'b1, 16'h7FFF, 16'd1, 16'h7FFF, 4'b0010, "ADD_PosOvf_Sat");
        // -32768 + -1 = sat 0x8000 (-32768), N=1 Z=0 V=1 C=1
        run_op(OP_ADD, 1'b1, 16'h8000, 16'hFFFF, 16'h8000, 4'b1011, "ADD_NegOvf_Sat");

        // 2. 2's Complement Subtraction
        // 50 - 120 = -70 (0xFFBA), N=1 Z=0 V=0 C=0
        run_op(OP_SUB, 1'b0, 16'd50, 16'd120, 16'hFFBA, 4'b1000, "SUB_Neg_Result");
        // -32768 - 1 = wrap 0x7FFF (+32767), N=0 Z=0 V=1 C=1
        run_op(OP_SUB, 1'b0, 16'h8000, 16'd1, 16'h7FFF, 4'b0011, "SUB_NegOvf_Wrap");
        // -32768 - 1 = sat 0x8000 (-32768), N=1 Z=0 V=1 C=1
        run_op(OP_SUB, 1'b1, 16'h8000, 16'd1, 16'h8000, 4'b1011, "SUB_NegOvf_Sat");
        // +32767 - (-1) = sat 0x7FFF (+32767), N=0 Z=0 V=1 C=0
        run_op(OP_SUB, 1'b1, 16'h7FFF, 16'hFFFF, 16'h7FFF, 4'b0010, "SUB_PosOvf_Sat");

        // 3. 2's Complement Negation
        // -42 = 0xFFD6, N=1 Z=0 V=0 C=0
        run_op(OP_NEG, 1'b0, 16'd42, 16'd0, 16'hFFD6, 4'b1000, "NEG_Pos42");
        // -(-32768) sat = +32767 (0x7FFF), N=0 Z=0 V=1 C=0
        run_op(OP_NEG, 1'b1, 16'h8000, 16'd0, 16'h7FFF, 4'b0010, "NEG_MinInt_Sat");

        // 4. Signed-Magnitude -> 2's Complement
        // SM -25 (0x8019) -> TC -25 (0xFFE7), N=1 Z=0 V=0 C=0
        run_op(OP_SM2TC, 1'b0, 16'h8019, 16'd0, 16'hFFE7, 4'b1000, "SM2TC_Neg25");
        // SM -0 (0x8000) -> TC 0 (0x0000), N=0 Z=1 V=0 C=0
        run_op(OP_SM2TC, 1'b0, 16'h8000, 16'd0, 16'h0000, 4'b0100, "SM2TC_NegZero");

        // 5. 2's Complement -> Signed-Magnitude
        // TC -25 (0xFFE7) -> SM -25 (0x8019), N=1 Z=0 V=0 C=0
        run_op(OP_TC2SM, 1'b0, 16'hFFE7, 16'd0, 16'h8019, 4'b1000, "TC2SM_Neg25");
        // TC -32768 (0x8000) sat -> SM -32767 (0xFFFF), N=1 Z=0 V=1 C=0
        run_op(OP_TC2SM, 1'b1, 16'h8000, 16'd0, 16'hFFFF, 4'b1010, "TC2SM_MinInt_Sat");

        // 6. 1's Complement
        // ~0x1234 = 0xEDCB, N=1 Z=0 V=0 C=0
        run_op(OP_ONES, 1'b0, 16'h1234, 16'd0, 16'hEDCB, 4'b1000, "ONES_1234");

        // 7. Biased (Excess-32768) Conversions
        // TC -32768 (0x8000) -> Biased 0 (0x0000), N=0 Z=1 V=0 C=0
        run_op(OP_TC2BIAS, 1'b0, 16'h8000, 16'd0, 16'h0000, 4'b0100, "TC2BIAS_MinInt");
        // Biased 0x802A (+42) -> TC +42 (0x002A), N=0 Z=0 V=0 C=0
        run_op(OP_BIAS2TC, 1'b0, 16'h802A, 16'd0, 16'h002A, 4'b0000, "BIAS2TC_Pos42");

        repeat (3) @(posedge clk);
        if (errors == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("TESTS FAILED: %0d error(s)", errors);
        $finish;
    end

endmodule
