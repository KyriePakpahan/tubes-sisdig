-- ============================================================================
-- ASCON FPGA SERIAL TOP - Protocol-Based FPGA Implementation
-- ============================================================================
-- Fully automated Ascon-CXOF128 hash module with serial protocol.
-- No buttons required - FPGA automatically processes data when received.
--
-- Target: Cyclone IV EP4CE6E22C8N (50MHz clock)
-- Baud Rate: 115200
--
-- PROTOCOL (Laptop → FPGA):
-- [z_len: 1 byte] [m_len: 1 byte] [out_len: 1 byte] [Z data] [M data]
--
-- PROTOCOL (FPGA → Laptop):
-- [hash output: out_len bytes]
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ascon_serial_top is
    Generic (
        CLKS_PER_BIT : integer := 434  -- 50MHz / 115200 = 434
    );
    Port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        uart_rx     : in  std_logic;
        uart_tx     : out std_logic;
        led_idle    : out std_logic;
        led_busy    : out std_logic;
        led_done    : out std_logic
    );
end ascon_serial_top;

architecture Behavioral of ascon_serial_top is

    signal rst : std_logic;

    -- UART signals
    signal rx_data      : std_logic_vector(7 downto 0);
    signal rx_valid     : std_logic;
    signal tx_data      : std_logic_vector(7 downto 0);
    signal tx_start     : std_logic := '0';
    signal tx_busy      : std_logic;
    signal tx_done      : std_logic;

    -- Main state machine
    type main_state_type is (
        S_INIT,
        S_IDLE,
        S_READ_MLEN,
        S_READ_OUTLEN,
        S_START_Z,
        S_WAIT_Z_READY,
        S_READ_Z,
        S_SEND_Z_LAST,
        S_WAIT_Z_DONE,
        S_START_M,
        S_WAIT_M_READY,
        S_READ_M,
        S_SEND_M_LAST,
        S_COLLECT_HASH,
        S_TX_BYTE,
        S_TX_WAIT,
        S_DONE
    );
    signal state : main_state_type := S_INIT;
    signal wait_cnt : unsigned(7 downto 0) := (others => '0');

    -- Protocol registers
    signal z_len        : unsigned(7 downto 0) := (others => '0');
    signal m_len        : unsigned(7 downto 0) := (others => '0');
    signal out_len      : unsigned(7 downto 0) := (others => '0');
    signal byte_counter : unsigned(7 downto 0) := (others => '0');

    -- Byte buffer for incoming UART data
    signal rx_buffer      : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_buffer_full : std_logic := '0';  -- '1' when buffer has unprocessed data

    -- Byte accumulator for building 64-bit words
    signal accum_reg    : std_logic_vector(63 downto 0) := (others => '0');
    signal accum_idx    : unsigned(2 downto 0) := (others => '0');

    -- Hash module interface
    signal hash_start_z     : std_logic := '0';
    signal hash_start_m     : std_logic := '0';
    signal hash_data_in     : std_logic_vector(63 downto 0) := (others => '0');
    signal hash_valid_bytes : unsigned(2 downto 0) := (others => '0');
    signal hash_last_word   : std_logic := '0';
    signal hash_data_valid  : std_logic := '0';
    signal hash_ready       : std_logic;
    signal hash_out         : std_logic_vector(63 downto 0);
    signal hash_out_valid   : std_logic;

    -- Hash output storage (32 blocks * 8 bytes = 256 bytes max)
    type hash_array_type is array (0 to 31) of std_logic_vector(63 downto 0);
    signal hash_blocks      : hash_array_type := (others => (others => '0'));
    signal blocks_collected : unsigned(4 downto 0) := (others => '0');
    signal blocks_needed    : unsigned(4 downto 0) := (others => '0');
    signal await_valid_low  : std_logic := '0';

    -- TX handling
    signal bytes_sent   : unsigned(7 downto 0) := (others => '0');
    signal tx_block_idx : unsigned(4 downto 0) := (others => '0');
    signal tx_byte_idx  : unsigned(2 downto 0) := (others => '0');

begin

    rst <= not rst_n;

    -- ========================================================================
    -- UART RX
    -- ========================================================================
    U_UART_RX : entity work.uart_rx
    generic map ( CLKS_PER_BIT => CLKS_PER_BIT )
    port map (
        clk        => clk,
        rx_serial  => uart_rx,
        data_out   => rx_data,
        data_valid => rx_valid
    );

    -- ========================================================================
    -- UART TX
    -- ========================================================================
    U_UART_TX : entity work.uart_tx
    generic map ( CLKS_PER_BIT => CLKS_PER_BIT )
    port map (
        clk        => clk,
        tx_start   => tx_start,
        data_in    => tx_data,
        tx_serial  => uart_tx,
        tx_busy    => tx_busy,
        tx_done    => tx_done
    );

    -- ========================================================================
    -- ASCON CXOF128 TOP
    -- ========================================================================
    U_HASH: entity work.ascon_cxof128_top
    port map (
        clk          => clk,
        rst          => rst,
        z_bit_len    => std_logic_vector(resize(z_len * 8, 64)),
        out_len_bits => std_logic_vector(resize(out_len * 8, 32)),
        start_z      => hash_start_z,
        start_m      => hash_start_m,
        data_in      => hash_data_in,
        valid_bytes  => hash_valid_bytes,
        last_word    => hash_last_word,
        data_valid   => hash_data_valid,
        buffer_ready => hash_ready,
        hash_out     => hash_out,
        hash_valid   => hash_out_valid
    );

    -- ========================================================================
    -- LED OUTPUTS
    -- ========================================================================
    led_idle <= '1' when state = S_IDLE else '0';
    led_busy <= '1' when state /= S_IDLE and state /= S_DONE and state /= S_INIT else '0';
    led_done <= '1' when state = S_DONE else '0';

    -- ========================================================================
    -- STATE MACHINE
    -- ========================================================================
    process(clk)
        variable current_block : std_logic_vector(63 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= S_INIT;
                wait_cnt <= (others => '0');
                byte_counter <= (others => '0');
                accum_reg <= (others => '0');
                accum_idx <= (others => '0');
                hash_start_z <= '0';
                hash_start_m <= '0';
                hash_data_valid <= '0';
                hash_last_word <= '0';
                tx_start <= '0';
                blocks_collected <= (others => '0');
                blocks_needed <= (others => '0');
                await_valid_low <= '0';
            else
                -- Clear pulse signals
                hash_start_z <= '0';
                hash_start_m <= '0';
                hash_data_valid <= '0';
                hash_last_word <= '0';
                tx_start <= '0';

                case state is

                    when S_INIT =>
                        wait_cnt <= wait_cnt + 1;
                        if wait_cnt >= 30 then
                            wait_cnt <= (others => '0');
                            state <= S_IDLE;
                        end if;

                    when S_IDLE =>
                        if rx_valid = '1' then
                            z_len <= unsigned(rx_data);
                            state <= S_READ_MLEN;
                        end if;

                    when S_READ_MLEN =>
                        if rx_valid = '1' then
                            m_len <= unsigned(rx_data);
                            state <= S_READ_OUTLEN;
                        end if;

                    when S_READ_OUTLEN =>
                        if rx_valid = '1' then
                            out_len <= unsigned(rx_data);
                            blocks_needed <= resize((unsigned(rx_data) + 7) / 8, 5);
                            byte_counter <= (others => '0');
                            accum_idx <= (others => '0');
                            accum_reg <= (others => '0');
                            state <= S_START_Z;
                        end if;

                    -- ========================================
                    -- Z PHASE
                    -- ========================================
                    when S_START_Z =>
                        -- Hold start_z until buffer reaches STREAM_Z (hash_ready='1')
                        hash_start_z <= '1';
                        if hash_ready = '1' then
                            state <= S_WAIT_Z_READY;
                        end if;

                    when S_WAIT_Z_READY =>
                        if hash_ready = '1' then
                            if z_len = 0 then
                                -- Empty Z
                                hash_data_in <= (others => '0');
                                hash_valid_bytes <= (others => '0');
                                hash_last_word <= '1';
                                hash_data_valid <= '1';
                                state <= S_WAIT_Z_DONE;
                            else
                                state <= S_READ_Z;
                            end if;
                        end if;

                    when S_READ_Z =>
                        if hash_ready = '1' and rx_valid = '1' then
                            -- Pack byte into accumulator (LSB first for buffer compatibility)
                            case accum_idx is
                                when "000" => accum_reg(7 downto 0)   <= rx_data;
                                when "001" => accum_reg(15 downto 8)  <= rx_data;
                                when "010" => accum_reg(23 downto 16) <= rx_data;
                                when "011" => accum_reg(31 downto 24) <= rx_data;
                                when "100" => accum_reg(39 downto 32) <= rx_data;
                                when "101" => accum_reg(47 downto 40) <= rx_data;
                                when "110" => accum_reg(55 downto 48) <= rx_data;
                                when "111" => accum_reg(63 downto 56) <= rx_data;
                                when others => null;
                            end case;
                            
                            byte_counter <= byte_counter + 1;
                            accum_idx <= accum_idx + 1;  -- Always increment
                            
                            -- CHECK FOR END OF Z
                            if byte_counter + 1 = z_len then
                                -- This is the LAST byte of Z
                                if accum_idx = "111" then 
                                    -- FULL 8-BYTE LAST WORD:
                                    -- Send this word as THE last word.
                                    -- Buffer will absorb with P12, then add padding separately.
                                    hash_data_in <= rx_data & accum_reg(55 downto 0);
                                    hash_valid_bytes <= (others => '0'); -- 8 valid bytes
                                    hash_last_word <= '1';               -- THIS IS LAST
                                    hash_data_valid <= '1';
                                    
                                    -- Go directly to WAIT state (no extra empty word)
                                    byte_counter <= (others => '0');
                                    accum_idx <= (others => '0');
                                    accum_reg <= (others => '0');
                                    state <= S_WAIT_Z_DONE;
                                else
                                    -- Partial last word
                                    state <= S_SEND_Z_LAST;
                                end if;
                            
                            elsif accum_idx = "111" then
                                -- Full 64-bit word ready (accumulation wrap)
                                hash_data_in <= rx_data & accum_reg(55 downto 0);
                                hash_valid_bytes <= (others => '0'); 
                                hash_last_word <= '0';
                                hash_data_valid <= '1';
                                accum_reg <= (others => '0');
                            end if;
                        end if;

                    when S_SEND_Z_LAST =>
                        if hash_ready = '1' then
                            hash_data_in <= accum_reg;
                            hash_valid_bytes <= accum_idx;
                            hash_last_word <= '1';
                            hash_data_valid <= '1';
                            byte_counter <= (others => '0');
                            accum_idx <= (others => '0');
                            accum_reg <= (others => '0');
                            state <= S_WAIT_Z_DONE;
                        end if;

                    when S_WAIT_Z_DONE =>
                        wait_cnt <= wait_cnt + 1;
                        if wait_cnt >= 5 then  -- Minimal wait, handshake handles the rest
                            wait_cnt <= (others => '0');
                            state <= S_START_M;
                        end if;

                    -- ========================================
                    -- M PHASE
                    -- ========================================
                    when S_START_M =>
                        -- Hold start_m until buffer reaches STREAM_M (hash_ready='1')
                        hash_start_m <= '1';
                        if hash_ready = '1' then
                            state <= S_WAIT_M_READY;
                        end if;

                    when S_WAIT_M_READY =>
                        if hash_ready = '1' then
                            if m_len = 0 then
                                -- Empty M
                                hash_data_in <= (others => '0');
                                hash_valid_bytes <= (others => '0');
                                hash_last_word <= '1';
                                hash_data_valid <= '1';
                                blocks_collected <= (others => '0');
                                await_valid_low <= '0';
                                state <= S_COLLECT_HASH;
                            elsif byte_counter > 0 and accum_idx = "000" then
                                -- Came back from S_READ_M with a full 64-bit word in accum_reg
                                hash_data_in <= accum_reg;
                                hash_valid_bytes <= (others => '0'); -- 8 bytes
                                hash_last_word <= '0';
                                hash_data_valid <= '1';
                                accum_reg <= (others => '0');
                                state <= S_READ_M;  -- Go back to read more
                            else
                                state <= S_READ_M;
                            end if;
                        end if;

                    when S_READ_M =>
                        -- Wait for UART byte first
                        if rx_valid = '1' then
                            -- Pack byte into accumulator (LSB first for buffer compatibility)
                            case accum_idx is
                                when "000" => accum_reg(7 downto 0)   <= rx_data;
                                when "001" => accum_reg(15 downto 8)  <= rx_data;
                                when "010" => accum_reg(23 downto 16) <= rx_data;
                                when "011" => accum_reg(31 downto 24) <= rx_data;
                                when "100" => accum_reg(39 downto 32) <= rx_data;
                                when "101" => accum_reg(47 downto 40) <= rx_data;
                                when "110" => accum_reg(55 downto 48) <= rx_data;
                                when "111" => accum_reg(63 downto 56) <= rx_data;
                                when others => null;
                            end case;
                            
                            byte_counter <= byte_counter + 1;
                            accum_idx <= accum_idx + 1;  -- Always increment
                            
                            -- CHECK FOR END OF M
                            if byte_counter + 1 = m_len then
                                -- Last M byte
                                if accum_idx = "111" then
                                    -- FULL 8-BYTE LAST WORD:
                                    hash_data_in <= rx_data & accum_reg(55 downto 0);
                                    hash_valid_bytes <= (others => '0');
                                    hash_last_word <= '1';
                                    hash_data_valid <= '1';
                                    blocks_collected <= (others => '0');
                                    await_valid_low <= '0';
                                    state <= S_COLLECT_HASH;
                                else
                                    state <= S_SEND_M_LAST;
                                end if;
                            
                            elsif accum_idx = "111" then
                                -- Full word to send
                                state <= S_WAIT_M_READY; 
                             end if;
                        end if;

                    when S_SEND_M_LAST =>
                        if hash_ready = '1' then
                            hash_data_in <= accum_reg;
                            hash_valid_bytes <= accum_idx;
                            hash_last_word <= '1';
                            hash_data_valid <= '1';
                            blocks_collected <= (others => '0');
                            await_valid_low <= '0';
                            state <= S_COLLECT_HASH;
                        end if;

                    -- ========================================
                    -- COLLECT HASH
                    -- ========================================
                    when S_COLLECT_HASH =>
                        if await_valid_low = '0' then
                            if hash_out_valid = '0' then
                                await_valid_low <= '1';
                            end if;
                        else
                            if hash_out_valid = '1' then
                                hash_blocks(to_integer(blocks_collected)) <= hash_out;
                                blocks_collected <= blocks_collected + 1;
                                
                                if blocks_collected + 1 >= blocks_needed then
                                    bytes_sent <= (others => '0');
                                    tx_block_idx <= (others => '0');
                                    tx_byte_idx <= (others => '0');
                                    state <= S_TX_BYTE;
                                else
                                    await_valid_low <= '0';
                                end if;
                            end if;
                        end if;

                    -- ========================================
                    -- TRANSMIT
                    -- ========================================
                    when S_TX_BYTE =>
                        if tx_busy = '0' then
                            current_block := hash_blocks(to_integer(tx_block_idx));
                            
                            case tx_byte_idx is
                                when "000" => tx_data <= current_block(63 downto 56);
                                when "001" => tx_data <= current_block(55 downto 48);
                                when "010" => tx_data <= current_block(47 downto 40);
                                when "011" => tx_data <= current_block(39 downto 32);
                                when "100" => tx_data <= current_block(31 downto 24);
                                when "101" => tx_data <= current_block(23 downto 16);
                                when "110" => tx_data <= current_block(15 downto 8);
                                when "111" => tx_data <= current_block(7 downto 0);
                                when others => null;
                            end case;
                            tx_start <= '1';
                            state <= S_TX_WAIT;
                        end if;

                    when S_TX_WAIT =>
                        if tx_done = '1' then
                            bytes_sent <= bytes_sent + 1;
                            
                            if bytes_sent + 1 >= out_len then
                                state <= S_DONE;
                            elsif tx_byte_idx = "111" then
                                tx_byte_idx <= (others => '0');
                                tx_block_idx <= tx_block_idx + 1;
                                state <= S_TX_BYTE;
                            else
                                tx_byte_idx <= tx_byte_idx + 1;
                                state <= S_TX_BYTE;
                            end if;
                        end if;

                    when S_DONE =>
                        state <= S_IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
