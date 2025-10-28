#!/usr/bin/env python3
import sys
import os

THRESHOLD = float(os.environ.get("COVERAGE_THRESHOLD", "0.90"))
LCOV_PATH = os.environ.get("LCOV_FILE", "lcov.info")

INCLUDE_PREFIXES = [
    "src/core/",
    "src/bridge/",
    "src/satellite/",
    "src/oracle/",
    "src/risk/",
    "src/finance/",
]
EXCLUDE_PREFIXES = [
    "src/examples/",
    "src/faucet/",
    "src/tokens/",
    "src/Counter.sol",
    "src/bridge/via/",  # not in beta audit scope
    "script/",
    "test/",
    "lib/",
]

def want_file(sf: str) -> bool:
    # must start with allowed prefixes and not with excluded prefixes
    if not any(sf.startswith(p) for p in INCLUDE_PREFIXES):
        return False
    if any(sf.startswith(p) for p in EXCLUDE_PREFIXES):
        return False
    return True

def parse_lcov(path):
    totals = {"FNF":0, "FNH":0, "LF":0, "LH":0, "BRF":0, "BRH":0}
    per_file = {}
    with open(path, 'r') as f:
        current_sf = None
        include_current = False
        cur = None
        for raw in f:
            line = raw.strip()
            if line.startswith('SF:'):
                current_sf = line[3:]
                include_current = want_file(current_sf)
                if include_current:
                    cur = per_file.setdefault(current_sf, {"FNF":0, "FNH":0, "LF":0, "LH":0, "BRF":0, "BRH":0})
            elif line == 'end_of_record':
                current_sf = None
                include_current = False
                cur = None
            elif include_current:
                if line.startswith('FNF:'):
                    v = int(line.split(':')[1]); totals["FNF"] += v; cur["FNF"] += v
                elif line.startswith('FNH:'):
                    v = int(line.split(':')[1]); totals["FNH"] += v; cur["FNH"] += v
                elif line.startswith('LF:'):
                    v = int(line.split(':')[1]); totals["LF"] += v; cur["LF"] += v
                elif line.startswith('LH:'):
                    v = int(line.split(':')[1]); totals["LH"] += v; cur["LH"] += v
                elif line.startswith('BRF:'):
                    v = int(line.split(':')[1]); totals["BRF"] += v; cur["BRF"] += v
                elif line.startswith('BRH:'):
                    v = int(line.split(':')[1]); totals["BRH"] += v; cur["BRH"] += v
    return totals, per_file

def pct(num, den):
    if den == 0:
        return 1.0
    return num / den

def main():
    if not os.path.exists(LCOV_PATH):
        print(f"ERROR: lcov file not found at {LCOV_PATH}")
        sys.exit(2)
    t, per_file = parse_lcov(LCOV_PATH)
    line_cov = pct(t["LH"], t["LF"])
    func_cov = pct(t["FNH"], t["FNF"])
    branch_cov = pct(t["BRH"], t["BRF"])
    print(f"Coverage summary: lines={line_cov*100:.2f}% functions={func_cov*100:.2f}% branches={branch_cov*100:.2f}%")
    # Print worst offenders by line coverage (bottom 10)
    files_cov = []
    for sf, m in per_file.items():
        lcov = pct(m["LH"], m["LF"]) if m["LF"] else 1.0
        files_cov.append((lcov, sf, m))
    files_cov.sort(key=lambda x: x[0])
    print("Worst files by line coverage (min to max):")
    for lcov, sf, m in files_cov[:10]:
        print(f" - {sf}: lines={lcov*100:.2f}% (LH/LF={m['LH']}/{m['LF']}), funcs={pct(m['FNH'], m['FNF'])*100 if m['FNF'] else 100:.2f}%, branches={pct(m['BRH'], m['BRF'])*100 if m['BRF'] else 100:.2f}%")
    ok = True
    if line_cov < THRESHOLD:
        print(f"FAIL: line coverage {line_cov*100:.2f}% < {THRESHOLD*100:.0f}%")
        ok = False
    if func_cov < THRESHOLD:
        print(f"FAIL: function coverage {func_cov*100:.2f}% < {THRESHOLD*100:.0f}%")
        ok = False
    if branch_cov < THRESHOLD:
        print(f"FAIL: branch coverage {branch_cov*100:.2f}% < {THRESHOLD*100:.0f}%")
        ok = False
    if not ok:
        sys.exit(1)
    sys.exit(0)

if __name__ == '__main__':
    main()
