#!/usr/bin/env python3
"""
serial_compare.py

Send test vectors to an FPGA over a serial link, receive the Ascon-CXOF output
as hex from the FPGA, and compare it to the software reference (`test_cxof_bits_hex`).

This script supports two simple text protocols (configurable):

1) Full "lines" protocol (default)

    MSG <hex>\n
    LABEL <hex>\n
    OUTBITS <n>\n
    ROUNDS <n>\n
    GO\n+
2) Minimal "minimal" protocol

    MSG <hex>\n
    LABEL <hex>\n
    OUTBITS <n>\n
    # no rounds/GO required; FPGA should start processing after receiving these

In both cases the FPGA must reply with a single line containing the output hex
(MSB-first) terminated by a newline. If your FPGA uses a different protocol,
adapt the `send_vector()` function or add another protocol option.

Dependencies: pyserial
  pip3 install pyserial

Usage examples:
  # run full vector set in software/test_vector.txt, port /dev/ttyUSB0
  python3 serial_compare.py --port /dev/ttyUSB0 --baud 115200

  # test a single vector index (Count = N in the vector file)
  python3 serial_compare.py --port /dev/ttyUSB0 --baud 115200 --single 1

Note: the local reference binary `test_cxof_bits_hex` must be built first.
      See software/Makefile.
"""

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path


def load_vectors(path):
    text = Path(path).read_text()
    blocks = re.split(r"(?=Count = )", text)
    out = []
    for b in blocks:
        b = b.strip()
        if not b:
            continue
        m = re.search(r"Count = (\d+)", b)
        idx = int(m.group(1)) if m else None
        msg = re.search(r"Msg = (.*)", b)
        z = re.search(r"Z = (.*)", b)
        md = re.search(r"MD = ([0-9A-Fa-f]+)", b)
        out.append({
            'idx': idx,
            'msg_hex': (msg.group(1).strip() if msg else ''),
            'label_hex': (z.group(1).strip() if z else ''),
            'md': (md.group(1).strip() if md else ''),
        })
    return out


def run_local_expected(bin_path, msg_hex, label_hex, out_bits, rounds, timeout=5):
    args = [str(bin_path), msg_hex if msg_hex is not None else '', label_hex if label_hex is not None else '', str(out_bits), str(rounds)]
    p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    if p.returncode != 0:
        raise RuntimeError(f"Local binary failed: {p.stderr.decode().strip()}")
    return p.stdout.decode().strip()


def send_vector(ser, msg_hex, label_hex, out_bits, rounds, proto='lines'):
    """Send a vector over serial and return the raw line response (stripped).
    Supported protocols: 'lines' (full), 'minimal' (msg/label/outbits only).
    """
    if proto == 'lines':
        lines = [f"MSG {msg_hex}\n", f"LABEL {label_hex}\n", f"OUTBITS {out_bits}\n", f"ROUNDS {rounds}\n", "GO\n"]
        for L in lines:
            ser.write(L.encode())
            ser.flush()
            time.sleep(0.01)
        # read a line (blocking with timeout handled by serial)
        resp = ser.readline().decode(errors='ignore').strip()
        return resp
    elif proto == 'minimal':
        # send only the fields you requested: MSG, LABEL, OUTBITS
        lines = [f"MSG {msg_hex}\n", f"LABEL {label_hex}\n", f"OUTBITS {out_bits}\n"]
        for L in lines:
            ser.write(L.encode())
            ser.flush()
            time.sleep(0.01)
        # some FPGA firmwares may start processing immediately; read line reply
        resp = ser.readline().decode(errors='ignore').strip()
        return resp
    else:
        raise ValueError('unknown proto')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--port', required=True, help='/dev/ttyUSB0 or COMx')
    p.add_argument('--baud', type=int, default=115200)
    p.add_argument('--vectors', default='test_vector.txt')
    p.add_argument('--bin', default='test_cxof_bits_hex')
    p.add_argument('--rounds', type=int, default=12)
    p.add_argument('--single', type=int, help='run a single vector index (Count value)')
    p.add_argument('--proto', choices=['lines','minimal'], default='lines', help='serial protocol')
    p.add_argument('--timeout', type=float, default=5.0, help='serial read timeout (s)')
    args = p.parse_args()

    vectors = load_vectors(Path(args.vectors))
    # map by idx for quick lookup
    vmap = {v['idx']: v for v in vectors}
    to_run = []
    if args.single:
        if args.single not in vmap:
            print('Vector not found:', args.single)
            sys.exit(2)
        to_run = [vmap[args.single]]
    else:
        to_run = vectors

    # ensure local binary exists
    bin_path = Path(args.bin)
    if not bin_path.exists():
        print('Local binary not found:', bin_path)
        sys.exit(2)

    try:
        import serial
    except Exception:
        print('pyserial is not installed. Install it inside the virtualenv:')
        print('  cd software && source .venv/bin/activate && pip install pyserial')
        sys.exit(2)

    try:
        ser = serial.Serial(args.port, args.baud, timeout=args.timeout)
    except serial.SerialException as e:
        print(f"Could not open serial port {args.port}: {e}")
        print('Check the device path and permissions (you may need to add your user to dialout).')
        sys.exit(2)

    print(f'Opened {args.port} @ {args.baud}')

    total = 0
    failed = 0
    for v in to_run:
        if v['md'] == '':
            continue
        total += 1
        msg_hex = v['msg_hex']
        label_hex = v['label_hex']
        out_bits = len(v['md']) * 4
        try:
            expected = run_local_expected(bin_path, msg_hex, label_hex, out_bits, args.rounds)
        except Exception as e:
            print(f"{v['idx']:4d}: LOCAL ERROR: {e}")
            failed += 1
            continue

        # send to FPGA and read reply
        try:
            fpga = send_vector(ser, msg_hex, label_hex, out_bits, args.rounds, proto=args.proto)
        except Exception as e:
            print(f"{v['idx']:4d}: SERIAL ERROR: {e}")
            failed += 1
            continue

        # normalize
        got = re.sub(r"\s+", "", fpga).upper()
        exp = re.sub(r"\s+", "", expected).upper()
        if got == exp:
            print(f"{v['idx']:4d}: PASS")
        else:
            print(f"{v['idx']:4d}: FAIL")
            print(f"  expected: {exp}")
            print(f"  fpga:     {got}")
            failed += 1

    ser.close()
    print(f"\nTotal: {total}, Failures: {failed}")
    if failed:
        sys.exit(1)


if __name__ == '__main__':
    main()
