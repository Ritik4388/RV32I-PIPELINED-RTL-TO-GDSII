source [file normalize [file dirname [info script]]/../pnr/common.tcl]

set IR_OUT $OUT_DIR/ir
set IR_RPT $RPT_DIR/ir
file delete -force $IR_OUT
file mkdir $IR_OUT $IR_RPT

set VDD_V   1.8
set VDD_PIN [lindex $PWR_PINS 0]
set VSS_PIN [lindex $GND_PINS 0]
set ACT     0.2

set status {}
proc run {label body} {
  global status
  puts "\n== IR: $label"
  if {[catch {uplevel 1 $body} msg]} {
    puts "== IR: $label FAILED: $msg"
    lappend status "FAIL  $label : [lindex [split $msg \n] 0]"
    return 0
  }
  lappend status "ok    $label"
  return 1
}
proc done {} {
  global status IR_RPT
  set f [open $IR_RPT/steps.txt w]
  foreach s $status { puts $f $s }
  close $f
  exit
}
proc find1 {dirs pattern} {
  set r ""
  catch {set r [lindex [split [exec sh -c "find $dirs -type f $pattern 2>/dev/null | sort | head -1"] \n] 0]}
  return $r
}

set REL [knob REL /home/install/sky130_release_0.1.0]
set SCL [knob SCL /home/install/sky130_scl_9T_0.1.2]

set qrc $QRC_FILE
if {$qrc eq "" || ![file exists $qrc]} {
  set qrc [find1 "$REL $SCL" {\( -iname 'qrcTech*' -o -iname '*.tch' \)}]
}
set ictem [find1 "$REL $SCL" {-iname '*.ictem'}]
set lefmap ""
if {$qrc ne ""} {
  foreach m [glob -nocomplain [file dirname $qrc]/*] {
    if {[regexp -nocase {lef.*map|map.*lef} [file tail $m]]} { set lefmap $m; break }
  }
}
lappend status "info  qrc tech: [expr {$qrc eq "" ? "NOT FOUND" : $qrc}]"
lappend status "info  em rules: [expr {$ictem eq "" ? "none, limits from tech LEF if present" : $ictem}]"

if {![run restore { restoreDesign $PNR_OUT/06_finish.enc.dat $DESIGN }]} done
connect_pg

run extract {
  setExtractRCMode -engine postRoute -effortLevel [expr {$qrc ne "" ? "medium" : "low"}]
  extractRC
}

proc do_power {full} {
  global IR_OUT IR_RPT CLK_PERIOD ACT
  set_power_output_dir $IR_OUT/power
  catch {set_default_switching_activity -reset}
  set_default_switching_activity -input_activity $ACT -period $CLK_PERIOD
  propagate_activity
  catch {set_power_analysis_mode -reset}
  if {$full} {
    set_power_analysis_mode -method static -analysis_view view_tt -corner max \
      -create_binary_db true -write_static_currents true \
      -honor_negative_energy true -ignore_control_signals true
  } else {
    set_power_analysis_mode -method static -analysis_view view_tt -write_static_currents true
  }
  report_power -outfile $IR_RPT/power_tt.rpt -rail_analysis_format VS
}
if {![run power { do_power 1 }]} { if {![run power_basic { do_power 0 }]} done }

set cur {}
catch {set cur [split [exec sh -c "find $IR_OUT $IR_RPT -name '*.ptiavg' 2>/dev/null"] \n]}
lappend status "info  current files: [llength $cur]"
if {![llength $cur]} done

set pgv ""
if {$qrc ne ""} {
  run pgv {
    catch {set_pg_library_mode -reset}
    set o [list -celltype techonly -extraction_tech_file $qrc \
      -default_power_voltage $VDD_V -power_pins [list $VDD_PIN $VDD_V] -ground_pins $VSS_PIN]
    if {$lefmap ne ""} { lappend o -lef_layermap $lefmap }
    set_pg_library_mode {*}$o
    generate_pg_library -output $IR_OUT/pgv
  }
  catch {set pgv [lindex [split [exec sh -c "find $IR_OUT/pgv -name '*.cl' 2>/dev/null"] \n] 0]}
}

# voltage sources: points along the core ring, like bumps or pads feeding it
proc write_pads {net file} {
  set f [open $file w]
  puts $f "*vsrc_name x y layer"
  set n 0
  set wires [dbGet [dbGet -p top.nets.name $net].sWires]
  foreach pass {ring stripe} {
    if {$n || $wires eq "0x0"} break
    foreach w $wires {
      if {![string match -nocase *$pass* [dbGet $w.shape]]} continue
      set b [dbGet $w.box]
      if {[llength $b] == 1} { set b [lindex $b 0] }
      lassign $b x1 y1 x2 y2
      set ly [dbGet $w.layer.name]
      set horiz [expr {($x2 - $x1) > ($y2 - $y1)}]
      if {$pass eq "ring"} { set fr {0.1 0.3 0.5 0.7 0.9} } else { set fr {0.02 0.98} }
      foreach k $fr {
        if {$horiz} { set x [expr {$x1 + ($x2-$x1)*$k}]; set y [expr {($y1+$y2)/2.0}] } \
        else        { set y [expr {$y1 + ($y2-$y1)*$k}]; set x [expr {($x1+$x2)/2.0}] }
        incr n
        puts $f [format "%s_%d %.3f %.3f %s" $net $n $x $y $ly]
      }
    }
  }
  close $f
  return $n
}
run pads {
  set nv [write_pads VDD $IR_OUT/VDD.pp]
  set ns [write_pads VSS $IR_OUT/VSS.pp]
  if {!$nv || !$ns} { error "no ring or stripe wires found for VDD/VSS" }
  puts "== IR: $nv VDD and $ns VSS sources"
}

proc try_rail {name method opts} {
  global IR_OUT VDD_V cur
  catch {set_rail_analysis_mode -reset}
  set_rail_analysis_mode -method $method {*}$opts
  set_pg_nets -net VDD -voltage $VDD_V -threshold [expr {$VDD_V * 0.95}] -force
  set_pg_nets -net VSS -voltage 0.0 -threshold [expr {$VDD_V * 0.05}] -force
  set_rail_analysis_domain -name core -pwrnets VDD -gndnets VSS
  catch {set_power_pads -reset}
  set_power_pads -net VDD -format xy -file $IR_OUT/VDD.pp
  set_power_pads -net VSS -format xy -file $IR_OUT/VSS.pp
  catch {set_power_data -reset}
  set_power_data -format current -scale 1 $cur
  analyze_rail -type domain -results_directory $IR_OUT/results_$name core
}

# EM numbers land in <net>.rj.avg.rpt only when EM limits were really loaded
proc em_result {name} {
  global IR_OUT
  set out ""
  foreach rpt [glob -nocomplain $IR_OUT/results_$name/*/Reports/*/*.rj.avg.rpt] {
    append out "[lindex [split [file tail $rpt] .] 0] "
  }
  return $out
}

set tries {}
if {$pgv ne ""} {
  set base [list -accuracy xd -analysis_view view_tt -power_grid_library $pgv \
    -extraction_tech_file $qrc -temperature 25 -ignore_shorts true \
    -enable_rlrp_analysis false -vsrc_search_distance 50]
  if {$ictem ne ""} { lappend tries em_ict static [concat $base -em_models $ictem] }
  lappend tries em_lef     static [concat $base -em_models $TLEF]
  lappend tries em_techgen static [concat $base -process_techgen_em_rules true]
  lappend tries ir_only    static $base
  lappend tries ir_basic   static [list -accuracy xd -power_grid_library $pgv -extraction_tech_file $qrc]
}
if {$qrc ne ""} {
  lappend tries ir_era era_static [list -accuracy hd -extraction_tech_file $qrc]
}

set ir_ok 0
foreach {name m o} $tries {
  if {$ir_ok && ![string match em_* $name]} break
  if {[run "rail $name" { try_rail $name $m $o }]} {
    if {!$ir_ok} { lappend status "info  ir results: out/ir/results_$name (method $m)" }
    set ir_ok 1
    set em [em_result $name]
    if {$em ne ""} {
      lappend status "info  em checked with $name: $em"
      break
    }
    lappend status "info  $name ran but no EM numbers"
  }
}
if {!$ir_ok} { lappend status "FAIL  no rail analysis method worked" }
done
