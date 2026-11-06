set here [file normalize [file dirname [info script]]]
source $here/common.tcl

set steps {01_init 02_floorplan 03_place 04_cts 05_route 06_finish 07_export}
set from [scan [knob START_FROM 1] %d]
set to   [scan [knob STOP_AFTER 7] %d]

set started 0
foreach s $steps {
  set n [scan [string range $s 0 1] %d]
  if {$n < $from} { set prev $s; continue }
  if {!$started && $n > 1} {
    restoreDesign $PNR_OUT/$prev.enc.dat $DESIGN
  }
  set started 1
  source $here/$s.tcl
  if {$n >= $to} break
}
exit
