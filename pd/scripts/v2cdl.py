import re, sys
src, top, out, libs = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
pins = {}
for lib in libs:
    for line in open(lib, errors="replace"):
        t = line.split()
        if len(t) > 1 and t[0].upper() == ".SUBCKT":
            pins[t[1]] = [p for p in t[2:] if "=" not in p]
def clean(n):
    n = n.strip()
    return (n[1:] if n.startswith("\\") else n).replace(" ", "")
text = re.sub(r"/\*.*?\*/", "", re.sub(r"//.*", "", open(src).read()), flags=re.S)
body = re.search(r"\bmodule\s+" + re.escape(top) + r"\b(.*?)\bendmodule", text, re.S).group(1)
ports = []
for kind, rng, names in re.findall(r"\b(input|output|inout)\s*(\[\s*\d+\s*:\s*\d+\s*\])?\s*([^;]+);", body):
    for n in names.split(","):
        n = clean(n)
        if not n: continue
        if rng:
            hi, lo = map(int, re.findall(r"\d+", rng)); st = -1 if hi >= lo else 1
            ports += ["%s[%d]" % (n, i) for i in range(hi, lo + st, st)]
        else:
            ports.append(n)
for pg in ("VDD", "VSS"):
    if pg not in ports: ports.append(pg)
lines, skipped, dang = [], {}, 0
for s in body.split(";"):
    mi = re.match(r"^\s*([A-Za-z_][\w$]*)\s+(\\\S+\s|[A-Za-z_][\w$\[\]]*)\s*\((.*)\)\s*$", s, re.S)
    if not mi or mi.group(1) in ("input", "output", "inout", "wire", "assign"): continue
    cell, inst, conns = mi.group(1), clean(mi.group(2)), mi.group(3)
    if cell not in pins:
        skipped[cell] = skipped.get(cell, 0) + 1; continue
    net = {}
    for p, n in re.findall(r"\.([\w$]+)\s*\(\s*((?:\\\S+\s)|[^()]*?)\s*\)", conns):
        n = clean(n); net[p] = {"1'b0": "VSS", "1'b1": "VDD"}.get(n, n)
    nodes = []
    for p in pins[cell]:
        n = net.get(p, "")
        if not n: dang += 1; n = "dangling_%d" % dang
        nodes.append(n)
    lines.append("X%s %s %s" % (inst, " ".join(nodes), cell))
with open(out, "w") as f:
    for lib in libs: f.write('.INCLUDE "%s"\n' % lib)
    f.write("\n.SUBCKT %s %s\n" % (top, " ".join(ports)))
    f.write("\n".join(lines) + "\n.ENDS %s\n" % top)
print("wrote %s: %d instances, %d ports" % (out, len(lines), len(ports)))
for c, k in sorted(skipped.items()): print("  no CDL for %s (%d skipped)" % (c, k))
