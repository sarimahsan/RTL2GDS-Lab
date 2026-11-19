TOP ?= top
SRC := $(wildcard src/*.v)
TB  := $(wildcard tb/*.v)
SIM_OUT := sim.vvp
VCD_OUT := dump.vcd

OPENLANE_IMAGE ?= ghcr.io/efabless/openlane2:2.3.10
PDK_ROOT_HOST  ?= $(HOME)/.volare

.PHONY: all sim wave gds clean

all: sim

sim:
	iverilog -g2012 -Wall -o $(SIM_OUT) $(SRC) $(TB)
	vvp $(SIM_OUT)

wave: sim
	gtkwave $(VCD_OUT) &

gds:
	docker run --rm \
		-u $$(id -u):$$(id -g) \
		-e HOME=/tmp \
		-e PDK_ROOT=/pdk \
		-v "$(CURDIR)":/work \
		-v "$(PDK_ROOT_HOST)":/pdk \
		-w /work \
		$(OPENLANE_IMAGE) \
		openlane config.json

clean:
	rm -f $(SIM_OUT) $(VCD_OUT)
	rm -rf runs/
