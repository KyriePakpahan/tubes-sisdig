#  Implementasi Algoritma Ringan ASCON-CXOF pada FPGA untuk Perangkat dengan Memori dan Fungsionalitas Terbatas
## Proyek Tugas Besar Sistem Digital (EL2002)

[![Lisensi MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

Ini adalah repositori tugas besar kelompok yang berisi desain VHDL dan beberapa utilitas perangkat lunak untuk menguji algoritma Ascon (CXOF) yang digunakan di bagian perangkat lunak.

Anggota Kelompok 2
- 13224006 - Kyrie Eleison Jacob Pakpahan
- 13224005 - Nadine Gabe Ulina Sianturi
- 13224004 - Afdhal Razaq
- 13223012 - Samuel Kristian

## Catatan singkat

- Top-level Makefile mungkin menjalankan tool VHDL (GHDL / Vivado / Quartus). Jika Anda hanya ingin membangun/menjalankan utilitas C (di folder `software/`), gunakan `make -C software` atau target Makefile di `software/`.

## Struktur penting

- `hardware/` — kode VHDL (top-level, testbenches, constraints)
- `software/` — implementasi C Ascon + test runners (lihat `software/README.md`)

## Kontribusi

- Gunakan branch terpisah untuk fitur/perbaikan. Contoh:

```bash
git checkout -b feat/nama-fitur
git add ...
git commit -m "feat: pesan singkat"
    feat: (Feature)
    fix: (Bug Fix)
    refactor: (Refactoring)
    docs: (Documentation)
    test: (Testing) 
    chore: (Chores/Maintenance)
    perf: (Performance)
git push -u origin feat/nama-fitur
```

- Buat pull request untuk review sebelum merge ke `main`.

## Ringkasan cepat: menjalankan utilitas Ascon (CXOF/hash)

1. Build runner CXOF:

```bash
make -C software test-cxof-bits
```

2. Jalankan (message, label, out_bits, optional pa_rounds):

```bash
./software/test_cxof_bits "hello" "kelompok2" 255 12
```

Untuk dokumentasi build/run lebih lengkap lihat `software/README.md`.