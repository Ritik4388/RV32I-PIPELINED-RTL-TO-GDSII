proc knob {name default} {
  global env
  if {[info exists env($name)] && $env($name) ne ""} { return $env($name) }
  return $default
}

set DESIGN      riscv_core
set CLK_PORT    clk
set RST_PORT    rst_n
set CLK_PERIOD  [knob CLK_PERIOD 20.0]
set UTIL        [knob UTIL 0.40]
set BP_ENTRIES  [knob BP_ENTRIES 64]
set BP_ENABLE   [knob BP_ENABLE 1]

set CORE_MARGIN 12.0
set RING_WIDTH  2.0
set RING_SPACE  1.8
set STRIPE_WIDTH 1.6
set STRIPE_PITCH 60.0
set TAP_INTERVAL 25.0

set PD_DIR  [file normalize [file dirname [info script]]]
set RTL_DIR [file normalize $PD_DIR/../rtl]
set RTL_FILES [list \
  $RTL_DIR/riscv_pkg.sv \
  $RTL_DIR/decoder.sv \
  $RTL_DIR/regfile.sv \
  $RTL_DIR/alu.sv \
  $RTL_DIR/branch_unit.sv \
  $RTL_DIR/forwarding_unit.sv \
  $RTL_DIR/hazard_unit.sv \
  $RTL_DIR/branch_predictor.sv \
  $RTL_DIR/riscv_core.sv]
set OUT_DIR  $PD_DIR/out
set RPT_DIR  $PD_DIR/reports
set SDC_FILE $OUT_DIR/$DESIGN.sdc
source $PD_DIR/constraints/make_sdc.tcl

if {![file exists $PD_DIR/config_auto.tcl]} {
  error "run 'make setup' first, config_auto.tcl is missing"
}
source $PD_DIR/config_auto.tcl
set ROUTE_TOP [knob ROUTE_TOP [llength $ROUTING_LAYERS]]
