set step 04_cts
set d [step_rpt $step]

if {[llength $CLKBUFS]} { set_ccopt_property buffer_cells $CLKBUFS }
if {[llength $CLKINVS]} { set_ccopt_property inverter_cells $CLKINVS }
soft set_ccopt_property target_skew 0.3

create_ccopt_clock_tree_spec -file $PNR_OUT/ccopt.spec
ccopt_design

soft report_ccopt_clock_trees -file $d/clock_trees.rpt
soft report_ccopt_skew_groups -file $d/skew_groups.rpt

# the clock is real now, so hold paths show up for the first time
optDesign -postCTS -outDir $d/opt_setup
soft setOptMode -holdTargetSlack 0.05
optDesign -postCTS -hold -outDir $d/opt_hold
connect_pg

timing_reports $step postCTS
save_step $step
