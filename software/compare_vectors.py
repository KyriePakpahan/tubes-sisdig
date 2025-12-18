#!/usr/bin/env python3
"""
compare_vectors.py
Reads software/test_vector.txt and compares expected MD values to the
output from ./test_cxof_bits_hex for each vector (uses pa_rounds=12 by
default). Prints a concise pass/fail report.

Run from repository root:
  cd software && python3 compare_vectors.py
"""
import re
import subprocess
import sys
from pathlib import Path

VTXT = Path(__file__).with_name('test_vector.txt')
BIN = Path(__file__).with_name('test_cxof_bits_hex')

if not VTXT.exists():
    print(f"Missing {VTXT}")
    sys.exit(2)
if not BIN.exists():
    print(f"Missing binary {BIN}; build it first (see Makefile).")
    sys.exit(2)

data = VTXT.read_text()
blocks = re.split(r"(?=Count = )", data)
blocks = [b.strip() for b in blocks if b.strip()]

def extract(block):
    m = re.search(r"Count = (\d+)", block)
    idx = int(m.group(1)) if m else -1
    msg = re.search(r"Msg = (.*)", block)
    z = re.search(r"Z = (.*)", block)
    md = re.search(r"MD = ([0-9A-Fa-f]+)", block)
    return idx, (msg.group(1).strip() if msg else ''), (z.group(1).strip() if z else ''), (md.group(1).strip() if md else '')

failures = []
total = 0

for b in blocks:
    idx, msg_hex, z_hex, md = extract(b)
    if md == '':
        continue
    total += 1
    out_bits = len(md) * 4
    # ensure empty strings are passed as empty (""), shell will see empty arg
    args = [str(BIN), msg_hex if msg_hex is not None else '', z_hex if z_hex is not None else '', str(out_bits), '12']
    try:
        p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=False)
    except Exception as e:
        failures.append((idx, 'EXCEPTION', str(e)))
        continue
    stdout = p.stdout.decode().strip()
    # normalize
    got = re.sub(r"\s+", "", stdout).upper()
    exp = md.upper()
    if got == exp:
        print(f"{idx:3d}: PASS")
    else:
        print(f"{idx:3d}: FAIL")
        print(f"  expected: {exp}")
        print(f"  got:      {got}")
        failures.append((idx, exp, got))

print(f"\nChecked {total} vectors: {len(failures)} failures")
if failures:
    sys.exit(1)
else:
    sys.exit(0)
