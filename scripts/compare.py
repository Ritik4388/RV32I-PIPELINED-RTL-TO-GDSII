#!/usr/bin/env python3
import argparse
import re
import sys

LINE_RE = re.compile(r"core\s+\d+:\s+\d+\s+0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)(.*)")

def parse(path, tohost, start=0x80000000):
    out = []
    with open(path, errors="replace") as f:
        for raw in f:

            raw = re.sub(r"\bx\s+(\d+)\b", r"x\1", raw)
            m = LINE_RE.match(raw.strip())
            if not m:
                continue
            pc = int(m.group(1), 16) & 0xFFFFFFFF
            if pc < start:
                continue
            insn = int(m.group(2), 16)
            toks = m.group(3).split()
            rd = store = None
            i = 0
            while i < len(toks):
                t = toks[i]
                if re.fullmatch(r"x\d+", t) and i + 1 < len(toks):
                    r, v = int(t[1:]), int(toks[i + 1], 16) & 0xFFFFFFFF
                    if r != 0:
                        rd = (r, v)
                    i += 2
                elif t == "mem" and i + 1 < len(toks):
                    addr = int(toks[i + 1], 16) & 0xFFFFFFFF

                    if i + 2 < len(toks) and toks[i + 2].startswith("0x"):
                        store = (addr, int(toks[i + 2], 16))
                        i += 3
                    else:
                        i += 2
                else:
                    i += 1
            out.append({"pc": pc, "insn": insn, "rd": rd, "store": store})
            if store and store[0] == tohost:
                break
    return out

def fmt(e):
    s = "pc=0x%08x insn=0x%08x" % (e["pc"], e["insn"])
    if e["rd"]:
        s += " x%d=0x%08x" % e["rd"]
    if e["store"]:
        s += " mem[0x%08x]=0x%x" % e["store"]
    return s

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spike")
    ap.add_argument("rtl")
    ap.add_argument("--tohost", type=lambda x: int(x, 16), required=True)
    a = ap.parse_args()

    iss = parse(a.spike, a.tohost)
    rtl = parse(a.rtl, a.tohost)
    if not iss or iss[-1]["store"] is None or iss[-1]["store"][0] != a.tohost:
        print("[COMPARE] WARNING: Spike never reached tohost - comparing the "
              "%d instructions it did retire" % len(iss))

    for n, (s, r) in enumerate(zip(iss, rtl)):
        if s != r:
            print("[COMPARE] MISMATCH at retired instruction #%d" % n)
            for k in range(max(0, n - 5), n):
                print("   ok    " + fmt(rtl[k]))
            print("   spike " + fmt(s))
            print("   rtl   " + fmt(r))
            return 1

    if len(iss) != len(rtl):
        print("[COMPARE] LENGTH MISMATCH spike=%d rtl=%d" % (len(iss), len(rtl)))
        longer = iss if len(iss) > len(rtl) else rtl
        print("   first extra: " + fmt(longer[min(len(iss), len(rtl))]))
        return 1
    if not rtl or rtl[-1]["store"] is None or rtl[-1]["store"][0] != a.tohost:
        print("[COMPARE] RTL never reached tohost")
        return 1

    print("[COMPARE] PASS - %d instructions matched" % len(rtl))
    return 0

if __name__ == "__main__":
    sys.exit(main())
