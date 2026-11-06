set step 07_export

streamOut $PNR_OUT/$DESIGN.gds \
  -mapFile $MAPFILE -libName DesignLib -units $DBU -mode ALL \
  -merge [list $GDS_STD $GDS_PHY]

saveNetlist $PNR_OUT/$DESIGN.pnr.v
soft saveNetlist -phys -includePowerGround $PNR_OUT/$DESIGN.lvs.v
soft write_sdf -view view_ss $PNR_OUT/$DESIGN.ss.sdf
soft rcOut -rc_corner rc_typ -spef $PNR_OUT/$DESIGN.spef
soft defOut -floorplan -netlist -routing $PNR_OUT/$DESIGN.def
soft write_lef_abstract $PNR_OUT/$DESIGN.lef

puts "\n== GDS: $PNR_OUT/$DESIGN.gds"
puts "== gate netlist for simulation: $PNR_OUT/$DESIGN.pnr.v\n"
