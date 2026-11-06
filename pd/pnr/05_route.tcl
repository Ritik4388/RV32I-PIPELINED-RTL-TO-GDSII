set step 05_route
set d [step_rpt $step]

soft setNanoRouteMode -routeTopRoutingLayer $ROUTE_TOP -routeBottomRoutingLayer $ROUTE_BOTTOM
setNanoRouteMode -routeWithTimingDriven true
setNanoRouteMode -drouteFixAntenna true
if {$ANTCELL ne ""} {
  soft setNanoRouteMode -routeInsertAntennaDiode true -routeAntennaCellName $ANTCELL
}

routeDesign

if {$QRC_FILE ne ""} {
  setExtractRCMode -engine postRoute -effortLevel medium
} else {
  setExtractRCMode -engine postRoute -effortLevel low
}
setAnalysisMode -analysisType onChipVariation -cppr both

optDesign -postRoute -outDir $d/opt_setup
soft setOptMode -holdTargetSlack 0.05
optDesign -postRoute -hold -outDir $d/opt_hold
connect_pg

timing_reports $step postRoute
save_step $step
