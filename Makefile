CROSS   ?= riscv64-unknown-elf-
CC      ?= $(CROSS)gcc
OBJCOPY ?= $(CROSS)objcopy
NM      ?= $(CROSS)nm
SPIKE   ?= spike
RISCV_DV_ROOT ?= $(HOME)/riscv-dv
CFLAGS  ?= -march=$(MARCH) -mabi=ilp32 -static -mcmodel=medany \
           -nostdlib -nostartfiles -Wl,--no-relax

ifeq ($(origin CC),default)
CC := $(CROSS)gcc
endif

# newer gcc needs rv32i_zicsr for csrr, older gcc only knows rv32i
MARCH ?= $(shell echo | $(CC) -march=rv32i_zicsr -mabi=ilp32 -x assembler -c - -o /dev/null 2>/dev/null && echo rv32i_zicsr || echo rv32i)

SIMULATOR ?= verilator
SRC  ?= tests/hazards.S
NAME := $(basename $(notdir $(SRC)))
OUT  := out/$(NAME)
VCD  ?= 0
SHM  ?= 0
MAX_CYCLES ?= 2000000
SPIKE_TIMEOUT ?= 60
GATE ?= 0

RTL := $(shell cat files.f)

ifneq ($(GATE),0)
  ifneq ($(SIMULATOR),xcelium)
    $(error gate-level simulation needs SIMULATOR=xcelium)
  endif
  NETLIST := $(if $(filter pnr,$(GATE)),pd/out/pnr/riscv_core.pnr.v,pd/out/syn/riscv_core.syn.v)
  CELL_V  := $(shell awk '/^set VLOG_STD/{print $$3}' pd/config_auto.tcl 2>/dev/null)
  OUT     := out/$(NAME)_$(GATE)
  SIM     := xcelium_$(GATE).d/.built
  RUN_SIM := xrun -R -64bit -q -xmlibdirpath $(CURDIR)/xcelium_$(GATE).d -l sim.log
else ifeq ($(SIMULATOR),xcelium)
  SIM     := xcelium.d/.built
  RUN_SIM := xrun -R -64bit -q -xmlibdirpath $(CURDIR)/xcelium.d -l sim.log
else ifeq ($(SIMULATOR),verilator)
  SIM     := obj_dir/Vtb_top
  RUN_SIM := $(CURDIR)/obj_dir/Vtb_top
else
  $(error SIMULATOR must be verilator or xcelium)
endif

.PHONY: all test regress clean

all: $(SIM)

obj_dir/Vtb_top: $(RTL) files.f
	verilator --binary --timing --timescale 1ns/1ps -j 0 -Wno-fatal -Wno-lint -Wno-style \
	    --top-module tb_top -f files.f -o Vtb_top

xcelium.d/.built: $(RTL) files.f
	@mkdir -p xcelium.d
	xrun -64bit -sv -q -elaborate -access +r -timescale 1ns/1ps \
	    +define+XCELIUM -top tb_top -f files.f \
	    -xmlibdirpath $(CURDIR)/xcelium.d -l xcelium.d/compile.log
	@touch $@

xcelium_syn.d/.built xcelium_pnr.d/.built: $(wildcard $(NETLIST)) tb/tb_top.sv rtl/riscv_pkg.sv
	@[ -f "$(NETLIST)" ] || { echo "no netlist $(NETLIST), run make in pd/ first"; exit 1; }
	@[ -f "$(CELL_V)" ]  || { echo "cell models not found, run 'make setup' in pd/"; exit 1; }
	@mkdir -p $(dir $@)
	xrun -64bit -sv -q -elaborate -access +r -timescale 1ns/1ps -nospecify -notimingchecks \
	    +define+XCELIUM +define+GATE_SIM -top tb_top \
	    -v $(CELL_V) tb/phys_cells.v $(NETLIST) rtl/riscv_pkg.sv tb/tb_top.sv \
	    -xmlibdirpath $(CURDIR)/$(dir $@) -l $(dir $@)compile.log
	@touch $@

$(OUT)/test.elf: $(SRC) tests/link.ld
	@mkdir -p $(OUT)
	$(CC) $(CFLAGS) -I$(RISCV_DV_ROOT)/user_extension -T tests/link.ld $(SRC) -o $@

$(OUT)/test.hex: $(OUT)/test.elf
	$(OBJCOPY) -O binary $< $(OUT)/test.bin
	python3 scripts/bin2hex.py $(OUT)/test.bin $@

test: $(SIM) $(OUT)/test.hex
	@TOHOST=$$($(NM) $(OUT)/test.elf | awk '/ tohost$$/{print $$1}'); \
	echo "== $(NAME) [$(SIMULATOR)]: tohost=0x$$TOHOST"; \
	timeout $(SPIKE_TIMEOUT) $(SPIKE) --isa=rv32i --log-commits --log=$(OUT)/spike.log $(OUT)/test.elf < /dev/null || \
	  echo "[SPIKE] did not finish in $(SPIKE_TIMEOUT)s - the program probably traps (e.g. misaligned access); bare mode has no trap handler"; \
	cd $(OUT) && $(RUN_SIM) +hex=test.hex +tohost=$$TOHOST +trace=rtl_trace.log \
	    +max_cycles=$(MAX_CYCLES) $(if $(filter 1,$(VCD)),+vcd) $(if $(filter 1,$(SHM)),+shm) \
	    < /dev/null | grep -E '^\[TB\]|\*E|\*F|%Error'; \
	cd $(CURDIR) && python3 scripts/compare.py $(OUT)/spike.log $(OUT)/rtl_trace.log --tohost $$TOHOST

regress: $(SIM)
	@pass=0; fail=0; \
	for s in $(DV_OUT)/asm_test/*.S; do \
	  if $(MAKE) -s test SRC=$$s > out_$$(basename $$s .S).txt 2>&1 && \
	     grep -q "PASS" out_$$(basename $$s .S).txt; then pass=$$((pass+1)); echo "PASS $$s"; \
	  else fail=$$((fail+1)); echo "FAIL $$s  (see out_$$(basename $$s .S).txt)"; fi; \
	done; echo "== $$pass passed, $$fail failed"; [ $$fail -eq 0 ]

clean:
	rm -rf obj_dir xcelium.d xcelium_syn.d xcelium_pnr.d out out_*.txt xrun.history xrun.log xrun.key .simvision
