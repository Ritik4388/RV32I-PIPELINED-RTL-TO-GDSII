set step 03_place
set d [step_rpt $step]

# let the placer put the I/O pins on the edge next to the logic that uses them
if {[catch {setPlaceMode -place_global_place_io_pins true}]} { soft setPlaceMode -placeIoPins true }

soft setPlaceMode -place_global_ignore_scan true
placeDesign

if {$TIEHI ne "" && $TIELO ne ""} {
  setTieHiLoMode -cell [list $TIEHI $TIELO] -maxFanout 10
  addTieHiLo -prefix TIE
}

optDesign -preCTS -outDir $d/opt
connect_pg

soft checkPlace $d/check_place.rpt
timing_reports $step preCTS
save_step $step
