-- ============================================================================
-- ASCON FPGA TOP - Complete FPGA Implementation with UART
-- ============================================================================
-- This is the complete top-level module for FPGA deployment.
-- It integrates:
--   - UART RX: Receive data from PC/terminal
--   - UART TX: Transmit hash output back to PC/terminal
--   - Ascon CXOF128: The hash function engine
--   - TX Controller: Serialize 64-bit hash blocks to 8-byte UART transmission
--   - Button debouncing and LED status indicators
--
-- Usage Flow:
--   1. Set sw_z_len (Z length in bytes) and sw_out_len (output length in bytes)
--   2. Press btn_start_z to begin Z (customization string) phase
--   3. Send Z data via UART (if z_len > 0)
--   4. Press btn_finish when done sending Z data
--   5. Press btn_start_m to begin M (message) phase
--   6. Send M data via UART
--   7. Press btn_finish when done sending M data
--   8. Hash output will automatically be transmitted via UART TX
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ascon_fpga_top is
    Generic (
        -- Clock frequency / Baud rate
        -- Example: 100 MHz / 115200 = 868
        -- Example: 10 MHz / 115200 = 87
        CLKS_PER_BIT : integer := 868
    );
    Port (
        -- Clock and Reset
        clk         : in  std_logic;                      -- System clock
        rst_n       : in  std_logic;                      -- Active-low reset
        
        -- UART Interface
        uart_rx_pin : in  std_logic;                      -- UART receive line
        uart_tx_pin : out std_logic;                      -- UART transmit line
        
        -- Button Inputs (directly from FPGA buttons)
        btn_start_z : in  std_logic;                      -- Start Z phase
        btn_start_m : in  std_logic;                      -- Start M phase  
        btn_finish  : in  std_logic;                      -- Finish current phase
        
        -- Switch Inputs (directly from FPGA switches)
        sw_z_len    : in  std_logic_vector(7 downto 0);   -- Z length in bytes
        sw_out_len  : in  std_logic_vector(7 downto 0);   -- Output length in bytes
        
        -- LED Outputs (directly to FPGA LEDs)
        led_ready   : out std_logic;                      -- Ready to receive data
        led_busy    : out std_logic;                      -- Processing/transmitting
        led_done    : out std_logic;                      -- Hash output complete
        led_rx      : out std_logic                       -- UART RX activity indicator
    );
end ascon_fpga_top;

architecture Behavioral of ascon_fpga_top is

    -- ========================================================================
    -- INTERNAL SIGNALS
    -- ========================================================================
    
    -- Reset (active high internal)
    signal rst : std_logic;
    
    -- UART RX Signals
    signal uart_rx_data   : std_logic_vector(7 downto 0);
    signal uart_rx_valid  : std_logic;
    
    -- UART TX Signals
    signal uart_tx_data   : std_logic_vector(7 downto 0);
    signal uart_tx_start  : std_logic;
    signal uart_tx_busy   : std_logic;
    signal uart_tx_done   : std_logic;
    
    -- Data accumulator (packs 8 bytes into 64-bit words)
    signal accum_reg      : std_logic_vector(63 downto 0) := (others => '0');
    signal byte_counter   : integer range 0 to 8 := 0;
    
    -- Ascon Interface Signals
    signal ascon_z_len    : std_logic_vector(63 downto 0);  -- Z length in bits
    signal ascon_out_len  : std_logic_vector(31 downto 0);  -- Output length in bits
    signal ascon_data_in  : std_logic_vector(63 downto 0);
    signal ascon_valid_bytes : unsigned(2 downto 0);
    signal ascon_last_word: std_logic;
    signal ascon_data_valid : std_logic;
    signal ascon_ready    : std_logic;
    signal ascon_hash_out : std_logic_vector(63 downto 0);
    signal ascon_hash_valid : std_logic;
    
    -- TX Controller State Machine
    type tx_state_type is (
        TX_IDLE,           -- Waiting for hash output
        TX_WAIT_HASH,      -- Wait for hash to be valid
        TX_SEND_BYTE,      -- Send one byte via UART
        TX_WAIT_UART,      -- Wait for UART TX to complete
        TX_NEXT_BYTE,      -- Move to next byte
        TX_NEXT_BLOCK,     -- Request next 64-bit block
        TX_DONE            -- All bytes transmitted
    );
    signal tx_state : tx_state_type := TX_IDLE;
    
    -- TX Controller Counters
    signal tx_byte_idx    : integer range 0 to 7 := 0;    -- Current byte within 64-bit block
    signal tx_bytes_sent  : unsigned(15 downto 0) := (others => '0'); -- Total bytes sent
    signal tx_bytes_total : unsigned(15 downto 0) := (others => '0'); -- Total bytes to send
    signal tx_hash_block  : std_logic_vector(63 downto 0); -- Current 64-bit hash block
    
    -- Top-level State Machine
    type main_state_type is (
        RESET_STATE,       -- Initial reset
        INIT_IV_PERM,      -- Wait for IV permutation
        IDLE_RUN,          -- Normal operation
        TRANSMIT_HASH      -- Transmitting hash output
    );
    signal main_state : main_state_type := RESET_STATE;
    
    -- Control signals for Ascon core
    signal ctrl_init_state : std_logic := '0';
    signal w_core_busy    : std_logic;
    signal w_perm_done    : std_logic;
    signal w_block_data   : std_logic_vector(63 downto 0);
    signal w_block_valid  : std_logic;
    signal w_cmd_squeeze  : std_logic;
    signal buf_ready_raw  : std_logic;
    signal comb_start_perm : std_logic;

    -- Debounced button signals
    signal btn_start_z_db : std_logic := '0';
    signal btn_start_m_db : std_logic := '0';
    signal btn_finish_db  : std_logic := '0';
    
    -- Button edge detection
    signal btn_start_z_prev : std_logic := '0';
    signal btn_start_m_prev : std_logic := '0';
    signal btn_finish_prev  : std_logic := '0';
    signal btn_start_z_pulse : std_logic := '0';
    signal btn_start_m_pulse : std_logic := '0';
    signal btn_finish_pulse  : std_logic := '0';
    
    -- Simple debounce counter
    signal debounce_ctr : unsigned(19 downto 0) := (others => '0');
    signal debounce_sample : std_logic := '0';

    -- ========================================================================
    -- BYTE SWAP FUNCTION (for correct endianness)
    -- ========================================================================
    function byte_swap(input : std_logic_vector(63 downto 0)) 
        return std_logic_vector is
        variable result : std_logic_vector(63 downto 0);
    begin
        result(63 downto 56) := input(7 downto 0);
        result(55 downto 48) := input(15 downto 8);
        result(47 downto 40) := input(23 downto 16);
        result(39 downto 32) := input(31 downto 24);
        result(31 downto 24) := input(39 downto 32);
        result(23 downto 16) := input(47 downto 40);
        result(15 downto 8)  := input(55 downto 48);
        result(7 downto 0)   := input(63 downto 56);
        return result;
    end function;

begin

    -- ========================================================================
    -- ACTIVE-HIGH RESET CONVERSION
    -- ========================================================================
    rst <= not rst_n;

    -- ========================================================================
    -- DEBOUNCE AND EDGE DETECTION
    -- ========================================================================
    -- Sample buttons every ~10ms (at 100MHz: 2^20 cycles ≈ 10.5ms)
    process(clk)
    begin
        if rising_edge(clk) then
            debounce_ctr <= debounce_ctr + 1;
            debounce_sample <= '0';
            
            if debounce_ctr = 0 then
                debounce_sample <= '1';
                btn_start_z_db <= btn_start_z;
                btn_start_m_db <= btn_start_m;
                btn_finish_db <= btn_finish;
            end if;
            
            -- Edge detection (rising edge = button press)
            btn_start_z_prev <= btn_start_z_db;
            btn_start_m_prev <= btn_start_m_db;
            btn_finish_prev <= btn_finish_db;
            
            btn_start_z_pulse <= btn_start_z_db and not btn_start_z_prev;
            btn_start_m_pulse <= btn_start_m_db and not btn_start_m_prev;
            btn_finish_pulse <= btn_finish_db and not btn_finish_prev;
        end if;
    end process;

    -- ========================================================================
    -- SWITCH TO BIT LENGTH CONVERSION
    -- ========================================================================
    -- Convert byte lengths to bit lengths for Ascon core
    ascon_z_len <= std_logic_vector(resize(unsigned(sw_z_len) * 8, 64));
    ascon_out_len <= std_logic_vector(resize(unsigned(sw_out_len) * 8, 32));
    
    -- Total bytes to transmit
    tx_bytes_total <= resize(unsigned(sw_out_len), 16);

    -- ========================================================================
    -- UART RX INSTANTIATION
    -- ========================================================================
    U_UART_RX : entity work.uart_rx
    generic map ( CLKS_PER_BIT => CLKS_PER_BIT )
    port map (
        clk        => clk,
        rx_serial  => uart_rx_pin,
        data_out   => uart_rx_data,
        data_valid => uart_rx_valid
    );

    -- ========================================================================
    -- UART TX INSTANTIATION
    -- ========================================================================
    U_UART_TX : entity work.uart_tx
    generic map ( CLKS_PER_BIT => CLKS_PER_BIT )
    port map (
        clk        => clk,
        tx_start   => uart_tx_start,
        data_in    => uart_tx_data,
        tx_serial  => uart_tx_pin,
        tx_busy    => uart_tx_busy,
        tx_done    => uart_tx_done
    );

    -- ========================================================================
    -- CXOF BUFFER INSTANTIATION
    -- ========================================================================
    U_BUFFER: entity work.cxof_buffer
    port map (
        clk          => clk,
        rst          => rst,
        z_bit_len    => ascon_z_len,
        out_len_bits => ascon_out_len,
        start_z      => btn_start_z_pulse,
        start_m      => btn_start_m_pulse,
        data_in      => ascon_data_in,
        valid_bytes  => ascon_valid_bytes,
        last_word    => ascon_last_word,
        data_valid   => ascon_data_valid,
        buffer_ready => buf_ready_raw,
        block_out    => w_block_data,
        block_valid  => w_block_valid,
        cmd_perm     => open,
        cmd_squeeze  => w_cmd_squeeze,
        domain_sep   => open,
        core_busy    => w_core_busy
    );

    -- ========================================================================
    -- ASCON CORE INSTANTIATION
    -- ========================================================================
    -- Start permutation when: Buffer sends data OR Buffer requests squeeze OR Init state
    comb_start_perm <= '1' when (w_block_valid = '1') or (w_cmd_squeeze = '1') or (main_state = INIT_IV_PERM) else '0';

    U_CORE: entity work.ascon_cxof128_core
    port map (
        clk        => clk,
        rst        => rst,
        start_perm => comb_start_perm,
        absorb_en  => w_block_valid,
        init_state => ctrl_init_state,
        block_in   => w_block_data,
        block_out  => ascon_hash_out,
        core_busy  => w_core_busy,
        perm_done  => w_perm_done
    );
    
    -- Hash is valid when core is idle and we're in normal run state
    ascon_hash_valid <= not w_core_busy when (main_state = IDLE_RUN or main_state = TRANSMIT_HASH) else '0';
    ascon_ready <= buf_ready_raw when (main_state = IDLE_RUN) else '0';

    -- ========================================================================
    -- LED OUTPUTS
    -- ========================================================================
    led_ready <= ascon_ready;
    led_busy <= '1' when (main_state = INIT_IV_PERM or tx_state /= TX_IDLE or w_core_busy = '1') else '0';
    led_done <= '1' when (tx_state = TX_DONE) else '0';
    led_rx <= uart_rx_valid;

    -- ========================================================================
    -- MAIN STATE MACHINE (Initialization)
    -- ========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                main_state <= RESET_STATE;
                ctrl_init_state <= '0';
            else
                case main_state is
                    when RESET_STATE =>
                        ctrl_init_state <= '1';
                        main_state <= INIT_IV_PERM;
                        
                    when INIT_IV_PERM =>
                        ctrl_init_state <= '0';
                        if w_perm_done = '1' then
                            main_state <= IDLE_RUN;
                        end if;
                        
                    when IDLE_RUN =>
                        -- Transition to transmit when squeeze phase starts
                        if w_cmd_squeeze = '1' then
                            main_state <= TRANSMIT_HASH;
                        end if;
                        
                    when TRANSMIT_HASH =>
                        if tx_state = TX_DONE then
                            main_state <= IDLE_RUN;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- UART RX TO ASCON DATA PACKING
    -- ========================================================================
    -- Accumulates 8 incoming UART bytes into 64-bit words for Ascon
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                accum_reg <= (others => '0');
                byte_counter <= 0;
                ascon_data_valid <= '0';
                ascon_last_word <= '0';
            else
                -- Default: clear pulse signals
                ascon_data_valid <= '0';
                ascon_last_word <= '0';
                
                -- Pack incoming UART bytes into 64-bit words
                if uart_rx_valid = '1' then
                    case byte_counter is
                        when 0 => accum_reg(7 downto 0)   <= uart_rx_data;
                        when 1 => accum_reg(15 downto 8)  <= uart_rx_data;
                        when 2 => accum_reg(23 downto 16) <= uart_rx_data;
                        when 3 => accum_reg(31 downto 24) <= uart_rx_data;
                        when 4 => accum_reg(39 downto 32) <= uart_rx_data;
                        when 5 => accum_reg(47 downto 40) <= uart_rx_data;
                        when 6 => accum_reg(55 downto 48) <= uart_rx_data;
                        when 7 => accum_reg(63 downto 56) <= uart_rx_data;
                        when others => null;
                    end case;
                    
                    if byte_counter = 7 then
                        -- Full 64-bit word received
                        ascon_data_in <= uart_rx_data & accum_reg(55 downto 0);
                        ascon_data_valid <= '1';
                        ascon_last_word <= '0';
                        ascon_valid_bytes <= to_unsigned(0, 3); -- All 8 bytes valid (0 means 8)
                        byte_counter <= 0;
                        accum_reg <= (others => '0');
                    else
                        byte_counter <= byte_counter + 1;
                    end if;
                    
                -- Handle finish button - send partial word with padding info
                elsif btn_finish_pulse = '1' then
                    if byte_counter > 0 then
                        ascon_data_in <= accum_reg;
                        ascon_data_valid <= '1';
                        ascon_last_word <= '1';
                        ascon_valid_bytes <= to_unsigned(byte_counter, 3);
                        byte_counter <= 0;
                        accum_reg <= (others => '0');
                    else
                        -- No pending bytes, just signal last word with 0 bytes
                        ascon_data_in <= (others => '0');
                        ascon_data_valid <= '1';
                        ascon_last_word <= '1';
                        ascon_valid_bytes <= to_unsigned(0, 3);
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- TX CONTROLLER STATE MACHINE
    -- ========================================================================
    -- Serializes 64-bit hash blocks into 8-byte UART transmissions
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tx_state <= TX_IDLE;
                tx_byte_idx <= 0;
                tx_bytes_sent <= (others => '0');
                uart_tx_start <= '0';
                uart_tx_data <= (others => '0');
            else
                -- Default: clear start pulse
                uart_tx_start <= '0';
                
                case tx_state is
                    when TX_IDLE =>
                        tx_bytes_sent <= (others => '0');
                        tx_byte_idx <= 0;
                        -- Start transmitting when squeeze mode is active and hash is valid
                        if w_cmd_squeeze = '1' and ascon_hash_valid = '1' then
                            -- Capture the current hash block (byte-swapped for big-endian output)
                            tx_hash_block <= byte_swap(ascon_hash_out);
                            tx_state <= TX_SEND_BYTE;
                        end if;
                        
                    when TX_WAIT_HASH =>
                        -- Wait for next hash block to be valid
                        if ascon_hash_valid = '1' then
                            tx_hash_block <= byte_swap(ascon_hash_out);
                            tx_state <= TX_SEND_BYTE;
                        end if;
                        
                    when TX_SEND_BYTE =>
                        -- Send current byte if UART TX is not busy
                        if uart_tx_busy = '0' then
                            -- Extract byte from 64-bit block (MSB first)
                            case tx_byte_idx is
                                when 0 => uart_tx_data <= tx_hash_block(63 downto 56);
                                when 1 => uart_tx_data <= tx_hash_block(55 downto 48);
                                when 2 => uart_tx_data <= tx_hash_block(47 downto 40);
                                when 3 => uart_tx_data <= tx_hash_block(39 downto 32);
                                when 4 => uart_tx_data <= tx_hash_block(31 downto 24);
                                when 5 => uart_tx_data <= tx_hash_block(23 downto 16);
                                when 6 => uart_tx_data <= tx_hash_block(15 downto 8);
                                when 7 => uart_tx_data <= tx_hash_block(7 downto 0);
                            end case;
                            uart_tx_start <= '1';
                            tx_state <= TX_WAIT_UART;
                        end if;
                        
                    when TX_WAIT_UART =>
                        -- Wait for UART TX to complete
                        if uart_tx_done = '1' then
                            tx_bytes_sent <= tx_bytes_sent + 1;
                            tx_state <= TX_NEXT_BYTE;
                        end if;
                        
                    when TX_NEXT_BYTE =>
                        -- Check if all bytes sent
                        if tx_bytes_sent >= tx_bytes_total then
                            tx_state <= TX_DONE;
                        elsif tx_byte_idx = 7 then
                            -- Need next 64-bit block
                            tx_byte_idx <= 0;
                            tx_state <= TX_NEXT_BLOCK;
                        else
                            -- More bytes in current block
                            tx_byte_idx <= tx_byte_idx + 1;
                            tx_state <= TX_SEND_BYTE;
                        end if;
                        
                    when TX_NEXT_BLOCK =>
                        -- Wait for next hash block from squeeze
                        -- The buffer/core will run another P12 for the next block
                        tx_state <= TX_WAIT_HASH;
                        
                    when TX_DONE =>
                        -- Stay in done state until next operation
                        -- Reset on next start_z
                        if btn_start_z_pulse = '1' then
                            tx_state <= TX_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

end Behavioral;
