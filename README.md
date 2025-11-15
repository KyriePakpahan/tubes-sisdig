# Proyek ""
## Tugas Besar Sistem Digital - EL2002

[![Lisensi MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

Proyek ini adalah implementasi ...

###  Anggota Kelompok 2
* 13224006 - Kyrie Eleison Jacob Pakpahan
* 13224005 - Nadine Gabe Ulina Sianturi
* 13224004 - Afdhal Razaq
* 13223012 - Samuel Kristian

#### 2. Kompilasi & Simulasi
1.  **Clone repositori** ini:
    ```bash
    git clone [URL-repo]
    ```
2.  **Buka Proyek:**
    * Buka [Nama Software, misal: Intel].
    * Pilih `Open Project`.
    * Arahkan ke file proyek `[nama-file-proyek].xpr` (untuk Vivado) atau `[nama-file-proyek].qpf` (untuk Quartus) yang ada di dalam folder yang sudah di-clone.
3.  **Jalankan Simulasi:**
    * Di panel *Flow Navigator*, temukan dan klik `Run Simulation`.
    * Pilih `Run Behavioral Simulation`.
    * File *testbench* utama yang digunakan adalah `[nama_file_testbench_utama]_tb.vhd`.
4.  **Sintesis & Implementasi (Opsional - Jika deploy ke board):**
    * Di panel *Flow Navigator*, klik `Run Synthesis`.
    * Setelah selesai, klik `Run Implementation`.
    * Terakhir, klik `Generate Bitstream` untuk membuat file `.bit` yang siap di-upload ke FPGA.