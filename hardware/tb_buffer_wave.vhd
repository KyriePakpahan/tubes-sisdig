-- ============================================================================
-- TESTBENCH: CXOF BUFFER - Waveform Simulation
-- ============================================================================
-- This testbench demonstrates the buffer's state machine behavior.
-- It simulates the absorption phases with a simple stub core.
-- Run with: ghdl -r --std=08 tb_buffer_wave --vcd=buffer_wave.vcd --stop-time=2000ns
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_buffer_wave is
end tb_buffer_wave;

architecture sim of tb_buffer_wave is

    -- Clock period: 10ns = 100 MHz
    constant CLK_PERIOD : time := 10 ns;
    
    -- Signals for buffer ports
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal z_bit_len    : std_logic_vector(63 downto 0) := x"0000000000000008";  -- 8 bits = 1 byte
    signal out_len_bits : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(512, 32));  -- 64 bytes output
    signal start_z      : std_logic := '0';
    signal start_m      : std_logic := '0';
    signal data_in      : std_logic_vector(63 downto 0) := (others => '0');
    signal valid_bytes  : unsigned(2 downto 0) := (others => '0');
    signal last_word    : std_logic := '0';
    signal data_valid   : std_logic := '0';
    signal buffer_ready : std_logic;
    signal block_out    : std_logic_vector(63 downto 0);
    signal block_valid  : std_logic;
    signal cmd_perm     : std_logic;
    signal cmd_squeeze  : std_logic;
    signal domain_sep   : std_logic;
    signal core_busy    : std_logic := '0';
    
    -- Simulated core busy counter (simulates 12-cycle P12)
    signal busy_counter : integer range 0 to 15 := 0;
    signal perm_requested : std_logic := '0';  -- Edge detector
    
    -- Debug: track current buffer state name (for waveform visualization)
    signal debug_state  : integer range 0 to 15 := 0;
    
begin

    -- =========================================================================
    -- CLOCK GENERATION
    -- =========================================================================
    clk <= not clk after CLK_PERIOD / 2;
    
    -- =========================================================================
    -- DEVICE UNDER TEST
    -- =========================================================================
    DUT: entity work.cxof_buffer
        port map (
            clk          => clk,
            rst          => rst,
            z_bit_len    => z_bit_len,
            out_len_bits => out_len_bits,
            start_z      => start_z,
            start_m      => start_m,
            data_in      => data_in,
            valid_bytes  => valid_bytes,
            last_word    => last_word,
            data_valid   => data_valid,
            buffer_ready => buffer_ready,
            block_out    => block_out,
            block_valid  => block_valid,
            cmd_perm     => cmd_perm,
            cmd_squeeze  => cmd_squeeze,
            domain_sep   => domain_sep,
            core_busy    => core_busy
        );
    
    -- =========================================================================
    -- IMPROVED CORE BUSY SIMULATOR
    -- =========================================================================
    -- The real core goes busy immediately when cmd_perm rises, stays busy for
    -- 12 clock cycles (one per permutation round), then goes idle.
    -- This simulator mimics that behavior with edge detection.
    
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                busy_counter <= 0;
                core_busy <= '0';
                perm_requested <= '0';
            else
                -- Edge detection for cmd_perm/cmd_squeeze
                perm_requested <= cmd_perm or cmd_squeeze;
                
                if busy_counter > 0 then
                    -- Count down while busy
                    busy_counter <= busy_counter - 1;
                    if busy_counter = 1 then
                        core_busy <= '0';  -- Will be idle on next cycle
                    end if;
                elsif (cmd_perm = '1' or cmd_squeeze = '1') and perm_requested = '0' then
                    -- Rising edge detected - start 12 cycle busy period
                    busy_counter <= 12;
                    core_busy <= '1';
                    report "Core: Starting P12 (12 cycles)" severity note;
                end if;
            end if;
        end if;
    end process;
    
    -- =========================================================================
    -- STIMULUS PROCESS
    -- =========================================================================
    stimulus: process
    begin
        -- =====================================================================
        -- PHASE 1: RESET
        -- =====================================================================
        report "=== PHASE 1: RESET ===" severity note;
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "Buffer initialized, waiting in IDLE state";
        
        -- =====================================================================
        -- PHASE 2: START Z PHASE
        -- =====================================================================
        report "=== PHASE 2: START Z PHASE (1-byte customization string) ===" severity note;
        
        -- Set up z_bit_len for 1 byte customization string
        z_bit_len <= x"0000000000000008";  -- 8 bits = 1 byte
        
        -- Pulse start_z
        wait until rising_edge(clk);
        start_z <= '1';
        wait until rising_edge(clk);
        start_z <= '0';
        
        report "start_z pulsed, buffer should go to ABSORB_CSLEN";
        
        -- Wait for CSLEN absorption + P12 to complete (12 cycles + overhead)
        report "Waiting for CSLEN P12 to complete...";
        wait for CLK_PERIOD * 20;
        
        -- Check if buffer_ready goes high (means we're in STREAM_Z)
        report "Checking for buffer_ready...";
        
        -- =====================================================================
        -- PHASE 3: SEND Z DATA
        -- =====================================================================
        report "=== PHASE 3: SEND Z DATA ===" severity note;
        
        -- Use a timeout loop instead of infinite wait
        for i in 0 to 50 loop
            if buffer_ready = '1' then
                report "buffer_ready = '1', sending Z data";
                exit;
            end if;
            wait until rising_edge(clk);
        end loop;
        
        if buffer_ready = '0' then
            report "WARNING: buffer_ready timeout, continuing anyway" severity warning;
        end if;
        
        -- Send 1 byte of Z data (0x10)
        data_in <= x"1000000000000000";  -- 0x10 in MSB position
        valid_bytes <= "001";  -- 1 byte
        last_word <= '1';
        data_valid <= '1';
        
        -- Hold data valid for a couple of cycles
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        data_valid <= '0';
        last_word <= '0';
        
        report "Z data sent, buffer should absorb and add padding";
        
        -- Wait for Z phase P12 to complete
        wait for CLK_PERIOD * 20;
        report "After Z P12, buffer should be in WAIT_M";
        
        -- =====================================================================
        -- PHASE 4: START M PHASE
        -- =====================================================================
        report "=== PHASE 4: START M PHASE (empty message) ===" severity note;
        
        -- Pulse start_m
        wait until rising_edge(clk);
        start_m <= '1';
        wait until rising_edge(clk);
        start_m <= '0';
        
        report "start_m pulsed, buffer should go to STREAM_M";
        
        -- =====================================================================
        -- PHASE 5: SEND EMPTY M DATA
        -- =====================================================================
        report "=== PHASE 5: SEND EMPTY M DATA ===" severity note;
        
        -- Wait for buffer_ready with timeout
        for i in 0 to 50 loop
            if buffer_ready = '1' then
                report "buffer_ready = '1', sending empty M data (padding only)";
                exit;
            end if;
            wait until rising_edge(clk);
        end loop;
        
        -- Send empty message (0 bytes, just last_word flag)
        data_in <= (others => '0');
        valid_bytes <= "000";  -- 0 bytes
        last_word <= '1';
        data_valid <= '1';
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        data_valid <= '0';
        last_word <= '0';
        
        report "Empty M data sent, buffer should add padding and permute";
        
        -- Wait for M phase P12
        wait for CLK_PERIOD * 20;
        report "After M P12, buffer should be in SQUEEZE_LOOP";
        
        -- =====================================================================
        -- PHASE 6: SQUEEZE OUTPUT
        -- =====================================================================
        report "=== PHASE 6: SQUEEZE OUTPUT ===" severity note;
        
        -- Watch squeeze signals for a few cycles
        for i in 0 to 100 loop
            wait until rising_edge(clk);
            if cmd_squeeze = '1' then
                report "Squeeze block output at cycle " & integer'image(i);
            end if;
        end loop;
        
        report "=== SIMULATION COMPLETE ===" severity note;
        wait;
    end process;

end sim;
