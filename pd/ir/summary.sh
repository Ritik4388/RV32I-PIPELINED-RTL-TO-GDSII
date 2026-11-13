#!/bin/bash
cd "$(dirname "$0")/.."
echo; echo "================ IR / EM summary ================"
cat reports/ir/steps.txt 2>/dev/null
echo; echo "-- power (typical 1.8 V, 20% activity)"
grep -i -E "total (internal|switching|leakage)? *power|^ *total" reports/ir/power_tt.rpt 2>/dev/null | head -6
echo; echo "-- report files"
find out/ir/results_* -type f \( -name "*.rpt" -o -name "*.worst*" -o -name "*.main*" \) 2>/dev/null | head -30
echo; echo "-- IR per net"
grep -h -A3 "Begin IR Drop (Linear)" out/ir/results_*/*/Reports/*/*.main.rpt logs/ir.log 2>/dev/null | grep -E "Voltage:|Maximum IR" | head -8
echo; echo "-- EM per net"
grep -E "^Net V|Current Density \\(J/JMAX\\)|resistors skipped" logs/ir.log 2>/dev/null | tail -8
echo; echo "-- IR and EM lines"
grep -r -i -h -E "worst|ir drop|ir_drop|average|electromigration|em viol|violation" out/ir/results_* 2>/dev/null \
  | grep -v -i "^ *#" | sort -u | head -40
echo "================================================="
