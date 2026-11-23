TOP := signed_arith_unit
SRC := src/signed_arith_unit.v
TB  := tb/tb_signed_arith_unit.v
SIM_OUT := sim.vvp
VCD_OUT := dump.vcd

.PHONY: all sim wave clean

all: sim

sim:
	iverilog -g2012 -Wall -o $(SIM_OUT) $(SRC) $(TB)
	vvp $(SIM_OUT)

wave: sim
	gtkwave $(VCD_OUT) &

clean:
	rm -f $(SIM_OUT) $(VCD_OUT)
