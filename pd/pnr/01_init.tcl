set step 01_init
set d [step_rpt $step]

set netlist $OUT_DIR/syn/$DESIGN.syn.v
if {![file exists $netlist]} { error "no netlist at $netlist, run 'make syn' first" }

make_mmmc $PNR_OUT/mmmc.tcl

set init_lef_file   [list $TLEF $LEF_STD $LEF_PHY]
set init_verilog    $netlist
set init_top_cell   $DESIGN
set init_pwr_net    VDD
set init_gnd_net    VSS
set init_mmmc_file  $PNR_OUT/mmmc.tcl
init_design

connect_pg
setDesignMode -process 130
soft setDesignMode -topRoutingLayer $ROUTE_TOP -bottomRoutingLayer $ROUTE_BOTTOM

soft checkDesign -all -outdir $d
timing_reports $step prePlace
save_step $step
