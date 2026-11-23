# Week 3: IEEE-754 FP16 Unpack, Align & Normalize Core (`w03_fp16_core`)

**Project:** RTL2GDS-Lab (`Verilog` → `OpenLane 2` / SkyWater 130nm `sky130A`)

---

## 1. Overview

Implemented and verified the Week 3 chip from [RTL2GDS_Roadmap.md](../../docs/RTL2GDS_Roadmap.md): a 2-stage pipelined **IEEE-754 half-precision (FP16 / `binary16`)** arithmetic core (`fp16_core`).

Each 16-bit FP16 operand is formatted as:
- **Sign (`[15]`):** 1 bit
- **Exponent (`[14:10]`):** 5 bits (biased by 15)
- **Fraction (`[9:0]`):** 10 bits

---

## 2. Pipeline Architecture

1. **Stage 1 — Unpack & Align / Multiply Setup:**
   - Decodes `sign`, `exp[4:0]`, and `frac[9:0]`; classifies `Zero`, `Subnormal` (effective exponent `1`, implicit bit `0`), `Inf`, and `NaN`.
   - For `OP_ADD` / `OP_SUB`: orders operands by magnitude (`lg >= sm`), computes `exp_diff`, and right-shifts the smaller mantissa with a sticky bit into a 14-bit `{11-bit mantissa, G, R, S}` format.
   - For `OP_MUL`: computes the 22-bit mantissa product (`11 × 11`) and signed biased exponent sum (`exp_a + exp_b - 15`).
2. **Stage 2 — Execute, LZC Normalize, Round & Pack:**
   - Performs effective add/sub or product normalization via Leading-Zero Count (LZC) — clamped for `ADD`/`SUB` so exponents do not underflow below subnormal exponent `1`.
   - Applies IEEE-754 **Round-to-Nearest-Even (RNE)** (`G & (R | S | LSB)`).
   - Handles overflow to `±Inf` (`flag_ovf`, `flag_inf`), underflow to subnormal or `±0` (`flag_udf`, `flag_zero`), and registers `result_out`, `out_valid`, and status flags.

---

## 3. Supported Operations & Pinout

| `op_sel[1:0]` | Operation | Description |
| :--- | :--- | :--- |
| `00` | `OP_ADD` | IEEE-754 FP16 addition (`a_in + b_in`) |
| `01` | `OP_SUB` | IEEE-754 FP16 subtraction (`a_in - b_in`) |
| `10` | `OP_MUL` | IEEE-754 FP16 multiplication (`a_in * b_in`) |
| `11` | `OP_ABS` | IEEE-754 FP16 absolute value (`|a_in|`, preserves `NaN`) |

- **Control & Handshake:** `clk`, `rst_n`, `in_valid`, `out_valid` (2-cycle latency, 1 op/cycle throughput)
- **Data:** `a_in[15:0]`, `b_in[15:0]`, `result_out[15:0]`
- **Flags:** `flag_zero`, `flag_inf`, `flag_nan`, `flag_ovf`, `flag_udf`

---

## 4. Verification & Testbench Fix

- Created a self-checking testbench (`tb/tb_fp16_core.v`) covering normal `ADD`/`SUB`/`MUL`, LZC cancellation (`1.00097656 - 1.0 = 2^-10`), subnormal addition, overflow to `+Inf`, underflow to subnormal/`+0`, `Inf`/`NaN` exception rules (`+Inf + -Inf → qNaN`, `0 * +Inf → qNaN`), `ABS`, and back-to-back pipelined throughput.
- During initial simulation (`make sim`), 21/22 checks passed. The single mismatch on `1.5 + (-2.0) = -0.5` was a testbench typo expecting `0xBC00` (`-1.0`) instead of `0xB800` (`-0.5`, which the DUT computed correctly). Fixed the expected constant to `16'hB800` and widened `label` from `[199:0]` to `[319:0]` to prevent string truncation.

---

## 5. Files Created

- `chips/w03_fp16_core/src/fp16_core.v` — Synthesizable 2-stage pipelined FP16 core
- `chips/w03_fp16_core/tb/tb_fp16_core.v` — Self-checking Icarus Verilog testbench
- `chips/w03_fp16_core/Makefile` & `chips/w03_fp16_core/config.json` — `iverilog`/`vvp` simulation and OpenLane 2 (`sky130A`) GDSII config
- `chips/w03_fp16_core/README.md` & root `README.md` — Documentation and chip index update
- `chips/w03_fp16_core/w03_fp16_core_report.docx` & `w03_fp16_core_report.md` — Summary reports

---

## 6. Next Steps (WSL)

```bash
cd chips/w03_fp16_core
make sim   # Verify all 22 test cases pass
make gds   # Run OpenLane 2 RTL-to-GDSII flow
```
