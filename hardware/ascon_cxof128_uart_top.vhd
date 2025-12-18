library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ascon_uart_top is
    Port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        rx_line       : in  std_logic; 
        
        btn_start_z   : in  std_logic; 
        btn_start_m   : in  std_logic; 
        btn_finish    : in  std_logic; 
        
        -- Input Panjang dari User (Menggunakan Switch)
        sw_z_len_byte   : in  std_logic_vector(7 downto 0); -- Panjang Z (Byte)
        sw_out_len_byte : in  std_logic_vector(7 downto 0); -- [BARU] Panjang Output (Byte)
        -- Contoh: Jika ingin 32 Byte (256 bit) hash, set switch ini ke 32.
        
        led_ready     : out std_logic;
        led_valid_out : out std_logic;
        
        core_block_out : out std_logic_vector(63 downto 0);
        core_block_val : out std_logic
    );
end ascon_uart_top;

architecture Behavioral of ascon_uart_top is

    signal uart_data_byte : std_logic_vector(7 downto 0);
    signal uart_byte_val  : std_logic;
    
    signal accum_reg      : std_logic_vector(63 downto 0) := (others => '0');
    signal byte_counter   : integer range 0 to 8 := 0;
    
    signal buf_z_len      : std_logic_vector(63 downto 0);
    signal buf_out_len    : std_logic_vector(31 downto 0); -- Sinyal Internal Panjang Output
    
    signal buf_data_in    : std_logic_vector(63 downto 0);
    signal buf_valid_bytes: unsigned(2 downto 0);
    signal buf_last_word  : std_logic;
    signal buf_data_valid : std_logic;
    signal buf_ready      : std_logic;
    
    signal w_block_data   : std_logic_vector(63 downto 0);
    signal w_block_valid  : std_logic;
    signal w_core_busy    : std_logic;
    signal w_perm_done    : std_logic;
    signal w_core_out     : std_logic_vector(63 downto 0);
    
    signal ctrl_init_state : std_logic := '0';
    signal buf_ready_raw   : std_logic;
    signal comb_start_perm : std_logic;
    
    -- Sinyal baru dari buffer
    signal w_cmd_squeeze   : std_logic; 

    -- FSM Top Level
    type state_type is (RESET_STATE, INIT_IV_PERM, IDLE_RUN);
    signal main_state : state_type := RESET_STATE;

begin

    -- Konversi Switch Byte ke Bit
    buf_z_len <= std_logic_vector(resize(unsigned(sw_z_len_byte) * 8, 64));
    
    -- [BARU] Konversi Panjang Output ke Bit (Max 255 byte * 8 = 2040 bit)
    buf_out_len <= std_logic_vector(resize(unsigned(sw_out_len_byte) * 8, 32));

    U_UART_RX : entity work.uart_rx
    generic map ( CLKS_PER_BIT => 868 ) 
    port map (clk, rx_line, uart_data_byte, uart_byte_val);

    U_BUFFER: entity work.cxof_buffer
    port map (
        clk => clk, rst => rst,
        z_bit_len => buf_z_len, 
        out_len_bits => buf_out_len, -- [BARU] Masuk ke Buffer
        
        start_z => btn_start_z, start_m => btn_start_m,
        data_in => buf_data_in, valid_bytes => buf_valid_bytes, last_word => buf_last_word, data_valid => buf_data_valid,
        buffer_ready => buf_ready_raw,
        block_out => w_block_data,
        block_valid => w_block_valid,
        
        cmd_squeeze => w_cmd_squeeze, -- [BARU] Sinyal perintah squeeze
        domain_sep => open,
        core_busy => w_core_busy
    );

    -- Start jika: Buffer kirim data valid ATAU Init state
    -- REMOVED w_cmd_squeeze to prevent skipping first block
    comb_start_perm <= '1' when (w_block_valid = '1') or (main_state = INIT_IV_PERM) else '0';

    U_CORE: entity work.ascon_cxof128_core
    port map (
        clk => clk, rst => rst,
        start_perm => comb_start_perm, 
        absorb_en => w_block_valid, -- Absorb hanya aktif jika buffer kirim data (saat squeeze, ini 0)
        init_state => ctrl_init_state,
        block_in => w_block_data,
        block_out => w_core_out,
        core_busy => w_core_busy,
        perm_done => w_perm_done
    );

    core_block_out <= w_core_out;
    
    -- Output valid jika core tidak busy dan kita ada di state IDLE/RUN
    core_block_val <= not w_core_busy when (main_state = IDLE_RUN) else '0';
    
    led_ready <= buf_ready_raw when (main_state = IDLE_RUN) else '0';
    led_valid_out <= not w_core_busy when (main_state = IDLE_RUN) else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                accum_reg <= (others => '0');
                byte_counter <= 0;
                buf_data_valid <= '0';
                buf_last_word <= '0';
                main_state <= RESET_STATE;
                ctrl_init_state <= '0';
            else
                -- FSM Init Control
                case main_state is
                    when RESET_STATE =>
                        ctrl_init_state <= '1'; main_state <= INIT_IV_PERM;
                    when INIT_IV_PERM =>
                        ctrl_init_state <= '0';
                        if w_perm_done = '1' then main_state <= IDLE_RUN; end if;
                    when IDLE_RUN => null;
                end case;

                -- UART Packing Logic (Standard)
                buf_data_valid <= '0';
                buf_last_word <= '0';

                if uart_byte_val = '1' then
                    case byte_counter is
                        when 0 => accum_reg(7 downto 0)   <= uart_data_byte;
                        when 1 => accum_reg(15 downto 8)  <= uart_data_byte;
                        when 2 => accum_reg(23 downto 16) <= uart_data_byte;
                        when 3 => accum_reg(31 downto 24) <= uart_data_byte;
                        when 4 => accum_reg(39 downto 32) <= uart_data_byte;
                        when 5 => accum_reg(47 downto 40) <= uart_data_byte;
                        when 6 => accum_reg(55 downto 48) <= uart_data_byte;
                        when 7 => accum_reg(63 downto 56) <= uart_data_byte;
                        when others => null;
                    end case;
                    
                    if byte_counter = 7 then
                        buf_data_in <= uart_data_byte & accum_reg(55 downto 0);
                        buf_data_valid <= '1';
                        buf_last_word <= '0';
                        buf_valid_bytes <= to_unsigned(0, 3);
                        byte_counter <= 0;
                        accum_reg <= (others => '0'); 
                    else
                        byte_counter <= byte_counter + 1;
                    end if;
                
                elsif btn_finish = '1' then
                    if byte_counter > 0 then
                        buf_data_in <= accum_reg;
                        buf_data_valid <= '1';
                        buf_last_word <= '1';
                        buf_valid_bytes <= to_unsigned(byte_counter, 3);
                        byte_counter <= 0;
                        accum_reg <= (others => '0'); 
                    elsif byte_counter = 0 then
                         null; 
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;