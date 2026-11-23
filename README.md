# RTL2GDS-Lab

A collection of **Verilog → OpenLane 2 (`sky130A`) GDSII** digital ASIC designs following the [RTL2GDS Roadmap](./docs/RTL2GDS_Roadmap.md).

## Chips

- [01 — Horner's Rule Serial Radix Converter (`w01_horner_converter`)](./chips/w01_horner_converter/README.md)
- [02 — 16-bit Signed Arithmetic & Saturation Unit (`w02_signed_arith_unit`)](./chips/w02_signed_arith_unit/README.md)
- [03 — IEEE-754 FP16 Unpack, Align & Normalize Core (`w03_fp16_core`)](./chips/w03_fp16_core/README.md) — [Report](./chips/w03_fp16_core/w03_fp16_core_report.md) | [Python RTL CLI](./chips/w03_fp16_core/fp16_calc.py)

## Toolchain

- **RTL Simulation:** Icarus Verilog (`iverilog`, `vvp`) + `gtkwave` (or Verilator)
- **RTL-to-GDSII:** OpenLane 2 targeting SkyWater 130nm (`sky130A`)
- **Layout Inspection:** KLayout

## Quick Start (Per Chip)

Copy `templates/config.json` and `templates/Makefile` into a new `chips/<design_name>/` directory, then:

```bash
# 1. Simulate & verify RTL
make sim

# 2. View waveforms
make wave

# 3. Run OpenLane 2 RTL-to-GDSII flow
make gds
```
