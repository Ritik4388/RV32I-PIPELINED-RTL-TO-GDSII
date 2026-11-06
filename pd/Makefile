export ROUTE_TOP CLK_PERIOD UTIL BP_ENTRIES BP_ENABLE STOP_AFTER START_FROM SCL REL

.PHONY: setup syn pnr lec lec_pnr sta clean

setup:
	bash scripts/setup.sh

config_auto.tcl:
	bash scripts/setup.sh

syn: config_auto.tcl
	@mkdir -p logs
	genus -batch -files syn/genus.tcl -log logs/genus < /dev/null

pnr: config_auto.tcl
	@mkdir -p logs
	innovus -nowin -overwrite -files pnr/run_all.tcl -log logs/innovus < /dev/null

lec:
	@mkdir -p logs reports/lec
	-lec -xl -nogui -dofile out/syn/lec_rtl_vs_syn.do -logfile logs/lec_rtl_vs_syn.log < /dev/null
	@grep -iE "No of (compare|diff|abort|unknown) points|LEC Comparison" reports/lec/rtl_vs_syn.log logs/lec_rtl_vs_syn.log 2>/dev/null | tail -5

lec_pnr:
	@mkdir -p logs reports/lec
	-lec -xl -nogui -dofile out/syn/lec_syn_vs_pnr.do -logfile logs/lec_syn_vs_pnr.log < /dev/null
	@grep -iE "No of (compare|diff|abort|unknown) points|LEC Comparison" reports/lec/syn_vs_pnr.log logs/lec_syn_vs_pnr.log 2>/dev/null | tail -5

sta:
	@mkdir -p logs
	tempus -nowin -files sta/tempus.tcl -log logs/tempus < /dev/null

clean:
	rm -rf out reports logs genus.* innovus.* tempus.* lec.* *.log* *.cmd* fv timingReports .cadence
antenna:
	@mkdir -p logs
	innovus -nowin -overwrite -files pnr/fix_antenna.tcl -log logs/innovus_antenna < /dev/null

