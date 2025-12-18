#!/usr/bin/env python3
"""
send_minimal_binary.py

Send message and label as raw binary to an FPGA over serial using a small,
explicit header so the FPGA can parse lengths. This is a generic example —
adapt the header/endianness to match your FPGA.

Format sent (big-endian):
  4 bytes: ASCII magic 'ASCN' (optional, helps sync)
  2 bytes: msg_len (bytes)
  N bytes: message bytes
  2 bytes: label_len (bytes)
  M bytes: label bytes
  2 bytes: out_bits (unsigned, e.g., 255)

The script supports:
  - --msg and --label as UTF-8 text (default) or hex when --msg-hex/--label-hex set
  - --dry-run to print the resulting payload (hex) without opening serial
  - reading the FPGA reply as raw bytes (calculated from out_bits) and printing
    the received bytes as hex

Usage (dry run):
  python send_minimal_binary.py --dry-run --msg hello --label anjay --outbits 255

Usage (real device):
  source .venv/bin/activate
  python send_minimal_binary.py --port /dev/ttyUSB0 --baud 115200 --msg hello --label anjay --outbits 255
"""

import argparse
import struct
import sys
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--port', help='serial port (e.g., /dev/ttyUSB0)')
    p.add_argument('--baud', type=int, default=115200)
    p.add_argument('--msg', required=True, help='message as text (or hex if --msg-hex)')
    p.add_argument('--label', required=True, help='label as text (or hex if --label-hex)')
    p.add_argument('--msg-hex', action='store_true', help='interpret --msg as hex')
    p.add_argument('--label-hex', action='store_true', help='interpret --label as hex')
    p.add_argument('--outbits', type=int, required=True, help='desired output length in bits')
    p.add_argument('--timeout', type=float, default=2.0, help='serial read timeout (s)')
    p.add_argument('--dry-run', action='store_true', help='print payload and exit (no serial)')
    p.add_argument('--reply-raw', action='store_true', help='expect raw byte reply of length ceil(outbits/8)')
    return p.parse_args()


def to_bytes(s: str, is_hex: bool) -> bytes:
    if is_hex:
        # allow 0x prefix and whitespace
        h = s.strip().lower()
        if h.startswith('0x'):
            h = h[2:]
        h = ''.join(h.split())
        if len(h) % 2:
            h = '0' + h
        return bytes.fromhex(h)
    else:
        return s.encode('utf-8')


def build_payload(msg_b: bytes, label_b: bytes, out_bits: int) -> bytes:
    magic = b'ASCN'
    payload = bytearray()
    payload += magic
    payload += struct.pack('>H', len(msg_b))
    payload += msg_b
    payload += struct.pack('>H', len(label_b))
    payload += label_b
    payload += struct.pack('>H', out_bits & 0xFFFF)
    return bytes(payload)


def main():
    args = parse_args()

    msg_b = to_bytes(args.msg, args.msg_hex)
    label_b = to_bytes(args.label, args.label_hex)
    payload = build_payload(msg_b, label_b, args.outbits)

    if args.dry_run:
        print('Payload length:', len(payload), 'bytes')
        print(payload.hex().upper())
        # also show structured view
        print('\nSTRUCTURED:')
        print("MAGIC:", payload[0:4])
        off = 4
        msg_len = struct.unpack('>H', payload[off:off+2])[0]; off += 2
        print('MSG_LEN:', msg_len)
        print('MSG_HEX:', payload[off:off+msg_len].hex().upper()); off += msg_len
        label_len = struct.unpack('>H', payload[off:off+2])[0]; off += 2
        print('LABEL_LEN:', label_len)
        print('LABEL_HEX:', payload[off:off+label_len].hex().upper()); off += label_len
        out_bits = struct.unpack('>H', payload[off:off+2])[0]
        print('OUT_BITS:', out_bits)
        return

    # runtime: open serial and send
    try:
        import serial
    except Exception:
        print('pyserial is not installed. Activate venv and pip install pyserial')
        sys.exit(2)

    try:
        ser = serial.Serial(args.port, args.baud, timeout=args.timeout)
    except Exception as e:
        print('Could not open serial port', args.port, e)
        sys.exit(2)

    try:
        ser.write(payload)
        ser.flush()
        print(f'Sent {len(payload)} bytes to {args.port}')

        if args.reply_raw:
            # expect raw reply of ceil(out_bits/8) bytes
            import math
            expected = (args.outbits + 7) // 8
            data = ser.read(expected)
            print('Received (hex):', data.hex().upper())
        else:
            # read a single ASCII line reply and print (strip)
            line = ser.readline().decode(errors='ignore').strip()
            print('Received (line):', line)
    finally:
        ser.close()


if __name__ == '__main__':
    main()
