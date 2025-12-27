library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx is
    Generic (
        CLKS_PER_BIT : integer := 87 -- Contoh: 100MHz Clock / 115200 Baud = 868 (Gunakan angka yang sesuai clock board kamu!)
    );
    Port (
        clk        : in  std_logic;
        rst        : in  std_logic;                     -- Active-high synchronous reset
        tx_start   : in  std_logic;                     -- Sinyal untuk memulai transmisi
        data_in    : in  std_logic_vector(7 downto 0);  -- Data byte yang akan dikirim
        tx_serial  : out std_logic;                     -- Output serial UART TX
        tx_busy    : out std_logic;                     -- '1' saat sedang transmisi
        tx_done    : out std_logic                      -- Pulse '1' saat transmisi selesai
    );
end uart_tx;

architecture Behavioral of uart_tx is
    type state_type is (IDLE, TX_START_BIT, TX_DATA_BITS, TX_STOP_BIT, CLEANUP);
    signal current_state : state_type := IDLE;
    
    signal clk_count : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal bit_index : integer range 0 to 7 := 0; -- 8 Bits Total
    signal tx_data   : std_logic_vector(7 downto 0) := (others => '0');
    signal r_tx_done : std_logic := '0';
    signal r_tx_busy : std_logic := '0';  -- Registered tx_busy to prevent glitches
    
begin

    tx_done <= r_tx_done;
    tx_busy <= r_tx_busy;  -- Registered output to prevent glitches

    -- UART TX FSM
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- Synchronous reset
                current_state <= IDLE;
                clk_count <= 0;
                bit_index <= 0;
                tx_data <= (others => '0');
                r_tx_done <= '0';
                r_tx_busy <= '0';
                tx_serial <= '1';  -- Line idle high
            else
                case current_state is
                    when IDLE =>
                        tx_serial <= '1'; -- Line idle high
                        r_tx_done <= '0';
                        r_tx_busy <= '0';  -- Not busy when idle
                        clk_count <= 0;
                        bit_index <= 0;
                        
                        if tx_start = '1' then
                            tx_data <= data_in; -- Capture data saat mulai
                            r_tx_busy <= '1';   -- Now busy
                            current_state <= TX_START_BIT;
                        else
                            current_state <= IDLE;
                        end if;
                    
                when TX_START_BIT =>
                    tx_serial <= '0'; -- Start bit = '0'
                    
                    if clk_count < CLKS_PER_BIT-1 then
                        clk_count <= clk_count + 1;
                        current_state <= TX_START_BIT;
                    else
                        clk_count <= 0;
                        current_state <= TX_DATA_BITS;
                    end if;
                    
                when TX_DATA_BITS =>
                    tx_serial <= tx_data(bit_index); -- Kirim LSB terlebih dahulu
                    
                    if clk_count < CLKS_PER_BIT-1 then
                        clk_count <= clk_count + 1;
                        current_state <= TX_DATA_BITS;
                    else
                        clk_count <= 0;
                        if bit_index < 7 then
                            bit_index <= bit_index + 1;
                            current_state <= TX_DATA_BITS;
                        else
                            bit_index <= 0;
                            current_state <= TX_STOP_BIT;
                        end if;
                    end if;
                    
                when TX_STOP_BIT =>
                    tx_serial <= '1'; -- Stop bit = '1'
                    
                    if clk_count < CLKS_PER_BIT-1 then
                        clk_count <= clk_count + 1;
                        current_state <= TX_STOP_BIT;
                    else
                        r_tx_done <= '1'; -- Transmisi selesai
                        clk_count <= 0;
                        current_state <= CLEANUP;
                    end if;
                    
                when CLEANUP =>
                    current_state <= IDLE;
                    r_tx_done <= '0';
                    
                    when others =>
                        current_state <= IDLE;
                end case;
            end if;  -- rst
        end if;  -- rising_edge
    end process;
end Behavioral;
