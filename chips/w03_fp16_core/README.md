# Week 3: IEEE-754 FP16 Unpack, Align & Normalize Core

A 2-stage pipelined **IEEE-754 binary16 (FP16)** arithmetic core supporting addition, subtraction, multiplication, and absolute value with subnormal support, leading-zero normalization (LZC), Round-to-Nearest-Even (RNE), and `Inf`/`NaN` exception handling.

## Pipeline Architecture

1. **Stage 1 — Unpack & Align / Multiply Setup:**
   - Decodes `sign`, `exp[4:0]`, `frac[9:0]`, and classifies `Zero`, `Subnormal`, `Inf`, `NaN`.
   - Orders operands by magnitude (`lg >= sm`), computes exponent difference, and right-shifts the smaller mantissa with a sticky bit (`11-bit mantissa + G/R/S`).
   - Computes the 22-bit mantissa product and biased exponent sum for `OP_MUL`.
2. **Stage 2 — Execute, LZC Normalize, RNE Round & Pack:**
   - Performs effective add/sub or product normalization via Leading-Zero Count (LZC).
   - Applies Round-to-Nearest-Even (`G & (R | S | LSB)`), handles subnormal underflow and `Inf` overflow, and registers `result_out` + status flags.

## Operations (`op_sel[1:0]`)

| `op_sel` | Operation | Description |
| :--- | :--- | :--- |
| `00` | `OP_ADD` | IEEE-754 FP16 `a_in + b_in` |
| `01` | `OP_SUB` | IEEE-754 FP16 `a_in - b_in` |
| `10` | `OP_MUL` | IEEE-754 FP16 `a_in * b_in` |
| `11` | `OP_ABS` | IEEE-754 FP16 `|a_in|` |

## Pinout (`fp16_core`)

- `clk`, `rst_n`: Clock & active-low async reset
- `in_valid`: Triggers 2-stage pipeline execution (1 op/cycle throughput)
- `op_sel[1:0]`: Operation selector
- `a_in[15:0]`, `b_in[15:0]`: IEEE-754 FP16 operands
- `result_out[15:0]`, `out_valid`: Registered FP16 result & valid pulse (2-cycle latency)
- `flag_zero`, `flag_inf`, `flag_nan`, `flag_ovf`, `flag_udf`: Status & exception flags

## Run

```bash
make sim   # Compile & run self-checking testbench
make wave  # Open GTKWave
make gds   # Run OpenLane 2 (sky130A) RTL-to-GDSII flow
```
