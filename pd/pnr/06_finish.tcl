set step 06_finish
set d [step_rpt $step]

if {[llength $DECAPS]}  { addFiller -cell $DECAPS  -prefix DECAP }
if {[llength $FILLERS]} { addFiller -cell $FILLERS -prefix FILLER }
soft ecoRoute -target
connect_pg

verify_drc -limit 10000 -report $d/drc.rpt
verifyConnectivity -type all -error 1000 -report $d/connectivity.rpt
soft verifyProcessAntenna -report $d/antenna.rpt

soft report_power -outfile $d/power.rpt
soft reportGateCount -outfile $d/gate_count.rpt
soft summaryReport -noHtml -outfile $d/summary.rpt
timing_reports $step postRoute
save_step $step
