-- ============================================================================
-- TESTBENCH: ASCON CXOF128 CORE - Waveform Simulation
-- ============================================================================
-- This testbench demonstrates the core permutation module behavior.
-- It shows: initialization, data absorption, and a full P12 permutation.
-- Run with: ghdl -r --std=08 tb_core_wave --vcd=core_wave.vcd --stop-time=500ns
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_core_wave is
end tb_core_wave;

architecture sim of tb_core_wave is

    -- Clock period: 10ns = 100 MHz
    constant CLK_PERIOD : time := 10 ns;
    
    -- Signals to connect to DUT (Device Under Test)
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal start_perm : std_logic := '0';
    signal absorb_en  : std_logic := '0';
    signal init_state : std_logic := '0';
    signal block_in   : std_logic_vector(63 downto 0) := (others => '0');
    signal block_out  : std_logic_vector(63 downto 0);
    signal core_busy  : std_logic;
    signal perm_done  : std_logic;
    
begin

    -- =========================================================================
    -- CLOCK GENERATION
    -- =========================================================================
    clk <= not clk after CLK_PERIOD / 2;
    
    -- =========================================================================
    -- DEVICE UNDER TEST
    -- =========================================================================
    DUT: entity work.ascon_cxof128_core
        port map (
            clk        => clk,
            rst        => rst,
            start_perm => start_perm,
            absorb_en  => absorb_en,
            init_state => init_state,
            block_in   => block_in,
            block_out  => block_out,
            core_busy  => core_busy,
            perm_done  => perm_done
        );
    
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
        
        report "After reset, S[0] (block_out) should be IV: 0x0000080000cc0004";
        report "block_out = 0x" & to_hstring(block_out);
        
        -- =====================================================================
        -- PHASE 2: FIRST P12 PERMUTATION (Initialization)
        -- =====================================================================
        report "=== PHASE 2: FIRST P12 (IV Permutation) ===" severity note;
        
        -- Start P12
        start_perm <= '1';
        wait for CLK_PERIOD;
        start_perm <= '0';
        
        -- Wait for permutation to complete (12 rounds)
        report "core_busy should be '1' during permutation";
        wait until perm_done = '1';
        wait for 0 ns;  -- Delta cycle
        
        report "P12 complete! perm_done = '1'";
        report "New S[0] = 0x" & to_hstring(block_out);
        
        wait for CLK_PERIOD * 2;
        
        -- =====================================================================
        -- PHASE 3: ABSORB DATA
        -- =====================================================================
        report "=== PHASE 3: ABSORB DATA ===" severity note;
        
        -- Absorb a test value into S[0]
        block_in <= x"0000000000000040";  -- z_bit_len = 64 bits = 8 bytes
        absorb_en <= '1';
        wait for CLK_PERIOD;
        absorb_en <= '0';
        block_in <= (others => '0');
        
        report "Absorbed 0x0000000000000040 (XORed into S[0])";
        wait for CLK_PERIOD;
        report "New S[0] = 0x" & to_hstring(block_out);
        
        -- =====================================================================
        -- PHASE 4: SECOND P12 PERMUTATION
        -- =====================================================================
        report "=== PHASE 4: SECOND P12 (After Absorption) ===" severity note;
        
        start_perm <= '1';
        wait for CLK_PERIOD;
        start_perm <= '0';
        
        wait until perm_done = '1';
        wait for 0 ns;
        
        report "Second P12 complete!";
        report "Final S[0] = 0x" & to_hstring(block_out);
        
        wait for CLK_PERIOD * 3;
        
        -- =====================================================================
        -- PHASE 5: REINITIALIZE STATE
        -- =====================================================================
        report "=== PHASE 5: REINITIALIZE ===" severity note;
        
        init_state <= '1';
        wait for CLK_PERIOD;
        init_state <= '0';
        
        report "State reinitialized to IV";
        wait for CLK_PERIOD;
        report "S[0] = 0x" & to_hstring(block_out);
        
        wait for CLK_PERIOD * 5;
        
        report "=== SIMULATION COMPLETE ===" severity note;
        wait;
    end process;

end sim;
