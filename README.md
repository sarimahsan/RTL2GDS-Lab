# RTL2GDS-Lab

A collection of **Verilog → OpenLane 2 (`sky130A`) GDSII** digital ASIC designs.

## Chips

- [01 — Horner's Rule Serial Radix Converter (`w01_horner_converter`)](./chips/w01_horner_converter/README.md)

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
