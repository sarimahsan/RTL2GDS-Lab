# RTL2GDS-Lab

A collection of **Verilog → OpenLane 2 (`sky130A`) GDSII** digital ASIC designs.

## Repository Structure

```text
RTL2GDS-Lab/
├── chips/          # Self-contained Verilog + OpenLane 2 ASIC designs
├── templates/      # Shared OpenLane 2 config & simulation Makefile
├── .gitignore
└── README.md
```

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
