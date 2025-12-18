# ASCON-CXOF128 Hardware Implementation

Implementasi VHDL dari algoritma **ASCON-CXOF128** untuk simulasi dan deployment FPGA.

## 📁 Struktur File

| File | Deskripsi |
|------|-----------|
| `ascon_cxof128_core.vhd` | Core module — permutasi Ascon |
| `ascon_cxof128_buffer.vhd` | Buffer module — state machine untuk absorption/squeezing |
| `ascon_cxof128_top.vhd` | Top-level module — integrasi core dan buffer |
| `ascon_serial_top.vhd` | **Serial Protocol Top** — fully automated dengan UART protocol |
| `ascon_fpga_top.vhd` | FPGA top dengan button control (legacy) |
| `ascon_cxof128_uart_top.vhd` | UART wrapper untuk komunikasi serial (legacy) |
| `uart_rx.vhd` | UART receiver module |
| `uart_tx.vhd` | UART transmitter module |

### Testbenches

| File | Deskripsi |
|------|-----------|
| `tb_core_wave.vhd` | Testbench untuk core module |
| `tb_buffer_wave.vhd` | Testbench untuk buffer module |
| `tb_top_wave.vhd` | Testbench untuk top module (sistem lengkap) |
| `tb_ascon.vhd` | Testbench utama |

## 🛠️ Prerequisites

- **GHDL** — VHDL simulator (open-source)
- **GTKWave** — Waveform viewer (opsional, untuk visualisasi)

### Instalasi (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install ghdl gtkwave
```

## 🚀 Menjalankan Simulasi

### Cara Cepat (Script Otomatis)

Jalankan semua simulasi sekaligus:

```bash
cd hardware
chmod +x run_wave_sim.sh
./run_wave_sim.sh
```

Script ini akan:
1. Compile semua module VHDL
2. Jalankan simulasi untuk core, buffer, dan top module
3. Generate file waveform (`.vcd`)

### Cara Manual

#### 1. Compile Core Module

```bash
ghdl -a --std=08 ascon_cxof128_core.vhd
ghdl -a --std=08 tb_core_wave.vhd
ghdl -e --std=08 tb_core_wave
ghdl -r --std=08 tb_core_wave --vcd=core_wave.vcd --stop-time=500ns
```

#### 2. Compile Buffer Module

```bash
ghdl -a --std=08 ascon_cxof128_buffer.vhd
ghdl -a --std=08 tb_buffer_wave.vhd
ghdl -e --std=08 tb_buffer_wave
ghdl -r --std=08 tb_buffer_wave --vcd=buffer_wave.vcd --stop-time=2000ns
```

#### 3. Compile Top Module (Sistem Lengkap)

```bash
ghdl -a --std=08 ascon_cxof128_core.vhd
ghdl -a --std=08 ascon_cxof128_buffer.vhd
ghdl -a --std=08 ascon_cxof128_top.vhd
ghdl -a --std=08 tb_top_wave.vhd
ghdl -e --std=08 tb_top_wave
ghdl -r --std=08 tb_top_wave --vcd=top_wave.vcd --stop-time=3000ns
```

## 📊 Melihat Waveform

Setelah simulasi selesai, buka waveform dengan GTKWave:

```bash
gtkwave core_wave.vcd      # Sinyal core module
gtkwave buffer_wave.vcd    # State machine buffer
gtkwave top_wave.vcd       # Sistem lengkap
```

Atau gunakan file konfigurasi `.gtkw` yang sudah tersedia:

```bash
gtkwave core_wave.vcd core_wave.gtkw
gtkwave buffer_wave.vcd buffer_wave.gtkw
gtkwave top_wave.vcd top_wave.gtkw
```

## 📝 File Output

| File | Deskripsi |
|------|-----------|
| `*.vcd` | Waveform files (Value Change Dump) |
| `*.gtkw` | GTKWave configuration files |
| `*.cf` | GHDL work library |
| `*.log` | Simulation log files |


## 🔌 FPGA Serial Communication Guide

This guide explains how to use the `fpga_serial_test.py` script to communicate with the Ascon-CXOF128 FPGA implementation over UART.

### Prerequisites

1.  **Python 3**: Ensure you have Python 3 installed.
2.  **PySerial**: Install the required Python library:
    ```bash
    pip install pyserial
    ```

### Hardware Setup

1.  Connect your FPGA board to your computer via USB.
2.  Identify the serial port:
    *   **Linux**: Usually `/dev/ttyUSB0` or `/dev/ttyUSB1`.
    *   **Windows**: Usually `COM3`, `COM4`, etc.
    *   **macOS**: Usually `/dev/tty.usbserial-...`.

> **Note**: On Linux, you might need permission to access the serial port:
> ```bash
> sudo chmod 666 /dev/ttyUSB0
> ```

### Usage

The script `fpga_serial_test.py` is located in the `software/` directory.

Must attach port to WSL
##
```bash
    usbipd list
usbipd attach --wsl --busid <BUSID>
```

#### 1. Basic Test (Text Input)
Send a simple text message and label to the FPGA:

```bash
python software/fpga_serial_test.py --port /dev/ttyUSB0 --msg "hello" --label "world" --outbytes 32
```

*   `--msg`: The message payload (M).
*   `--label`: The custom label (Z).
*   `--outbytes`: Number of output bytes requested (default 32).

#### 2. Hexadecimal Input
Send exact byte values using hex strings:

```bash
python software/fpga_serial_test.py --port /dev/ttyUSB0 --msg-hex "48656C6C6F" --label-hex "001122"
```

#### 3. Run Test Vectors
Run a suite of test vectors from a file (e.g., `KAT_cxof128.txt` format):

```bash
python software/fpga_serial_test.py --port /dev/ttyUSB0 --vectors software/test_vector.txt
```

*   `--limit N`: Only run the first N vectors.
*   `--single N`: Only run vector with Count = N.

#### 4. Dry Run (Debug)
See what data *would* be sent without actually opening the serial port:

```bash
python software/fpga_serial_test.py --dry-run --msg "test" --label "test"
```

### Protocol Details

The script communicates using a simple byte-oriented protocol (Big Endian):

**PC to FPGA Request:**
| Field | Size | Description |
| :--- | :--- | :--- |
| `z_len` | 1 byte | Length of Label (Z) in bytes |
| `m_len` | 1 byte | Length of Message (M) in bytes |
| `out_len` | 1 byte | Requested Hash Output Length in bytes |
| `Z Data` | `z_len` | The Label bytes |
| `M Data` | `m_len` | The Message bytes |

**FPGA to PC Response:**
| Field | Size | Description |
| :--- | :--- | :--- |
| `Hash` | `out_len` | The computed hash bytes |

### Troubleshooting

*   **Permission Denied**: Run `sudo chmod 666 /dev/ttyUSB0`.
*   **Timeout**: Ensure the FPGA is programmed and running. Check baud rate match (default 115200).
*   **C Reference Error**: The script tries to compare FPGA output against a C reference (`test_cxof_bits_hex`). Ensure you have built the C software:
    ```bash
    make -C software test-cxof-bits
    ```

## 🔗 Referensi

- [ASCON Official](https://ascon.iaik.tugraz.at/)
- [GHDL Documentation](https://ghdl.github.io/ghdl/)
- [GTKWave Manual](http://gtkwave.sourceforge.net/)
