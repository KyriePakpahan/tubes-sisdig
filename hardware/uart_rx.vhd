library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_rx is
    Generic (
        CLKS_PER_BIT : integer := 87 -- Contoh: 100MHz Clock / 115200 Baud = 868 (Gunakan angka yang sesuai clock board kamu!)
    );
    Port (
        clk       : in  std_logic;
        rx_serial : in  std_logic;
        data_out  : out std_logic_vector(7 downto 0);
        data_valid: out std_logic
    );
end uart_rx;

architecture Behavioral of uart_rx is
    type state_type is (IDLE, RX_START_BIT, RX_DATA_BITS, RX_STOP_BIT, CLEANUP);
    signal current_state : state_type := IDLE;
    
    signal clk_count : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal bit_index : integer range 0 to 7 := 0; -- 8 Bits Total
    signal rx_byte   : std_logic_vector(7 downto 0) := (others => '0');
    signal r_rx_data_r : std_logic := '1';
    signal r_rx_data   : std_logic := '1';
    
begin
    -- Double register untuk menghindari metastability pada input RX
    process(clk)
    begin
        if rising_edge(clk) then
            r_rx_data_r <= rx_serial;
            r_rx_data   <= r_rx_data_r;
        end if;
    end process;

    -- UART FSM
    process(clk)
    begin
        if rising_edge(clk) then
            case current_state is
                when IDLE =>
                    data_valid <= '0';
                    clk_count <= 0;
                    bit_index <= 0;
                    if r_rx_data = '0' then -- Start bit detected
                        current_state <= RX_START_BIT;
                    else
                        current_state <= IDLE;
                    end if;
                    
                when RX_START_BIT =>
                    if clk_count = (CLKS_PER_BIT-1)/2 then
                        if r_rx_data = '0' then
                            clk_count <= 0;
                            current_state <= RX_DATA_BITS;
                        else
                            current_state <= IDLE;
                        end if;
                    else
                        clk_count <= clk_count + 1;
                        current_state <= RX_START_BIT;
                    end if;
                    
                when RX_DATA_BITS =>
                    if clk_count < CLKS_PER_BIT-1 then
                        clk_count <= clk_count + 1;
                        current_state <= RX_DATA_BITS;
                    else
                        clk_count <= 0;
                        rx_byte(bit_index) <= r_rx_data;
                        if bit_index < 7 then
                            bit_index <= bit_index + 1;
                            current_state <= RX_DATA_BITS;
                        else
                            bit_index <= 0;
                            current_state <= RX_STOP_BIT;
                        end if;
                    end if;
                    
                when RX_STOP_BIT =>
                    if clk_count < CLKS_PER_BIT-1 then
                        clk_count <= clk_count + 1;
                        current_state <= RX_STOP_BIT;
                    else
                        data_valid <= '1'; -- Byte valid di sini
                        data_out   <= rx_byte;
                        clk_count <= 0;
                        current_state <= CLEANUP;
                    end if;
                    
                when CLEANUP =>
                    current_state <= IDLE;
                    data_valid <= '0';
                    
                when others =>
                    current_state <= IDLE;
            end case;
        end if;
    end process;
end Behavioral;