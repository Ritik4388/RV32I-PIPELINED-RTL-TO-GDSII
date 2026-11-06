# memory paths: 40% of the clock for the core, 60% for the memory

proc make_sdc {path} {
  global CLK_PERIOD CLK_PORT RST_PORT
  set P $CLK_PERIOD
  set f [open $path w]
  puts $f "create_clock -name clk -period $P \[get_ports $CLK_PORT\]"
  puts $f "set_clock_uncertainty -setup [format %.3f [expr {0.05 * $P}]] \[get_clocks clk\]"
  puts $f "set_clock_uncertainty -hold 0.100 \[get_clocks clk\]"
  puts $f "set_clock_transition 0.3 \[get_clocks clk\]"
  puts $f ""
  puts $f "set_input_delay  [format %.3f [expr {0.6 * $P}]] -clock clk \[get_ports {imem_rdata* dmem_rdata*}\]"
  puts $f "set_output_delay [format %.3f [expr {0.6 * $P}]] -clock clk \[get_ports {imem_addr* dmem_req dmem_we dmem_addr* dmem_be* dmem_wdata*}\]"
  puts $f "set_output_delay [format %.3f [expr {0.2 * $P}]] -clock clk \[get_ports {rvfi_* perf_*}\]"
  puts $f "set_input_delay  [format %.3f [expr {0.2 * $P}]] -clock clk \[get_ports $RST_PORT\]"
  puts $f ""
  puts $f "set_input_transition 0.3 \[remove_from_collection \[all_inputs\] \[get_ports $CLK_PORT\]\]"
  puts $f "set_load 0.02 \[all_outputs\]"
  puts $f "set_max_fanout 20 \[current_design\]"
  puts $f "set_max_transition 1.5 \[current_design\]"
  close $f
}
