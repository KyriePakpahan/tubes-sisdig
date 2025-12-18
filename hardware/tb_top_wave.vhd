-- ============================================================================
-- TESTBENCH: ASCON CXOF128 TOP - Hard Reset & Full Block Verification
-- ============================================================================
-- Run with: ghdl -r --std=08 tb_top_wave --vcd=top_wave.vcd --stop-time=10000ns
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
    signal out_len_bits : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(256, 32)); -- 32 bytes output
    signal data_in      : std_logic_vector(63 downto 0) := (others => '0');
    signal valid_bytes  : unsigned(2 downto 0) := (others => '0');
    signal last_word    : std_logic := '0';
    signal data_valid   : std_logic := '0';
    signal buffer_ready : std_logic;
    signal hash_out     : std_logic_vector(63 downto 0);
    signal hash_valid   : std_logic;
    
    -- Monitor signals
    signal test_case    : integer := 0;

begin

    -- Clock Generation
    clk <= not clk after CLK_PERIOD / 2;
    
    -- DUT
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
    
    -- Stimulus
    process
        procedure drive_empty_test(idx : integer) is
        begin
            report "=== TEST CASE " & integer'image(idx) & ": EMPTY INPUT ===";
            test_case <= idx;
            z_bit_len <= (others => '0');
            
            -- Hold Start Z until buffer is ready
            wait until rising_edge(clk); start_z <= '1';
            wait until buffer_ready = '1' and rising_edge(clk);
            start_z <= '0';
            report "Buffer Ready received";
            
            -- Send Empty Z
            data_in <= (others => '0');
            valid_bytes <= "000";
            last_word <= '1';
            data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
            last_word <= '0';
            
            -- Wait for Z Permutation
            wait for 200 ns; 
            
            -- Hold Start M
            wait until rising_edge(clk); start_m <= '1';
            wait until buffer_ready = '1' and rising_edge(clk);
            start_m <= '0';
            
            -- Send Empty M
            wait until rising_edge(clk);
            data_in <= (others => '0');
            valid_bytes <= "000";
            last_word <= '1';
            data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
            last_word <= '0';
            
            -- Collect Output
            wait until hash_valid = '1';
            report "Got Hash: " & to_hstring(hash_out);
            
            wait for 500 ns; -- Wait for completion
        end procedure;

        procedure drive_full_block_test(idx : integer) is
        begin
            report "=== TEST CASE " & integer'image(idx) & ": FULL 8-BYTE Z ===";
            test_case <= idx;
            z_bit_len <= std_logic_vector(to_unsigned(64, 64)); -- 64 bits = 8 bytes
            
            -- Hold Start Z
            wait until rising_edge(clk); start_z <= '1';
            wait until buffer_ready = '1' and rising_edge(clk);
            start_z <= '0';
            
            -- Send Z Body (8 bytes), NOT last word
            wait until rising_edge(clk);
            data_in <= x"1011121314151617"; -- Example Z
            valid_bytes <= "000"; -- 8 bytes
            last_word <= '0';     -- Full Block Protocol: Split body
            data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
            
            -- CRITICAL CHECK: Buffer should NOT be ready immediately if Core busy
            wait for 1 ns;
            if buffer_ready = '1' then
                report "WARNING: Buffer claims ready immediately after body? (Maybe P12 hasn't started yet)" severity note;
            else
                report "SUCCESS: Buffer is Busy processing Body P12" severity note;
            end if;
            
            -- Wait for Ready again (for Tail)
            wait until buffer_ready = '1';
            report "Buffer Ready for Tail";
            
            -- Send Z Tail (Empty)
            wait until rising_edge(clk);
            data_in <= (others => '0');
            valid_bytes <= "000";
            last_word <= '1'; -- Now Last
            data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
            last_word <= '0';
            
            wait for 200 ns;

            -- M Phase (Empty)
            wait until rising_edge(clk); start_m <= '1';
            wait until buffer_ready = '1' and rising_edge(clk);
            start_m <= '0';
            wait until rising_edge(clk);
            data_in <= (others => '0');
            valid_bytes <= "000";
            last_word <= '1';
            data_valid <= '1';
            wait until rising_edge(clk);
            data_valid <= '0';
            
            wait until hash_valid = '1';
            report "Got Hash: " & to_hstring(hash_out);
            wait for 500 ns;
        end procedure;

    begin
        -- Initial Reset
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for 200 ns; -- Wait for Initial IV Load
        
        -- TEST 1: Standard Empty
        drive_empty_test(1);
        
        -- TEST 2: Verify Hard Reset (Run Empty Again)
        drive_empty_test(2);
        
        -- TEST 3: Full Block Z (The Failing Case)
        drive_full_block_test(3);
        
        report "SIMULATION FINISHED";
        wait;
    end process;

end sim;
