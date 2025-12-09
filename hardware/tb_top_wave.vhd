-- ============================================================================
-- TESTBENCH: ASCON CXOF128 TOP - Waveform Simulation
-- ============================================================================
-- This testbench shows the complete system behavior with core and buffer.
-- It demonstrates a full hash computation for the empty input case.
-- Run with: ghdl -r --std=08 tb_top_wave --vcd=top_wave.vcd --stop-time=3000ns
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

entity tb_top_wave is
end tb_top_wave;

architecture sim of tb_top_wave is

    -- Clock period: 10ns = 100 MHz
    constant CLK_PERIOD : time := 10 ns;
    
    -- Signals for top module ports
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal start_z      : std_logic := '0';
    signal start_m      : std_logic := '0';
    signal z_bit_len    : std_logic_vector(63 downto 0) := (others => '0');
    signal out_len_bits : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(512, 32));
    signal data_in      : std_logic_vector(63 downto 0) := (others => '0');
    signal valid_bytes  : unsigned(2 downto 0) := (others => '0');
    signal last_word    : std_logic := '0';
    signal data_valid   : std_logic := '0';
    signal buffer_ready : std_logic;
    signal hash_out     : std_logic_vector(63 downto 0);
    signal hash_valid   : std_logic;
    
    -- Monitor signals for waveform clarity
    signal m_data_sent  : std_logic := '0';
    signal block_count  : integer range 0 to 15 := 0;
    signal hash_block_0 : std_logic_vector(63 downto 0) := (others => '0');
    signal hash_block_1 : std_logic_vector(63 downto 0) := (others => '0');
    
begin

    -- =========================================================================
    -- CLOCK GENERATION
    -- =========================================================================
    clk <= not clk after CLK_PERIOD / 2;
    
    -- =========================================================================
    -- DEVICE UNDER TEST
    -- =========================================================================
    DUT: entity work.ascon_cxof128_top
        port map (
            clk          => clk,
            rst          => rst,
            start_z      => start_z,
            start_m      => start_m,
            z_bit_len    => z_bit_len,
            out_len_bits => out_len_bits,
            data_in      => data_in,
            valid_bytes  => valid_bytes,
            last_word    => last_word,
            data_valid   => data_valid,
            buffer_ready => buffer_ready,
            hash_out     => hash_out,
            hash_valid   => hash_valid
        );
    
    -- =========================================================================
    -- HASH OUTPUT MONITOR
    -- =========================================================================
    -- Only starts counting after M data is sent to capture the actual hash output
    monitor: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                block_count <= 0;
                hash_block_0 <= (others => '0');
                hash_block_1 <= (others => '0');
            elsif m_data_sent = '1' and hash_valid = '1' then
                -- Only count during actual squeeze phase
                report "Hash Block " & integer'image(block_count) & 
                       ": 0x" & to_hstring(hash_out) severity note;
                
                -- Save first two blocks for verification in waveform
                if block_count = 0 then
                    hash_block_0 <= hash_out;
                elsif block_count = 1 then
                    hash_block_1 <= hash_out;
                end if;
                
                if block_count < 15 then
                    block_count <= block_count + 1;
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
        -- PHASE 1: RESET AND INITIALIZATION
        -- =====================================================================
        report "=== PHASE 1: RESET ===" severity note;
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        
        -- Wait for IV P12 to complete (core does 12-round permutation after IV load)
        report "Waiting for IV permutation to complete...";
        wait for CLK_PERIOD * 20;
        
        -- =====================================================================
        -- PHASE 2: START Z PHASE (Empty Customization String)
        -- =====================================================================
        report "=== PHASE 2: START Z PHASE (empty) ===" severity note;
        
        z_bit_len <= (others => '0');  -- 0 bits = empty customization string
        
        wait until rising_edge(clk);
        wait for 0 ns;
        start_z <= '1';
        wait until rising_edge(clk);
        wait for 0 ns;
        start_z <= '0';
        
        report "start_z pulsed";
        
        -- Wait for buffer to be ready
        for i in 0 to 500 loop
            wait until rising_edge(clk);
            if buffer_ready = '1' then 
                report "buffer_ready = '1'";
                exit; 
            end if;
        end loop;
        
        -- =====================================================================
        -- PHASE 3: SEND EMPTY Z DATA (0 bytes + padding)
        -- =====================================================================
        report "=== PHASE 3: SEND EMPTY Z DATA ===" severity note;
        
        data_in <= (others => '0');
        valid_bytes <= "000";  -- 0 valid bytes
        last_word <= '1';      -- This is the last (and only) word
        data_valid <= '1';
        
        -- Wait for buffer to consume data
        wait until rising_edge(clk) and buffer_ready = '0';
        wait for CLK_PERIOD;
        data_valid <= '0';
        last_word <= '0';
        
        report "Empty Z data sent, waiting for Z P12 to complete";
        
        -- Wait for Z phase P12 to complete
        wait for CLK_PERIOD * 20;
        
        -- =====================================================================
        -- PHASE 4: START M PHASE (Empty Message)
        -- =====================================================================
        report "=== PHASE 4: START M PHASE (empty) ===" severity note;
        
        wait until rising_edge(clk);
        wait for 0 ns;
        start_m <= '1';
        wait until rising_edge(clk);
        wait for 0 ns;
        start_m <= '0';
        
        report "start_m pulsed";
        
        -- Wait for buffer to be ready for M data
        for i in 0 to 500 loop
            wait until rising_edge(clk);
            if buffer_ready = '1' then 
                report "buffer_ready = '1'";
                exit; 
            end if;
        end loop;
        
        -- =====================================================================
        -- PHASE 5: SEND EMPTY M DATA (0 bytes + padding)
        -- =====================================================================
        report "=== PHASE 5: SEND EMPTY M DATA ===" severity note;
        
        data_in <= (others => '0');
        valid_bytes <= "000";  -- 0 valid bytes
        last_word <= '1';
        data_valid <= '1';
        
        wait until rising_edge(clk) and buffer_ready = '0';
        wait for CLK_PERIOD;
        data_valid <= '0';
        last_word <= '0';
        m_data_sent <= '1';  -- Signal that we're now in squeeze phase
        
        report "Empty M data sent, NOW COLLECTING HASH OUTPUT";
        
        -- =====================================================================
        -- PHASE 6: COLLECT HASH OUTPUT
        -- =====================================================================
        report "=== PHASE 6: SQUEEZE PHASE - COLLECTING HASH ===" severity note;
        
        -- Wait for all 8 hash blocks
        -- Each block is 64 bits, 8 blocks = 512 bits output
        -- Each squeeze requires a P12 (12 cycles) plus some overhead
        wait for CLK_PERIOD * 300;
        
        -- =====================================================================
        -- FINAL REPORT
        -- =====================================================================
        report "Total hash blocks collected: " & integer'image(block_count) severity note;
        report "First hash block: 0x" & to_hstring(hash_block_0) severity note;
        report "Expected:         0x4F50159EF70BB3DA" severity note;
        
        if hash_block_0 = x"4F50159EF70BB3DA" then
            report "=== FIRST BLOCK MATCHES! ===" severity note;
        else
            report "=== FIRST BLOCK MISMATCH ===" severity warning;
        end if;
        
        report "=== SIMULATION COMPLETE ===" severity note;
        wait;
    end process;

end sim;
