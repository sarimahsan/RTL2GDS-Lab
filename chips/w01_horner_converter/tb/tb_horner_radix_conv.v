`timescale 1ns / 1ps

module tb_horner_radix_conv;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg         digit_valid;
    reg         last_digit;
    reg  [3:0]  digit_in;
    reg  [4:0]  base_in;
    wire [15:0] result_out;
    wire        done;
    wire        overflow;
    wire        busy;

    integer errors = 0;

    horner_radix_conv dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .digit_valid (digit_valid),
        .last_digit  (last_digit),
        .digit_in    (digit_in),
        .base_in     (base_in),
        .result_out  (result_out),
        .done        (done),
        .overflow    (overflow),
        .busy        (busy)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task reset_dut;
        begin
            rst_n       = 1'b0;
            start       = 1'b0;
            digit_valid = 1'b0;
            last_digit  = 1'b0;
            digit_in    = 4'd0;
            base_in     = 5'd10;
            repeat (3) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    task start_conv(input [4:0] base);
        begin
            @(negedge clk);
            base_in = base;
            start   = 1'b1;
            @(negedge clk);
            start   = 1'b0;
        end
    endtask

    task send_digit(input [3:0] d, input is_last);
        begin
            @(negedge clk);
            digit_in    = d;
            digit_valid = 1'b1;
            last_digit  = is_last;
            @(negedge clk);
            digit_valid = 1'b0;
            last_digit  = 1'b0;
        end
    endtask

    task check_result(input [15:0] exp_val, input exp_ovf, input [127:0] label);
        begin
            @(posedge done);
            #1;
            if (result_out !== exp_val || overflow !== exp_ovf) begin
                $display("[FAIL] %0s: got result=%0d (0x%04h) ovf=%b, expected %0d (0x%04h) ovf=%b",
                         label, result_out, result_out, overflow, exp_val, exp_val, exp_ovf);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s: result=%0d (0x%04h) ovf=%b",
                         label, result_out, result_out, overflow);
            end
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_horner_radix_conv);

        reset_dut();

        // Test 1: Base 10 "12345" -> 12345
        start_conv(5'd10);
        send_digit(4'd1, 1'b0);
        send_digit(4'd2, 1'b0);
        send_digit(4'd3, 1'b0);
        send_digit(4'd4, 1'b0);
        send_digit(4'd5, 1'b1);
        check_result(16'd12345, 1'b0, "Base10_12345");

        // Test 2: Base 16 "CAFE" -> 0xCAFE
        start_conv(5'd16);
        send_digit(4'hC, 1'b0);
        send_digit(4'hA, 1'b0);
        send_digit(4'hF, 1'b0);
        send_digit(4'hE, 1'b1);
        check_result(16'hCAFE, 1'b0, "Base16_CAFE");

        // Test 3: Base 2 "101101" -> 45
        start_conv(5'd2);
        send_digit(4'd1, 1'b0);
        send_digit(4'd0, 1'b0);
        send_digit(4'd1, 1'b0);
        send_digit(4'd1, 1'b0);
        send_digit(4'd0, 1'b0);
        send_digit(4'd1, 1'b1);
        check_result(16'd45, 1'b0, "Base2_101101");

        // Test 4: Base 8 "777" -> 511
        start_conv(5'd8);
        send_digit(4'd7, 1'b0);
        send_digit(4'd7, 1'b0);
        send_digit(4'd7, 1'b1);
        check_result(16'd511, 1'b0, "Base8_777");

        // Test 5: Overflow Base 10 "70000" -> 0xFFFF, ovf=1
        start_conv(5'd10);
        send_digit(4'd7, 1'b0);
        send_digit(4'd0, 1'b0);
        send_digit(4'd0, 1'b0);
        send_digit(4'd0, 1'b0);
        send_digit(4'd0, 1'b1);
        check_result(16'hFFFF, 1'b1, "Base10_Overflow");

        // Test 6: Invalid digit for Base 8 ('9') -> ovf=1
        start_conv(5'd8);
        send_digit(4'd9, 1'b1);
        check_result(16'hFFFF, 1'b1, "Base8_InvalidDigit");

        repeat (3) @(posedge clk);
        if (errors == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("TESTS FAILED: %0d error(s)", errors);
        $finish;
    end

endmodule
