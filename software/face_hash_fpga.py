#!/usr/bin/env python3
"""
face_hash_fpga.py

Extract face features from an image and send to FPGA for hashing.
Combines extract_face.py with fpga_serial_test.py.

Usage:
    python face_hash_fpga.py --image face.jpg --port /dev/ttyUSB0

This will:
1. Extract 512-bit face embedding from the image (using ArcFace)
2. Convert embedding to 64-byte hex string (label/Z)
3. Send to FPGA with optional message (M)
4. Receive hash output
"""

import argparse
import sys
import time
from pathlib import Path

# Import face extraction
try:
    from extract_face import extract_face_binary
except ImportError:
    print("Error: extract_face.py not found. Make sure arcface.onnx is available.")
    sys.exit(1)


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
    packet.extend(z_data)        # Z data (face embedding)
    packet.extend(m_data)        # M data (optional message)
    return bytes(packet)


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


def main():
    parser = argparse.ArgumentParser(description='Face Hash FPGA - Extract face and hash with FPGA')
    
    # Image input
    parser.add_argument('--image', '-i', required=True, help='Path to face image')
    
    # Serial port
    parser.add_argument('--port', '-p', help='Serial port (e.g., /dev/ttyUSB0)')
    parser.add_argument('--baud', type=int, default=115200, help='Baud rate (default: 115200)')
    parser.add_argument('--timeout', type=float, default=5.0, help='Serial timeout in seconds')
    
    # Optional message
    parser.add_argument('--msg', default='', help='Optional message to hash with face (M)')
    parser.add_argument('--msg-hex', help='Optional message as hex')
    
    # Output options
    parser.add_argument('--outbytes', type=int, default=32, help='Hash output length (default: 32)')
    parser.add_argument('--dry-run', action='store_true', help='Extract face but skip FPGA communication')
    
    args = parser.parse_args()
    
    # Step 1: Extract face embedding
    print(f"\n{'='*60}")
    print("STEP 1: Extracting face embedding...")
    print(f"{'='*60}")
    
    try:
        face_hex = extract_face_binary(args.image)
        print(f"Face embedding extracted: {len(face_hex)} hex chars ({len(face_hex)//2} bytes)")
        
        # The face embedding is 512 bits = 64 bytes = 128 hex chars
        # But our protocol only supports 255 bytes max for Z
        # 64 bytes is within limit, so we're good
        
        face_bytes = bytes.fromhex(face_hex)
        print(f"First 16 bytes: {face_bytes[:16].hex().upper()}")
        
    except Exception as e:
        print(f"Error extracting face: {e}")
        sys.exit(1)
    
    # Step 2: Prepare message (optional)
    if args.msg_hex:
        msg_bytes = bytes.fromhex(args.msg_hex)
    elif args.msg:
        msg_bytes = args.msg.encode('utf-8')
    else:
        msg_bytes = b''
    
    print(f"\n{'='*60}")
    print("STEP 2: Preparing FPGA packet...")
    print(f"{'='*60}")
    print(f"  Label (Z) = Face embedding: {len(face_bytes)} bytes")
    print(f"  Message (M): {len(msg_bytes)} bytes")
    print(f"  Output length: {args.outbytes} bytes")
    
    packet = build_packet(face_bytes, msg_bytes, args.outbytes)
    print(f"\n  Header: {packet[:3].hex().upper()}")
    print(f"  Total packet size: {len(packet)} bytes")
    
    if args.dry_run:
        print(f"\n{'='*60}")
        print("DRY RUN - Skipping FPGA communication")
        print(f"{'='*60}")
        print(f"\nFull packet (first 64 chars): {packet.hex().upper()[:64]}...")
        return
    
    # Step 3: Send to FPGA
    if not args.port:
        print("\nError: --port is required (use --dry-run to skip FPGA)")
        sys.exit(1)
    
    try:
        import serial
    except ImportError:
        print("Error: pyserial not installed. Run: pip install pyserial")
        sys.exit(1)
    
    print(f"\n{'='*60}")
    print("STEP 3: Sending to FPGA...")
    print(f"{'='*60}")
    
    try:
        ser = serial.Serial(args.port, args.baud, timeout=args.timeout)
        print(f"Opened {args.port} @ {args.baud} baud")
        time.sleep(0.5)  # Give FPGA time to initialize
    except Exception as e:
        print(f"Error opening serial port: {e}")
        sys.exit(1)
    
    try:
        fpga_result = send_to_fpga(ser, face_bytes, msg_bytes, args.outbytes, args.timeout)
        fpga_hex = fpga_result.hex().upper()
    except Exception as e:
        print(f"FPGA Error: {e}")
        ser.close()
        sys.exit(1)
    finally:
        ser.close()
    
    # Step 4: Display result
    print(f"\n{'='*60}")
    print("RESULT: FPGA Face Hash")
    print(f"{'='*60}")
    print(f"\n  Hash ({args.outbytes} bytes):")
    print(f"  {fpga_hex}")
    
    # Save to file
    with open("face_hash_result.txt", "w") as f:
        f.write(f"Image: {args.image}\n")
        f.write(f"Face Embedding (Label): {face_hex}\n")
        f.write(f"Message: {args.msg or args.msg_hex or '(empty)'}\n")
        f.write(f"FPGA Hash: {fpga_hex}\n")
    
    print(f"\n  Result saved to face_hash_result.txt")


if __name__ == '__main__':
    main()
