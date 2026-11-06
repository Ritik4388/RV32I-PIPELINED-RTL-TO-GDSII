#!/bin/bash

SCL=${SCL:-/home/install/sky130_scl_9T_0.1.2}
REL=${REL:-/home/install/sky130_release_0.1.0}
OUT=${OUT:-config_auto.tcl}
MAP=${MAP:-sky130_streamout.map}

die() { echo "ERROR: $*"; exit 1; }
need() { [ -f "$1" ] || die "missing $1"; echo "  ok  $1"; }

LIB_SS=$SCL/sky130_scl_9T/lib/sky130_ss_1.62_125_nldm.lib
LIB_TT=$SCL/sky130_scl_9T/lib/sky130_tt_1.8_25_nldm.lib
LIB_PHY=$SCL/sky130_scl_9T_tech/lib/sky130_scl_9T_phyCells.lib
TLEF=$SCL/sky130_scl_9T_tech/lef/sky130_scl_9T.tlef
LEF_STD=$SCL/sky130_scl_9T/lef/sky130_scl_9T.lef
LEF_PHY=$SCL/sky130_scl_9T_tech/lef/sky130_scl_9T_phyCells.lef
GDS_STD=$SCL/sky130_scl_9T/gds/sky130_scl_9T.gds
GDS_PHY=$SCL/sky130_scl_9T_tech/gds/sky130_scl_9T_phyCells.gds
VLOG_STD=$SCL/sky130_scl_9T/verilog/sky130_scl_9T.v
LAYERMAP=$REL/libs/sky130_fd_pr_main/sky130_fd_pr_main.layermap

echo "== files"
for f in $LIB_SS $LIB_TT $LIB_PHY $TLEF $LEF_STD $LEF_PHY $GDS_STD $GDS_PHY $VLOG_STD; do need $f; done

QRC=$(find $REL/quantus -type f -iname "qrcTech*" 2>/dev/null | sort)
QRC_FILE=$(echo "$QRC" | grep -iE "typ|nom|tt" | head -1)
[ -z "$QRC_FILE" ] && QRC_FILE=$(echo "$QRC" | head -1)
echo "  qrc: ${QRC_FILE:-none found, Innovus will use LEF R/C}"

LAYERS=$(awk '
  /^[ \t]*LAYER[ \t]+[^ \t;]+[ \t]*$/ { name=$2; type=""; dir="" ; next }
  name!="" && /^[ \t]*TYPE[ \t]/      { type=$2 }
  name!="" && /^[ \t]*DIRECTION[ \t]/ { dir=$2 }
  name!="" && $1=="END" && $2==name   { if (type=="ROUTING" || type=="CUT") print name, type, (dir==""?"-":dir); name="" }
' $TLEF)
ROUTING=$(echo "$LAYERS" | awk '$2=="ROUTING"{printf "%s ", $1}')
RDIRS=$(echo "$LAYERS" | awk '$2=="ROUTING"{printf "%s ", $3}')
CUTS=$(echo "$LAYERS" | awk '$2=="CUT"{printf "%s ", $1}')
[ -z "$ROUTING" ] && die "no routing layers found in $TLEF"
echo "== layers"
echo "$LAYERS" | sed 's/^/  /'

DBU=$(awk '/DATABASE[ \t]+MICRONS/{print $3; exit}' $TLEF)
DBU=${DBU:-1000}

SITE=$(awk '/^[ \t]*SITE[ \t]+[^ \t]+[ \t]*;/{print $2}' $LEF_STD | sort | uniq -c | sort -rn | awk 'NR==1{print $2}')
[ -z "$SITE" ] && SITE=$(awk '/^SITE[ \t]/{print $2; exit}' $TLEF)
echo "== site: $SITE   dbu: $DBU"

PG=$(awk '
  /^[ \t]*PIN[ \t]+[^ \t;]+[ \t]*$/ { pin=$2 }
  /^[ \t]*USE[ \t]+POWER/  { p[pin]=1 }
  /^[ \t]*USE[ \t]+GROUND/ { g[pin]=1 }
  END { for (k in p) printf "P %s\n", k; for (k in g) printf "G %s\n", k }
' $LEF_STD $LEF_PHY)
PWR_PINS=$(echo "$PG" | awk '$1=="P"{printf "%s ", $2}')
GND_PINS=$(echo "$PG" | awk '$1=="G"{printf "%s ", $2}')
echo "== power pins: $PWR_PINS  ground pins: $GND_PINS"

MACROS=$(awk '
  /^MACRO[ \t]/ { m=$2 }
  m!="" && /^[ \t]*SIZE[ \t]/ { print m, $2; m="" }
' $LEF_STD $LEF_PHY)
pick() { echo "$MACROS" | awk -v re="$1" -v ex="$2" 'toupper($1) ~ re && (ex=="" || toupper($1) !~ ex) {print $2, $1}' | sort -rn | awk '{printf "%s ", $2}'; }

TIEHI=$(pick 'TIE.*(HI|H[0-9_]|HIGH|1)' 'LO')
TIELO=$(pick 'TIE.*(LO|L[0-9_]|LOW|0)' 'HI')
FILLERS=$(pick 'FILL' 'CAP')
DECAPS=$(pick 'DECAP|DCAP|FILLCAP' '')
TAPS=$(pick 'TAP' '')
ENDCAPS=$(pick 'ENDCAP|BOUNDARY' '')
ANTENNA=$(pick 'ANT|DIODE' '')
CLKBUFS=$(pick '^(CLK|CK)BUF' '')
CLKINVS=$(pick '^(CLK|CK)INV' '')
TIEHI=$(echo $TIEHI | awk '{print $NF}')
TIELO=$(echo $TIELO | awk '{print $NF}')
TAPCELL=$(echo $TAPS | awk '{print $NF}')
ENDCAP=$(echo $ENDCAPS | awk '{print $1}')
ANTCELL=$(echo $ANTENNA | awk '{print $NF}')
echo "== cells"
echo "  tie hi/lo : ${TIEHI:-NONE} / ${TIELO:-NONE}"
echo "  fillers   : ${FILLERS:-NONE}"
echo "  decaps    : ${DECAPS:-none}"
echo "  tap       : ${TAPCELL:-none}"
echo "  endcap    : ${ENDCAP:-none}"
echo "  antenna   : ${ANTCELL:-none}"
echo "  clock buf : ${CLKBUFS:-none, CTS picks from all buffers}"
echo "  clock inv : ${CLKINVS:-none}"
[ -z "$FILLERS" ] && echo "  WARNING: no filler cells found, set FILLERS in config.tcl"

# routing plan: skip li1 for signals, keep the top layer for the power ring
set -- $ROUTING; NR=$#
FIRST=$1
if echo "$FIRST" | grep -qi '^li'; then BOT=2; else BOT=1; fi
TOP=$((NR - 1))
LTOP=$(echo $ROUTING | awk '{print $NF}')
LTOP1=$(echo $ROUTING | awk -v n=$((NR-1)) '{print $n}')
DTOP=$(echo $RDIRS | awk '{print $NF}')
if [ "$DTOP" = "HORIZONTAL" ]; then RING_H=$LTOP; RING_V=$LTOP1; else RING_H=$LTOP1; RING_V=$LTOP; fi
STRIPE=$RING_V
echo "== routing: signals on layers $BOT..$TOP, ring $RING_H (horizontal) / $RING_V (vertical), stripes on $STRIPE"

# GDS map: use the PDK layermap when it knows the layer, otherwise sky130 numbers by order
lookup() { [ -f "$LAYERMAP" ] && awk -v l="$1" -v p="$2" '$1==l && $2==p {print $3, $4; exit}' $LAYERMAP; }
{
  i=0
  if [ $BOT -eq 2 ]; then base=67; else base=68; fi
  for L in $ROUTING; do
    n=$((base + i))
    d=$(lookup $L drawing); [ -z "$d" ] && d="$n 20"
    p=$(lookup $L pin);     [ -z "$p" ] && p="${d% *} 16"
    t=$(lookup $L label);   [ -z "$t" ] && t="${d% *} 5"
    for ty in NET SPNET VIA VIAFILL FILL FILLOPC LEFOBS; do echo "$L $ty $d"; done
    echo "$L PIN $p"; echo "$L PIN $d"; echo "$L LEFPIN $p"
    echo "NAME $L/PIN $t"; echo "NAME $L/SPNET $t"
    i=$((i + 1))
  done
  set -- $CUTS; NC=$#
  if [ $NC -ge 5 ]; then cbase=67; else cbase=68; fi
  i=0
  for C in $CUTS; do
    d=$(lookup $C drawing); [ -z "$d" ] && d="$((cbase + i)) 44"
    echo "$C VIA $d"; echo "$C VIAFILL $d"; echo "$C LEFOBS $d"
    i=$((i + 1))
  done
  echo "DIEAREA ALL 235 4"
} > $MAP
echo "== wrote $MAP"

{
  echo "set LIB_SS   $LIB_SS"
  echo "set LIB_TT   $LIB_TT"
  echo "set LIB_PHY  $LIB_PHY"
  echo "set TLEF     $TLEF"
  echo "set LEF_STD  $LEF_STD"
  echo "set LEF_PHY  $LEF_PHY"
  echo "set GDS_STD  $GDS_STD"
  echo "set GDS_PHY  $GDS_PHY"
  echo "set VLOG_STD $VLOG_STD"
  echo "set QRC_FILE \"$QRC_FILE\""
  echo "set SITE     $SITE"
  echo "set DBU      $DBU"
  echo "set ROUTING_LAYERS {$ROUTING}"
  echo "set ROUTE_BOTTOM $BOT"
  echo "set ROUTE_TOP    $TOP"
  echo "set RING_H   $RING_H"
  echo "set RING_V   $RING_V"
  echo "set STRIPE_LAYER $STRIPE"
  echo "set PWR_PINS {$PWR_PINS}"
  echo "set GND_PINS {$GND_PINS}"
  echo "set TIEHI    \"$TIEHI\""
  echo "set TIELO    \"$TIELO\""
  echo "set FILLERS  {$FILLERS}"
  echo "set DECAPS   {$DECAPS}"
  echo "set TAPCELL  \"$TAPCELL\""
  echo "set ENDCAP   \"$ENDCAP\""
  echo "set ANTCELL  \"$ANTCELL\""
  echo "set CLKBUFS  {$CLKBUFS}"
  echo "set CLKINVS  {$CLKINVS}"
  echo "set MAPFILE  [file normalize $MAP]"
} > $OUT
echo "== wrote $OUT"
