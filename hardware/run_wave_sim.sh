#!/bin/bash
# ============================================================================
# ASCON CXOF128 Waveform Simulation Script
# ============================================================================
# This script compiles and runs each testbench to generate VCD waveform files.
# Use GTKWave to view the generated .vcd files: gtkwave <file>.vcd
# ============================================================================

HARDWARE_DIR="$(dirname "$0")"
cd "$HARDWARE_DIR"

echo "============================================"
echo "   ASCON CXOF128 Waveform Simulations"
echo "============================================"
echo ""

# Clean old work files
rm -f *.cf *.vcd 2>/dev/null

# ============================================================================
# 1. CORE MODULE SIMULATION
# ============================================================================
echo "=== 1. CORE MODULE (ascon_cxof128_core) ==="
echo "Compiling..."
ghdl -a --std=08 ascon_cxof128_core.vhd
ghdl -a --std=08 tb_core_wave.vhd
ghdl -e --std=08 tb_core_wave

echo "Running simulation..."
ghdl -r --std=08 tb_core_wave --vcd=core_wave.vcd --stop-time=500ns 2>&1 | head -30

if [ -f core_wave.vcd ]; then
    echo "✓ Generated: core_wave.vcd"
else
    echo "✗ Failed to generate core_wave.vcd"
fi
echo ""

# ============================================================================
# 2. BUFFER MODULE SIMULATION
# ============================================================================
echo "=== 2. BUFFER MODULE (cxof_buffer) ==="
echo "Compiling..."
ghdl -a --std=08 ascon_cxof128_buffer.vhd
ghdl -a --std=08 tb_buffer_wave.vhd
ghdl -e --std=08 tb_buffer_wave

echo "Running simulation..."
ghdl -r --std=08 tb_buffer_wave --vcd=buffer_wave.vcd --stop-time=2000ns 2>&1 | head -40

if [ -f buffer_wave.vcd ]; then
    echo "✓ Generated: buffer_wave.vcd"
else
    echo "✗ Failed to generate buffer_wave.vcd"
fi
echo ""

# ============================================================================
# 3. TOP MODULE SIMULATION
# ============================================================================
echo "=== 3. TOP MODULE (ascon_cxof128_top) ==="
echo "Compiling..."
ghdl -a --std=08 ascon_cxof128_core.vhd
ghdl -a --std=08 ascon_cxof128_buffer.vhd
ghdl -a --std=08 ascon_cxof128_top.vhd
ghdl -a --std=08 tb_top_wave.vhd
ghdl -e --std=08 tb_top_wave

echo "Running simulation..."
ghdl -r --std=08 tb_top_wave --vcd=top_wave.vcd --stop-time=3000ns 2>&1 | head -50

if [ -f top_wave.vcd ]; then
    echo "✓ Generated: top_wave.vcd"
else
    echo "✗ Failed to generate top_wave.vcd"
fi
echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo "============================================"
echo "            SUMMARY"
echo "============================================"
echo ""
echo "Generated waveform files:"
ls -la *.vcd 2>/dev/null || echo "No VCD files found."
echo ""
echo "To view waveforms, run:"
echo "  gtkwave core_wave.vcd   - Core module signals"
echo "  gtkwave buffer_wave.vcd - Buffer state machine"
echo "  gtkwave top_wave.vcd    - Complete system"
echo ""
echo "Or view all at once with different GTKWave instances."
echo "============================================"
