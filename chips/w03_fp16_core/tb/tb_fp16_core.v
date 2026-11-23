`timescale 1ns / 1ps

module tb_fp16_core;

    localparam [1:0] OP_ADD = 2'b00;
    localparam [1:0] OP_SUB = 2'b01;
    localparam [1:0] OP_MUL = 2'b10;
    localparam [1:0] OP_ABS = 2'b11;

    reg         clk;
    reg         rst_n;
    reg         in_valid;
    reg  [1:0]  op_sel;
    reg  [15:0] a_in;
    reg  [15:0] b_in;
    wire [15:0] result_out;
    wire        flag_zero;
    wire        flag_inf;
    wire        flag_nan;
    wire        flag_ovf;
    wire        flag_udf;
    wire        out_valid;

    integer errors = 0;

    fp16_core dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .in_valid   (in_valid),
        .op_sel     (op_sel),
        .a_in       (a_in),
        .b_in       (b_in),
        .result_out (result_out),
        .flag_zero  (flag_zero),
        .flag_inf   (flag_inf),
        .flag_nan   (flag_nan),
        .flag_ovf   (flag_ovf),
        .flag_udf   (flag_udf),
        .out_valid  (out_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task reset_dut;
        begin
            rst_n    = 1'b0;
            in_valid = 1'b0;
            op_sel   = OP_ADD;
            a_in     = 16'd0;
            b_in     = 16'd0;
            repeat (3) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    // 2-stage pipeline: drive before posedge T0 -> Stage 1 latches at T0 -> Stage 2 latches at T1
    task run_op(
        input [1:0]   op,
        input [15:0]  a,
        input [15:0]  b,
        input [15:0]  exp_res,
        input [4:0]   exp_flags, // {zero, inf, nan, ovf, udf}
        input [319:0] label
    );
        reg [4:0] got_flags;
        begin
            @(negedge clk);
            op_sel   = op;
            a_in     = a;
            b_in     = b;
            in_valid = 1'b1;
            @(posedge clk); // Stage 1 capture
            @(negedge clk);
            in_valid = 1'b0;
            @(posedge clk); // Stage 2 capture
            #1;
            got_flags = {flag_zero, flag_inf, flag_nan, flag_ovf, flag_udf};
            if (!out_valid || result_out !== exp_res || got_flags !== exp_flags) begin
                $display("[FAIL] %0s: got res=0x%04h flags=%b valid=%b | exp res=0x%04h flags=%b",
                         label, result_out, got_flags, out_valid, exp_res, exp_flags);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s: res=0x%04h flags=%b", label, result_out, got_flags);
            end
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_fp16_core);

        reset_dut();

        // Basic ADD
        run_op(OP_ADD, 16'h3C00, 16'h4000, 16'h4200, 5'b00000, "1.0 + 2.0 = 3.0");
        run_op(OP_ADD, 16'h3C00, 16'h3C00, 16'h4000, 5'b00000, "1.0 + 1.0 = 2.0");
        run_op(OP_ADD, 16'h3E00, 16'hC000, 16'hB800, 5'b00000, "1.5 + (-2.0) = -0.5");
        run_op(OP_ADD, 16'h3C00, 16'hBC00, 16'h0000, 5'b10000, "1.0 + (-1.0) = +0");

        // Basic SUB & LZC normalization (massive cancellation)
        run_op(OP_SUB, 16'h4200, 16'h3C00, 16'h4000, 5'b00000, "3.0 - 1.0 = 2.0");
        run_op(OP_SUB, 16'h3C01, 16'h3C00, 16'h1400, 5'b00000, "1.00097656 - 1.0 = 2^-10");
        run_op(OP_SUB, 16'h3C00, 16'h3C00, 16'h0000, 5'b10000, "1.0 - 1.0 = +0");

        // Subnormals in ADD
        run_op(OP_ADD, 16'h03FF, 16'h0001, 16'h0400, 5'b00000, "max_sub + min_sub = min_norm");
        run_op(OP_ADD, 16'h0200, 16'h0100, 16'h0300, 5'b00000, "subnormal + subnormal");

        // Basic MUL
        run_op(OP_MUL, 16'h4000, 16'h4200, 16'h4600, 5'b00000, "2.0 * 3.0 = 6.0");
        run_op(OP_MUL, 16'hBE00, 16'h4000, 16'hC200, 5'b00000, "-1.5 * 2.0 = -3.0");
        run_op(OP_MUL, 16'h3800, 16'h3800, 16'h3400, 5'b00000, "0.5 * 0.5 = 0.25");

        // Overflow & Underflow
        run_op(OP_ADD, 16'h7BFF, 16'h7BFF, 16'h7C00, 5'b01010, "max + max -> +Inf (ovf)");
        run_op(OP_MUL, 16'h7BFF, 16'h4000, 16'h7C00, 5'b01010, "max * 2.0 -> +Inf (ovf)");
        run_op(OP_MUL, 16'h0400, 16'h3800, 16'h0200, 5'b00001, "min_norm * 0.5 -> subnormal (udf)");
        run_op(OP_MUL, 16'h0001, 16'h0001, 16'h0000, 5'b10001, "min_sub * min_sub -> +0 (udf)");

        // Special values: Inf, NaN, Zero, ABS
        run_op(OP_ADD, 16'h7C00, 16'hFC00, 16'h7E00, 5'b00100, "+Inf + -Inf -> qNaN");
        run_op(OP_MUL, 16'h0000, 16'h7C00, 16'h7E00, 5'b00100, "0 * +Inf -> qNaN");
        run_op(OP_ADD, 16'h7E01, 16'h3C00, 16'h7E00, 5'b00100, "NaN + 1.0 -> qNaN");
        run_op(OP_ABS, 16'hC000, 16'h0000, 16'h4000, 5'b00000, "ABS(-2.0) = 2.0");

        // Back-to-back pipelined throughput test (1 op/cycle)
        @(negedge clk);
        op_sel = OP_ADD; a_in = 16'h3C00; b_in = 16'h3C00; in_valid = 1'b1; // 1+1=2 (0x4000)
        @(negedge clk);
        op_sel = OP_MUL; a_in = 16'h4000; b_in = 16'h4200; in_valid = 1'b1; // 2*3=6 (0x4600)
        @(negedge clk);
        in_valid = 1'b0;
        #1; // Check first pipelined output right after 2nd posedge
        if (!out_valid || result_out !== 16'h4000) begin
            $display("[FAIL] Pipe op1: got 0x%04h valid=%b | exp 0x4000", result_out, out_valid);
            errors = errors + 1;
        end else begin
            $display("[PASS] Pipe op1: res=0x%04h", result_out);
        end
        @(posedge clk);
        #1;
        if (!out_valid || result_out !== 16'h4600) begin
            $display("[FAIL] Pipe op2: got 0x%04h valid=%b | exp 0x4600", result_out, out_valid);
            errors = errors + 1;
        end else begin
            $display("[PASS] Pipe op2: res=0x%04h", result_out);
        end

        if (errors == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("FAILED with %0d error(s).", errors);

        $finish;
    end

endmodule
