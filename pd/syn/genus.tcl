source [file normalize [file dirname [info script]]/../config.tcl]

set out $OUT_DIR/syn
set rpt $RPT_DIR/syn
file mkdir $out $rpt $RPT_DIR/lec

proc soft {args} {
  if {[catch {uplevel 1 $args} msg]} { puts "NOTE: skipped '[lindex $args 0] [lindex $args 1]': $msg" }
}

soft set_db information_level 7
soft set_db hdl_error_on_blackbox true

# separate server processes hang on this machine, so use threads in one process only
soft set_db auto_super_thread false
soft set_db super_thread_servers {}
soft set_db max_cpus_per_server 4

read_libs [list $LIB_SS $LIB_PHY]
read_physical -lef [list $TLEF $LEF_STD $LEF_PHY]

read_hdl -sv $RTL_FILES
elaborate $DESIGN
check_design -unresolved > $rpt/check_design.rpt

foreach c [concat $FILLERS $DECAPS $TAPCELL $ENDCAP $ANTCELL] {
  if {$c eq ""} continue
  soft set_db [get_db lib_cells */$c] .dont_use true
}

make_sdc $SDC_FILE
read_sdc $SDC_FILE
report_timing -lint > $rpt/timing_lint.rpt

soft set_db remove_assigns true
soft set_db use_tiehilo_for_const unique

set_db syn_generic_effort medium
set_db syn_map_effort     high
set_db syn_opt_effort     high

syn_generic
syn_map
syn_opt

write_hdl > $out/$DESIGN.syn.v
write_sdc > $out/$DESIGN.syn.sdc
if {[catch {write_sdf -timescale ns > $out/$DESIGN.syn.sdf} m]} { puts "NOTE: no sdf: $m" }

write_do_lec -revised_design $out/$DESIGN.syn.v -logfile $RPT_DIR/lec/rtl_vs_syn.log > $out/lec_rtl_vs_syn.do
write_do_lec -golden_design $out/$DESIGN.syn.v -revised_design $OUT_DIR/pnr/$DESIGN.pnr.v \
             -logfile $RPT_DIR/lec/syn_vs_pnr.log > $out/lec_syn_vs_pnr.do

report_timing -max_paths 10 > $rpt/timing.rpt
report_area > $rpt/area.rpt
report_area -depth 2 > $rpt/area_by_module.rpt
report_gates > $rpt/gates.rpt
report_power > $rpt/power.rpt
report_qor > $rpt/qor.rpt
check_design -all > $rpt/check_design.rpt
if {[catch {report_sequential -deleted > $rpt/deleted_flops.rpt} m]} { puts "NOTE: no deleted-flop report: $m" }

puts "\n== synthesis done: $out/$DESIGN.syn.v"
puts "== read reports/syn/qor.rpt, timing.rpt and area_by_module.rpt\n"
exit
