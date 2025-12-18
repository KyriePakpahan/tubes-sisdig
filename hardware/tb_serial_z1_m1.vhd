-- ============================================================================
-- TESTBENCH: tb_serial_z1_m1 - Tests with Z=0x10 (1 byte) and M=0x00 (1 byte)
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_serial_z1_m1 is
end tb_serial_z1_m1;

architecture Behavioral of tb_serial_z1_m1 is

    constant CLK_PERIOD    : time := 20 ns;
    constant CLKS_PER_BIT  : integer := 10;
    constant BIT_PERIOD    : time := CLK_PERIOD * CLKS_PER_BIT;
    
    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';
    signal uart_rx      : std_logic := '1';
    signal uart_tx      : std_logic;
    signal led_idle     : std_logic;
    signal led_busy     : std_logic;
    signal led_done     : std_logic;
    signal sim_done     : std_logic := '0';
    
    signal rx_byte_cnt  : integer := 0;
    signal hash_output  : std_logic_vector(255 downto 0) := (others => '0');

    -- Expected hash for Z=0x10, M=0x00 (KAT Count=35, first 32 bytes)
    constant EXPECTED : std_logic_vector(255 downto 0) := 
        x"63FA8BA86382F2D544580F51322D080424B42C556EB74503CD73CF052BB993BD";

begin

    DUT: entity work.ascon_serial_top
    generic map ( CLKS_PER_BIT => CLKS_PER_BIT )
    port map (
        clk      => clk,
        rst_n    => rst_n,
        uart_rx  => uart_rx,
        uart_tx  => uart_tx,
        led_idle => led_idle,
        led_busy => led_busy,
        led_done => led_done
    );

    clk_process: process
    begin
        while sim_done = '0' loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    stim_process: process
        procedure send_byte(data : std_logic_vector(7 downto 0)) is
        begin
            uart_rx <= '0';
            wait for BIT_PERIOD;
            for i in 0 to 7 loop
                uart_rx <= data(i);
                wait for BIT_PERIOD;
            end loop;
            uart_rx <= '1';
            wait for BIT_PERIOD;
        end procedure;
        
    begin
        uart_rx <= '1';
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        
        -- Wait for FPGA init
        wait until led_idle = '1' for 10 us;
        wait for 500 ns;
        
        report "=== TEST: Z=0x10 (1 byte), M=0x00 (1 byte), out=32 ===";
        
        -- Send header
        send_byte(x"01");  -- z_len = 1
        send_byte(x"01");  -- m_len = 1
        send_byte(x"20");  -- out_len = 32
        
        -- Send Z data (1 byte: 0x10)
        report "Header sent, sending Z data...";
        send_byte(x"10");
        
        -- Wait for FPGA to process Z phase and P12
        report "Z data sent, waiting for FPGA to digest Z...";
        -- A generous wait time to simulate real UART gap and allow internal processing
        wait for 10 us;
        
        -- Send M data (1 byte: 0x00)
        report "Sending M data...";
        send_byte(x"00");
        
        report "Data sent, waiting for output...";
        
        -- Wait for output
        for i in 0 to 1000 loop
            wait for 100 us;
            if rx_byte_cnt >= 32 then
                report "All 32 bytes received!";
                exit;
            end if;
        end loop;
        
        wait for 1 ms;
        
        report "=== RESULT ===";
        report "Bytes received: " & integer'image(rx_byte_cnt);
        report "Expected: 63FA8BA86382F2D544580F51322D080424B42C556EB74503CD73CF052BB993BD";
        if rx_byte_cnt >= 32 then
            report "Got:      " & to_hstring(hash_output);
            if hash_output = EXPECTED then
                report "*** MATCH! ***";
            else
                report "*** MISMATCH! ***";
            end if;
        end if;
        
        sim_done <= '1';
        wait;
    end process;

    capture_process: process
        variable rx_data_v : std_logic_vector(7 downto 0);
    begin
        while sim_done = '0' loop
            if uart_tx = '0' then
                wait for BIT_PERIOD / 2;
                for i in 0 to 7 loop
                    wait for BIT_PERIOD;
                    rx_data_v(i) := uart_tx;
                end loop;
                wait for BIT_PERIOD;
                
                report "RX[" & integer'image(rx_byte_cnt) & "] = 0x" & to_hstring(rx_data_v);
                
                if rx_byte_cnt < 32 then
                    hash_output(255 - rx_byte_cnt*8 downto 248 - rx_byte_cnt*8) <= rx_data_v;
                end if;
                rx_byte_cnt <= rx_byte_cnt + 1;
            else
                wait for CLK_PERIOD;
            end if;
        end loop;
        wait;
    end process;

end Behavioral;
