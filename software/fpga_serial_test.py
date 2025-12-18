#!/usr/bin/env python3
"""
fpga_serial_test.py

Test Ascon-CXOF128 FPGA implementation via serial communication.
Sends test data to FPGA, receives hash output, and compares with C reference.

PROTOCOL (Laptop → FPGA):
┌─────────┬─────────┬──────────┬────────────┬────────────┐
│ z_len   │ m_len   │ out_len  │ Z data     │ M data     │
│ 1 byte  │ 1 byte  │ 1 byte   │ z_len bytes│ m_len bytes│
└─────────┴─────────┴──────────┴────────────┴────────────┘

PROTOCOL (FPGA → Laptop):
┌────────────────────────────────────┐
│ Hash output (out_len bytes)        │
└────────────────────────────────────┘

Usage:
    # Single test with text input
    python fpga_serial_test.py --port /dev/ttyUSB0 --msg "hello" --label "world" --outbytes 32

    # Single test with hex input
    python fpga_serial_test.py --port /dev/ttyUSB0 --msg-hex "48656C6C6F" --label-hex "" --outbytes 32

    # Run test vectors from file
    python fpga_serial_test.py --port /dev/ttyUSB0 --vectors test_vector.txt

    # Dry run (no serial, just show packets)
    python fpga_serial_test.py --dry-run --msg "hello" --label "world" --outbytes 32

Dependencies:
    pip install pyserial
"""

import argparse
import subprocess
import sys
import time
import re
from pathlib import Path


def to_bytes(s: str, is_hex: bool) -> bytes:
    """Convert string to bytes (either as UTF-8 text or hex)."""
    if not s:
        return b''
    if is_hex:
        h = s.strip().lower()
        if h.startswith('0x'):
            h = h[2:]
        h = ''.join(h.split())
        if len(h) % 2:
            h = '0' + h
        return bytes.fromhex(h)
    else:
        return s.encode('utf-8')


def build_packet(z_data: bytes, m_data: bytes, out_len: int) -> bytes:
    """Build the protocol packet to send to FPGA."""
    if len(z_data) > 255:
        raise ValueError(f"Z data too long: {len(z_data)} bytes (max 255)")
    if len(m_data) > 255:
        raise ValueError(f"M data too long: {len(m_data)} bytes (max 255)")
    if out_len > 255:
        raise ValueError(f"Output length too large: {out_len} bytes (max 255)")
    
    packet = bytearray()
    packet.append(len(z_data))   # z_len (1 byte)
    packet.append(len(m_data))   # m_len (1 byte)
    packet.append(out_len)       # out_len (1 byte)
    packet.extend(z_data)        # Z data
    packet.extend(m_data)        # M data
    return bytes(packet)


def run_c_reference(bin_path: str, msg_hex: str, label_hex: str, out_bits: int, rounds: int = 12) -> str:
    """Run the C reference implementation and return hex output."""
    args = [str(bin_path), msg_hex or '', label_hex or '', str(out_bits), str(rounds)]
    try:
        p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        if p.returncode != 0:
            raise RuntimeError(f"C reference failed: {p.stderr.decode().strip()}")
        return p.stdout.decode().strip().upper()
    except FileNotFoundError:
        raise RuntimeError(f"C reference binary not found: {bin_path}")


def send_to_fpga(ser, z_data: bytes, m_data: bytes, out_len: int, timeout: float = 5.0) -> bytes:
    """Send data to FPGA and receive hash output."""
    packet = build_packet(z_data, m_data, out_len)
    
    # Clear any pending data
    ser.reset_input_buffer()
    
    # Send packet
    ser.write(packet)
    ser.flush()
    
    # Wait for response
    start_time = time.time()
    received = bytearray()
    
    while len(received) < out_len:
        if time.time() - start_time > timeout:
            raise TimeoutError(f"Timeout waiting for FPGA response (got {len(received)}/{out_len} bytes)")
        
        if ser.in_waiting > 0:
            data = ser.read(ser.in_waiting)
            received.extend(data)
        else:
            time.sleep(0.01)
    
    return bytes(received[:out_len])


def load_vectors(path: str) -> list:
    """Load test vectors from KAT file."""
    text = Path(path).read_text()
    blocks = re.split(r"(?=Count = )", text)
    vectors = []
    
    for b in blocks:
        b = b.strip()
        if not b:
            continue
        
        m = re.search(r"Count = (\d+)", b)
        idx = int(m.group(1)) if m else None
        
        msg = re.search(r"Msg = (.*)", b)
        z = re.search(r"Z = (.*)", b)
        md = re.search(r"MD = ([0-9A-Fa-f]+)", b)
        
        vectors.append({
            'idx': idx,
            'msg_hex': (msg.group(1).strip() if msg else ''),
            'label_hex': (z.group(1).strip() if z else ''),
            'md': (md.group(1).strip() if md else ''),
        })
    
    return vectors


def print_packet_info(z_data: bytes, m_data: bytes, out_len: int):
    """Print packet information for debugging."""
    packet = build_packet(z_data, m_data, out_len)
    print(f"\n{'='*60}")
    print("PACKET INFO:")
    print(f"  Z length:   {len(z_data)} bytes")
    print(f"  M length:   {len(m_data)} bytes")
    print(f"  Out length: {out_len} bytes")
    print(f"  Total packet size: {len(packet)} bytes")
    print(f"\n  Header (hex):  {packet[:3].hex().upper()}")
    if z_data:
        print(f"  Z data (hex):  {z_data.hex().upper()}")
    if m_data:
        print(f"  M data (hex):  {m_data.hex().upper()}")
    print(f"\n  Full packet:   {packet.hex().upper()}")
    print(f"{'='*60}\n")


def main():
    parser = argparse.ArgumentParser(description='Test Ascon-CXOF128 FPGA via serial')
    
    # Serial port options
    parser.add_argument('--port', help='Serial port (e.g., /dev/ttyUSB0 or COM3)')
    parser.add_argument('--baud', type=int, default=115200, help='Baud rate (default: 115200)')
    parser.add_argument('--timeout', type=float, default=5.0, help='Serial timeout in seconds')
    
    # Single test mode
    parser.add_argument('--msg', help='Message as text')
    parser.add_argument('--label', help='Label (Z) as text')
    parser.add_argument('--msg-hex', help='Message as hex')
    parser.add_argument('--label-hex', help='Label (Z) as hex')
    parser.add_argument('--outbytes', type=int, default=32, help='Output length in bytes (default: 32)')
    
    # Vector test mode  
    parser.add_argument('--vectors', help='Path to test vector file')
    parser.add_argument('--single', type=int, help='Run single vector by Count index')
    parser.add_argument('--limit', type=int, help='Limit number of vectors to test')
    
    # Reference binary
    default_bin = './test_cxof_bits_hex' if Path('./test_cxof_bits_hex').exists() else 'test_cxof_bits_hex'
    parser.add_argument('--bin', default=default_bin, help='Path to C reference binary')
    parser.add_argument('--rounds', type=int, default=12, help='Permutation rounds')
    
    # Options
    parser.add_argument('--dry-run', action='store_true', help='Print packet without sending')
    parser.add_argument('--no-compare', action='store_true', help='Skip C reference comparison')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    
    args = parser.parse_args()
    
    # Determine mode
    if args.vectors:
        # Vector test mode
        vectors = load_vectors(args.vectors)
        
        if args.single is not None:
            vectors = [v for v in vectors if v['idx'] == args.single]
            if not vectors:
                print(f"Vector index {args.single} not found")
                sys.exit(1)
        
        if args.limit:
            vectors = vectors[:args.limit]
            
    elif args.msg or args.msg_hex or args.label or args.label_hex:
        # Single test mode
        msg_hex = args.msg_hex if args.msg_hex else (args.msg.encode().hex() if args.msg else '')
        label_hex = args.label_hex if args.label_hex else (args.label.encode().hex() if args.label else '')
        
        vectors = [{
            'idx': 0,
            'msg_hex': msg_hex,
            'label_hex': label_hex,
            'md': '',  # Will compute expected from C reference
        }]
    else:
        # Default test
        print("No input specified. Running default test: msg='', label='', outbytes=32")
        vectors = [{
            'idx': 0,
            'msg_hex': '',
            'label_hex': '',
            'md': '',
        }]
    
    # Dry run mode
    if args.dry_run:
        for v in vectors:
            msg_bytes = bytes.fromhex(v['msg_hex']) if v['msg_hex'] else b''
            label_bytes = bytes.fromhex(v['label_hex']) if v['label_hex'] else b''
            out_len = len(v['md']) // 2 if v['md'] else args.outbytes
            print_packet_info(label_bytes, msg_bytes, out_len)
        return
    
    # Open serial port
    if not args.port:
        print("Error: --port is required (use --dry-run for testing without serial)")
        sys.exit(1)
    
    try:
        import serial
    except ImportError:
        print("Error: pyserial not installed. Run: pip install pyserial")
        sys.exit(1)
    
    try:
        ser = serial.Serial(args.port, args.baud, timeout=args.timeout)
        print(f"Opened {args.port} @ {args.baud} baud")
        time.sleep(0.5)  # Give FPGA time to initialize
    except Exception as e:
        print(f"Error opening serial port: {e}")
        sys.exit(1)
    
    # Run tests
    total = 0
    passed = 0
    failed = 0
    
    try:
        for v in vectors:
            if v['md'] == '' and args.vectors:
                continue  # Skip vectors with no expected output
            
            total += 1
            msg_bytes = bytes.fromhex(v['msg_hex']) if v['msg_hex'] else b''
            label_bytes = bytes.fromhex(v['label_hex']) if v['label_hex'] else b''
            out_len = len(v['md']) // 2 if v['md'] else args.outbytes
            out_bits = out_len * 8
            
            # Skip if data too long
            if len(msg_bytes) > 255 or len(label_bytes) > 255 or out_len > 255:
                print(f"[{v['idx']:4d}] SKIP - data too long for protocol")
                continue
            
            if args.verbose:
                print_packet_info(label_bytes, msg_bytes, out_len)
            
            # Send to FPGA
            try:
                fpga_result = send_to_fpga(ser, label_bytes, msg_bytes, out_len, args.timeout)
                fpga_hex = fpga_result.hex().upper()
                print(f"[{v['idx']:4d}] FPGA GOT: {fpga_hex}") # Print immediately
            except Exception as e:
                print(f"[{v['idx']:4d}] FPGA ERROR: {e}")
                failed += 1
                continue
            
            # Get expected result
            if args.no_compare:
                passed += 1
            else:
                try:
                    if v['md']:
                        expected_hex = v['md'].upper()
                    else:
                        expected_hex = run_c_reference(
                            args.bin, v['msg_hex'], v['label_hex'], out_bits, args.rounds
                        )
                except Exception as e:
                    print(f"[{v['idx']:4d}] C REF ERROR: {e}")
                    failed += 1
                    continue
                
                # Compare
                if fpga_hex == expected_hex:
                    print(f"[{v['idx']:4d}] PASS")
                    passed += 1
                else:
                    print(f"[{v['idx']:4d}] FAIL")
                    print(f"       Expected: {expected_hex}")
                    print(f"       Got:      {fpga_hex}")
                    failed += 1
    
    finally:
        ser.close()
    
    # Summary
    print(f"\n{'='*60}")
    print(f"SUMMARY: {passed}/{total} passed, {failed} failed")
    print(f"{'='*60}")
    
    if failed > 0:
        sys.exit(1)


if __name__ == '__main__':
    main()
