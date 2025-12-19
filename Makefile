# ====================================================================
# Makefile Sederhana untuk Proyek VHDL dengan GHDL
# Dibuat untuk: T
# ====================================================================

# --- 1. Konfigurasi Proyek (WAJIB UBAH BAGIAN INI) ---

# Tulis semua file .vhd *desain* Anda di sini, dipisahkan spasi.
# JANGAN masukkan file testbench di sini.
# Gunakan '\' di akhir baris jika daftarnya panjang.
VHDL_SOURCES =  file_modul_1.vhd \
                file_modul_2.vhd \
                file_top_level.vhd

# Nama file testbench Anda
TESTBENCH_FILE = testbench_utama.vhd

# Nama ENTITY dari testbench Anda (penting!)
TESTBENCH_ENTITY = nama_entity_testbench

# Nama file output waveform yang diinginkan
WAVE_FILE = simulation.ghw

# Standar VHDL yang digunakan (misal: 93, 08)
VHDL_STD = --std=08

# ====================================================================
# --- 2. Aturan Makefile (Umumnya tidak perlu diubah) ---

# Gabungkan semua file VHDL
ALL_VHDL_FILES = $(VHDL_SOURCES) $(TESTBENCH_FILE)

# Perintah GHDL
GHDL = ghdl

# Flags untuk GHDL
GHDL_FLAGS = $(VHDL_STD)

# Perintah untuk melihat waveform (membutuhkan GTKWave)
VIEWER = gtkwave

# ====================================================================
# --- 3. Target (Perintah yang Bisa Dijalankan) ---

# Target default: jika hanya mengetik 'make'
all: simulate

# Menganalisis (Compile) semua file
# 'make analyze'
analyze:
	@echo "--- Menganalisis (Compile) semua file VHDL ---"
	$(GHDL) -a $(GHDL_FLAGS) $(ALL_VHDL_FILES)

# Meng-elaborasi (Build) testbench
# 'make elaborate'
elaborate: analyze
	@echo "--- Meng-elaborasi $(TESTBENCH_ENTITY) ---"
	$(GHDL) -e $(GHDL_FLAGS) $(TESTBENCH_ENTITY)

# Menjalankan simulasi
# 'make simulate'
simulate: elaborate
	@echo "--- Menjalankan simulasi dan membuat $(WAVE_FILE) ---"
	$(GHDL) -r $(GHDL_FLAGS) $(TESTBENCH_ENTITY) --wave=$(WAVE_FILE)

# Membuka waveform (membutuhkan GTKWave)
# 'make view'
view:
	@echo "--- Membuka $(WAVE_FILE) dengan GTKWave ---"
	$(VIEWER) $(WAVE_FILE)

# Membersihkan semua file hasil compile/simulasi
# 'make clean'
clean:
	@echo "--- Membersihkan direktori proyek ---"
	$(GHDL) --clean
	rm -f *.ghw *.vcd *.o *.cf work-obj*.cf

# Memberitahu 'make' bahwa target ini bukan nama file
.PHONY: all analyze elaborate simulate view clean