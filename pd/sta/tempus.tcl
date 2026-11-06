source [file normalize [file dirname [info script]]]/../pnr/common.tcl

set rpt $RPT_DIR/sta
file mkdir $rpt

foreach f [list $PNR_OUT/$DESIGN.pnr.v $PNR_OUT/$DESIGN.spef] {
  if {![file exists $f]} { error "missing $f, finish 'make pnr' first" }
}

# antenna diodes have no timing model, give them one with just their input pin
if {$ANTCELL ne ""} {
  set stub $rpt/antenna_stub.lib
  set f [open $stub w]
  puts $f "library(antenna_stub) {
  delay_model : table_lookup ; time_unit : \"1ns\" ; voltage_unit : \"1V\" ;
  current_unit : \"1mA\" ; pulling_resistance_unit : \"1kohm\" ;
  leakage_power_unit : \"1nW\" ; capacitive_load_unit (1,pf) ;
  nom_process : 1 ; nom_voltage : 1.8 ; nom_temperature : 25 ;
  cell($ANTCELL) { area : 0 ; dont_use : true ; pin(A) { direction : input ; capacitance : 0.001 ; } }
}"
  close $f
  lappend LIB_PHY $stub
}
make_mmmc $rpt/mmmc_sta.tcl

set load_netlist_ignore_undefined_cell true
read_view_definition $rpt/mmmc_sta.tcl
read_verilog $PNR_OUT/$DESIGN.pnr.v
set_top_module $DESIGN
read_spef -rc_corner rc_typ $PNR_OUT/$DESIGN.spef

# the clock tree is real now, so use its actual delays
set_interactive_constraint_modes [all_constraint_modes -active]
set_propagated_clock [all_clocks]
set_interactive_constraint_modes {}

if {[catch {set_analysis_mode -analysis_type ocv -cppr both}]} {
  soft setAnalysisMode -analysisType onChipVariation -cppr both
}

update_timing -full

report_analysis_summary > $rpt/summary.rpt
report_timing -late  -max_paths 20 -path_type full_clock > $rpt/setup.rpt
report_timing -early -max_paths 20 -path_type full_clock > $rpt/hold.rpt
report_constraint -all_violators > $rpt/violators.rpt
report_clocks > $rpt/clocks.rpt

puts "\n== sign-off timing done: read $rpt/summary.rpt (setup and hold WNS must be >= 0)\n"
exit
