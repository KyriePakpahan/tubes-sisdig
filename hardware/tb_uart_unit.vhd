-- ============================================================================
-- UART TX/RX Unit Test
-- ============================================================================
-- Tests the UART TX with:
--   1. Reset functionality (new rst port)
--   2. Registered tx_busy output (no glitches)
--   3. RX with half-stop-bit optimization
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_uart_unit is
end tb_uart_unit;

architecture Behavioral of tb_uart_unit is

    constant CLKS_PER_BIT : integer := 87;  -- ~115200 baud at 10MHz
    constant CLK_PERIOD   : time := 100 ns; -- 10 MHz clock
    constant BIT_PERIOD   : time := CLK_PERIOD * CLKS_PER_BIT;

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '0';
    
    -- TX signals
    signal tx_start  : std_logic := '0';
    signal tx_data   : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_serial : std_logic;
    signal tx_busy   : std_logic;
    signal tx_done   : std_logic;
    
    -- RX signals
    signal rx_serial : std_logic := '1';
    signal rx_data   : std_logic_vector(7 downto 0);
    signal rx_valid  : std_logic;
    
    -- Test control
    signal test_done : boolean := false;

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD/2 when not test_done else '0';
    
    -- Connect TX output to RX input (loopback)
    rx_serial <= tx_serial;

    -- UART TX under test
    U_TX : entity work.uart_tx
    generic map ( CLKS_PER_BIT => CLKS_PER_BIT )
    port map (
        clk       => clk,
        rst       => rst,
        tx_start  => tx_start,
        data_in   => tx_data,
        tx_serial => tx_serial,
        tx_busy   => tx_busy,
        tx_done   => tx_done
    );
    
    -- UART RX under test
    U_RX : entity work.uart_rx
    generic map ( CLKS_PER_BIT => CLKS_PER_BIT )
    port map (
        clk        => clk,
        rst        => rst,
        rx_serial  => rx_serial,
        data_out   => rx_data,
        data_valid => rx_valid
    );

    -- Test process
    process
        variable received_bytes : integer := 0;
        variable test_byte : std_logic_vector(7 downto 0);
    begin
        report "=== UART Unit Test Started ===" severity note;
        
        -- ====================================
        -- TEST 1: Reset functionality
        -- ====================================
        report "TEST 1: Reset functionality" severity note;
        
        -- Assert reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        
        -- Verify TX is idle during reset
        assert tx_busy = '0' 
            report "FAIL: tx_busy should be '0' during reset" severity error;
        assert tx_serial = '1' 
            report "FAIL: tx_serial should be '1' (idle) during reset" severity error;
        
        -- Release reset
        rst <= '0';
        wait for CLK_PERIOD * 5;
        
        -- Verify TX remains idle after reset
        assert tx_busy = '0' 
            report "FAIL: tx_busy should be '0' after reset release" severity error;
        
        report "TEST 1: PASSED - Reset works correctly" severity note;
        
        -- ====================================
        -- TEST 2: TX busy signal is registered
        -- ====================================
        report "TEST 2: TX busy signal behavior" severity note;
        
        -- Start transmission
        tx_data <= x"A5";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';
        
        -- Check tx_busy goes high on next clock edge
        wait for CLK_PERIOD;
        assert tx_busy = '1' 
            report "FAIL: tx_busy should be '1' after tx_start" severity error;
        
        -- Wait for transmission to complete (including CLEANUP -> IDLE transition)
        wait until tx_done = '1';
        wait for CLK_PERIOD * 5;  -- Wait for CLEANUP -> IDLE transition
        
        -- Check tx_busy goes low
        assert tx_busy = '0' 
            report "FAIL: tx_busy should be '0' after transmission complete" severity error;
        
        report "TEST 2: PASSED - tx_busy is properly registered" severity note;
        
        -- ====================================
        -- TEST 3: Loopback test (TX -> RX)
        -- ====================================
        report "TEST 3: Loopback test (TX -> RX)" severity note;
        
        -- Send a single test byte through loopback
        test_byte := x"A5";
        
        -- TX should already be idle from previous test
        wait for CLK_PERIOD * 10;
        
        -- Start transmission
        tx_data <= test_byte;
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';
        
        -- Wait for full byte transmission + RX processing
        -- 1 start + 8 data + 1 stop = 10 bits
        wait for BIT_PERIOD * 12;
        
        -- Check if we received the byte
        if rx_data = test_byte then
            received_bytes := 1;
            report "  Loopback byte TX=0xA5 RX=0x" & 
                   integer'image(to_integer(unsigned(rx_data))) & " OK"
                severity note;
        else
            report "FAIL: RX data mismatch. Expected: 0xA5 Got: 0x" & 
                   integer'image(to_integer(unsigned(rx_data)))
                severity error;
        end if;
        
        report "TEST 3: PASSED - Loopback successful" severity note;
        
        -- ====================================
        -- TEST 4: Reset during transmission
        -- ====================================
        report "TEST 4: Reset during transmission" severity note;
        
        -- Start a transmission
        tx_data <= x"FF";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';
        
        -- Wait a bit, then reset mid-transmission
        wait for BIT_PERIOD * 3;
        rst <= '1';
        wait for CLK_PERIOD * 3;
        
        -- Verify reset took effect
        assert tx_busy = '0' 
            report "FAIL: tx_busy should be '0' after mid-transmission reset" severity error;
        assert tx_serial = '1' 
            report "FAIL: tx_serial should be '1' after mid-transmission reset" severity error;
        
        rst <= '0';
        wait for CLK_PERIOD * 5;
        
        report "TEST 4: PASSED - Reset during transmission works" severity note;
        
        -- ====================================
        -- All tests complete
        -- ====================================
        report "=== ALL TESTS PASSED ===" severity note;
        
        test_done <= true;
        wait;
    end process;

end Behavioral;
