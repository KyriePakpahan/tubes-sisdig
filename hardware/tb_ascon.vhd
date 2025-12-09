library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;
use IEEE.std_logic_textio.all;

entity tb_ascon is
end tb_ascon;

architecture Behavioral of tb_ascon is
    -- Component Declaration
    component ascon_cxof128_top
        Port (
            clk, rst      : in  std_logic;
            z_bit_len     : in  std_logic_vector(63 downto 0);
            out_len_bits  : in  std_logic_vector(31 downto 0);
            start_z       : in  std_logic;
            start_m       : in  std_logic;
            data_in       : in  std_logic_vector(63 downto 0);
            valid_bytes   : in  unsigned(2 downto 0);
            last_word     : in  std_logic;
            data_valid    : in  std_logic;
            buffer_ready  : out std_logic;
            hash_out      : out std_logic_vector(63 downto 0);
            hash_valid    : out std_logic
        );
    end component;

    -- Signals
    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    signal z_bit_len     : std_logic_vector(63 downto 0) := (others => '0');
    signal out_len_bits  : std_logic_vector(31 downto 0) := (others => '0');
    signal start_z, start_m : std_logic := '0';
    signal data_in       : std_logic_vector(63 downto 0) := (others => '0');
    signal valid_bytes   : unsigned(2 downto 0) := (others => '0');
    signal last_word, data_valid : std_logic := '0';
    signal buffer_ready  : std_logic;
    signal hash_out      : std_logic_vector(63 downto 0);
    signal hash_valid    : std_logic;

    constant CLK_PERIOD : time := 10 ns;

begin
    -- Instantiate UUT
    UUT: ascon_cxof128_top
    port map (
        clk => clk, rst => rst,
        z_bit_len => z_bit_len, out_len_bits => out_len_bits,
        start_z => start_z, start_m => start_m,
        data_in => data_in, valid_bytes => valid_bytes,
        last_word => last_word, data_valid => data_valid,
        buffer_ready => buffer_ready,
        hash_out => hash_out, hash_valid => hash_valid
    );

    -- Clock Process
    process
    begin
        clk <= '0'; wait for CLK_PERIOD/2;
        clk <= '1'; wait for CLK_PERIOD/2;
    end process;

    -- Stimulus Process
    process
    begin
        -- Initialize all inputs to default values
        -- Test Case 35: Z=0x10 (1 byte=8 bits), Msg=0x00 (1 byte)
        z_bit_len <= std_logic_vector(to_unsigned(8, 64));  -- 1 byte = 8 bits
        out_len_bits <= std_logic_vector(to_unsigned(512, 32));
        start_z <= '0'; 
        start_m <= '0';
        data_in <= (others => '0');
        valid_bytes <= to_unsigned(0, 3);
        last_word <= '0';
        data_valid <= '0';
        
        -- Reset
        rst <= '1';
        wait for CLK_PERIOD*5;
        rst <= '0';
        wait for CLK_PERIOD*5;
        
        report "Starting Simulation: Test Case 35 (Z=0x10, Msg=0x00)";
        report "Expected first block: 63FA8BA86382F2D5";

        -- Start Z
        start_z <= '1';
        wait for 0 ns;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        start_z <= '0';
        
        -- Feed Z Data: 0x10 (1 byte)
        report "Waiting for buffer_ready for Z...";
        for i in 0 to 500 loop
            wait until rising_edge(clk);
            if buffer_ready = '1' then exit; end if;
        end loop;
        
        data_in <= x"0000000000000010";  -- Z data = 0x10, LSB-aligned
        valid_bytes <= to_unsigned(1, 3); -- 1 valid byte
        last_word <= '1'; -- Last word of Z
        data_valid <= '1';
        report "Driving Z Data: 0x10 (1 byte)";
        -- Wait for buffer to transition out of STREAM_Z (buffer_ready will go low)
        wait until rising_edge(clk) and buffer_ready = '0';
        report "Buffer consumed Z data";
        data_valid <= '0';
        last_word <= '0';
        
        -- Wait for Z P12 to complete and buffer to reach WAIT_M
        wait for CLK_PERIOD * 20;  -- Wait for P12 to complete

        -- Start M (Empty) - hold start_m until buffer responds
        start_m <= '1';
        wait for 0 ns;
        report "Starting M Phase, waiting for buffer to accept";
        wait until rising_edge(clk) and buffer_ready = '1';  -- Buffer accepted and is ready for M data
        start_m <= '0';
        report "Buffer accepted M phase";

        -- Feed M Data (Empty)
        -- Wait for buffer to be ready for M data
        wait until rising_edge(clk) and buffer_ready = '1';
        data_in <= x"0000000000000000";  -- M data = 0x00
        valid_bytes <= to_unsigned(1, 3);  -- 1 valid byte
        last_word <= '1';
        data_valid <= '1';
        report "Driving M Data: 0x00 (1 byte)";
        wait until rising_edge(clk) and buffer_ready = '0';
        report "Buffer consumed M data";
        data_valid <= '0';
        last_word <= '0';

        wait;
    end process;
    
    -- Monitor Process
    process(clk)
        variable l : line;
    begin
        if rising_edge(clk) then
            if hash_valid = '1' then
                write(l, string'("Hash Output Block: "));
                hwrite(l, hash_out);
                writeline(output, l);
                -- Also print byte-by-byte (LSB first)
                write(l, string'("Bytes (LSB first): "));
                for i in 0 to 7 loop
                    hwrite(l, hash_out(i*8+7 downto i*8));
                    write(l, string'(" "));
                end loop;
                writeline(output, l);
            end if;
        end if;
    end process;

end Behavioral;
