#!/usr/bin/env python3
"""
Interactive / CLI runner for the Week 3 fp16_core Verilog RTL.
Encodes two decimal numbers to IEEE-754 FP16 hex, runs iverilog/vvp on
src/fp16_core.v, and decodes the hardware output back to decimal.

Usage:
  python3 fp16_calc.py <op> <a> [b]
    op: add (+), sub (-), mul (*), abs
  Example:
    python3 fp16_calc.py add 1.5 2.25
    python3 fp16_calc.py mul -1.5 2.0
    python3 fp16_calc.py abs -3.5
  Or run with no arguments for interactive mode.
"""

import os
import re
import struct
import subprocess
import sys
import tempfile

OP_MAP = {
    "add": 0b00, "+": 0b00,
    "sub": 0b01, "-": 0b01,
    "mul": 0b10, "*": 0b10, "x": 0b10,
    "abs": 0b11,
}


def float_to_fp16_bits(val: float) -> int:
    try:
        return struct.unpack(">H", struct.pack(">e", val))[0]
    except OverflowError:
        return 0x7C00 if val > 0 else 0xFC00


def fp16_bits_to_float(bits: int) -> float:
    return struct.unpack(">e", struct.pack(">H", bits))[0]


def run_rtl(op_code: int, a_bits: int, b_bits: int) -> tuple[int, str]:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    rtl_path = os.path.join(script_dir, "src", "fp16_core.v")

    tb_code = f"""`timescale 1ns / 1ps
module tb_cli;
    reg         clk = 0;
    reg         rst_n = 0;
    reg         in_valid = 0;
    reg  [1:0]  op_sel = 2'b{op_code:02b};
    reg  [15:0] a_in = 16'h{a_bits:04x};
    reg  [15:0] b_in = 16'h{b_bits:04x};
    wire [15:0] result_out;
    wire        flag_zero, flag_inf, flag_nan, flag_ovf, flag_udf, out_valid;

    fp16_core dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .op_sel(op_sel), .a_in(a_in), .b_in(b_in),
        .result_out(result_out),
        .flag_zero(flag_zero), .flag_inf(flag_inf), .flag_nan(flag_nan),
        .flag_ovf(flag_ovf), .flag_udf(flag_udf), .out_valid(out_valid)
    );

    always #5 clk = ~clk;

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(negedge clk);
        in_valid = 1;
        @(posedge clk); // Stage 1
        @(negedge clk);
        in_valid = 0;
        @(posedge clk); // Stage 2
        #1;
        $display("RTL_OUT res=%04x flags=%b%b%b%b%b valid=%b",
                 result_out, flag_zero, flag_inf, flag_nan, flag_ovf, flag_udf, out_valid);
        $finish;
    end
endmodule
"""
    with tempfile.TemporaryDirectory() as tmpdir:
        tb_file = os.path.join(tmpdir, "tb_cli.v")
        vvp_file = os.path.join(tmpdir, "cli.vvp")
        with open(tb_file, "w", encoding="utf-8") as f:
            f.write(tb_code)

        subprocess.run(
            ["iverilog", "-g2012", "-o", vvp_file, rtl_path, tb_file],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        res = subprocess.run(
            ["vvp", vvp_file],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

    m = re.search(r"RTL_OUT res=([0-9a-fA-F]{4}) flags=([01]{5}) valid=([01])", res.stdout)
    if not m or m.group(3) != "1":
        raise RuntimeError(f"Unexpected RTL output:\n{res.stdout}")
    return int(m.group(1), 16), m.group(2)


def run_once(op_str: str, a_val: float, b_val: float) -> None:
    op_key = op_str.lower()
    if op_key not in OP_MAP:
        raise ValueError(f"Unsupported op '{op_str}'. Use: add, sub, mul, abs")

    op_code = OP_MAP[op_key]
    a_bits = float_to_fp16_bits(a_val)
    b_bits = float_to_fp16_bits(b_val)

    res_bits, flags = run_rtl(op_code, a_bits, b_bits)
    res_val = fp16_bits_to_float(res_bits)

    flag_names = [
        name for bit, name in zip(flags, ["ZERO", "INF", "NAN", "OVF", "UDF"]) if bit == "1"
    ]
    flag_str = ", ".join(flag_names) if flag_names else "NONE"

    print(f"Input A : {fp16_bits_to_float(a_bits)} (0x{a_bits:04X})")
    if op_code != 0b11:
        print(f"Input B : {fp16_bits_to_float(b_bits)} (0x{b_bits:04X})")
    print(f"RTL Out : {res_val} (0x{res_bits:04X}) | Flags: {flag_str} [{flags}]")


def main() -> None:
    if len(sys.argv) >= 3:
        op_str = sys.argv[1]
        a_val = float(sys.argv[2])
        b_val = float(sys.argv[3]) if len(sys.argv) >= 4 else 0.0
        run_once(op_str, a_val, b_val)
        return

    print("FP16 Core RTL Calculator (type 'quit' to exit)")
    print("Format: <op> <a> [b]   where op = add | sub | mul | abs")
    while True:
        try:
            line = input("\nfp16> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not line or line.lower() in {"q", "quit", "exit"}:
            break
        parts = line.split()
        if len(parts) < 2:
            print("Usage: <op> <a> [b]")
            continue
        try:
            op_str = parts[0]
            a_val = float(parts[1])
            b_val = float(parts[2]) if len(parts) >= 3 else 0.0
            run_once(op_str, a_val, b_val)
        except Exception as exc:
            print(f"Error: {exc}")


if __name__ == "__main__":
    main()
