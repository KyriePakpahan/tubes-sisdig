-- ============================================================================
-- ASCON CXOF128 TOP - Top-Level Wrapper
-- ============================================================================
-- This is the main interface module that connects all components of the
-- Ascon-CXOF128 hash function implementation.
--
-- Architecture Overview:
-- +------------------------------------------------------------------+
-- |                    ascon_cxof128_top                             |
-- |                                                                  |
-- |  +------------------+        +------------------------+          |
-- |  |   cxof_buffer    |  --->  |   ascon_cxof128_core   |          |
-- |  | (State Machine)  |  <---  |    (Permutation)       |          |
-- |  +------------------+        +------------------------+          |
-- |       ^    |                          |                          |
-- |       |    v                          v                          |
-- |   data_in/out                     hash_out                       |
-- +------------------------------------------------------------------+
--
-- The top module is responsible for:
--   1. Initial Value (IV) setup after reset
--   2. Running the first P12 permutation on the IV
--   3. Connecting the buffer and core modules
--   4. Gating output signals until the initialization is complete
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ascon_cxof128_top is
    Port (
        -- Clock and Reset
        clk, rst      : in  std_logic;
        
        -- Configuration Inputs
        z_bit_len     : in  std_logic_vector(63 downto 0);  -- Z (label) length in bits
        out_len_bits  : in  std_logic_vector(31 downto 0);  -- Desired hash output length in bits
        
        -- Phase Control
        start_z       : in  std_logic;  -- Pulse to start Z absorption phase
        start_m       : in  std_logic;  -- Pulse to start M absorption phase
        
        -- Data Input Interface (streaming)
        data_in       : in  std_logic_vector(63 downto 0);  -- Input data (64-bit words)
        valid_bytes   : in  unsigned(2 downto 0);           -- Number of valid bytes (0-7)
        last_word     : in  std_logic;                       -- High for final data word
        data_valid    : in  std_logic;                       -- High when data_in is valid
        
        -- Handshake Output
        buffer_ready  : out std_logic;  -- High when ready to accept data
        
        -- Hash Output
        hash_out      : out std_logic_vector(63 downto 0);  -- 64-bit output blocks
        hash_valid    : out std_logic                        -- High when hash_out is valid
    );
end ascon_cxof128_top;

architecture Behavioral of ascon_cxof128_top is

    -- ========================================================================
    -- TOP-LEVEL STATE MACHINE
    -- ========================================================================
    -- After reset, we need to:
    --   1. Initialize the core with the IV
    --   2. Run the first P12 permutation
    --   3. Then allow normal operation
    
    type state_type is (
        RESET_STATE,    -- Just came out of reset
        INIT_IV_START,  -- Trigger IV initialization and start P12
        INIT_IV_WAIT,   -- Wait for IV permutation to complete
        IDLE_RUN        -- Normal operation - buffer controls everything
    );
    signal main_state : state_type := RESET_STATE;
    
    -- ========================================================================
    -- INTERNAL SIGNALS
    -- ========================================================================
    
    -- Data path signals between buffer and core
    signal w_block_data : std_logic_vector(63 downto 0);  -- Data from buffer to core
    signal w_core_out   : std_logic_vector(63 downto 0);  -- Output from core (S[0])
    
    -- Control signals
    signal w_block_valid  : std_logic;  -- Buffer wants to absorb data
    signal w_core_busy    : std_logic;  -- Core is running permutation
    signal w_perm_done    : std_logic;  -- Core finished permutation
    signal ctrl_init_state: std_logic;  -- Tell core to reset to IV
    signal buf_ready_raw  : std_logic;  -- Raw buffer_ready from buffer
    signal w_cmd_squeeze  : std_logic;  -- Buffer is in squeeze mode
    signal w_cmd_perm     : std_logic;  -- Buffer requests permutation
    
    -- One-cycle pulse to start the IV permutation
    -- This is critical: we only want ONE P12, not continuous
    -- One-cycle pulse to start the IV permutation
    -- This is critical: we only want ONE P12, not continuous
    signal iv_start_perm : std_logic := '0';
    
    -- Auto-Reset Tracking
    signal transaction_init_done : std_logic := '0';
    signal buf_start_z : std_logic;
    signal internal_reset_pulse : std_logic := '0';
    signal combined_rst : std_logic;

    -- ========================================================================
    -- BYTE SWAP FUNCTION
    -- ========================================================================
    -- Converts from LSB-first (hardware register order) to MSB-first (KAT format)
    -- Example: 0xDAB30BF79E15504F -> 0x4F50159EF70BB3DA
    
    function byte_swap(input : std_logic_vector(63 downto 0)) 
        return std_logic_vector is
        variable result : std_logic_vector(63 downto 0);
    begin
        result(63 downto 56) := input(7 downto 0);   -- Byte 0 -> Byte 7
        result(55 downto 48) := input(15 downto 8);  -- Byte 1 -> Byte 6
        result(47 downto 40) := input(23 downto 16); -- Byte 2 -> Byte 5
        result(39 downto 32) := input(31 downto 24); -- Byte 3 -> Byte 4
        result(31 downto 24) := input(39 downto 32); -- Byte 4 -> Byte 3
        result(23 downto 16) := input(47 downto 40); -- Byte 5 -> Byte 2
        result(15 downto 8)  := input(55 downto 48); -- Byte 6 -> Byte 1
        result(7 downto 0)   := input(63 downto 56); -- Byte 7 -> Byte 0
        return result;
    end function;

begin

    -- Combined Reset: External Reset OR Internal Auto-Reset Pulse
    combined_rst <= rst or internal_reset_pulse;

    -- ========================================================================
    -- COMPONENT INSTANTIATION
    -- ========================================================================
    
    -- Buffer: Controls the data flow and algorithm phases
    U_BUFFER: entity work.cxof_buffer
    port map (
        clk         => clk,
        rst         => combined_rst, -- Force Reset on new transaction
        z_bit_len   => z_bit_len,
        out_len_bits=> out_len_bits,
        start_z     => buf_start_z,
        start_m     => start_m,
        data_in     => data_in,
        valid_bytes => valid_bytes,
        last_word   => last_word,
        data_valid  => data_valid,
        buffer_ready=> buf_ready_raw,
        block_out   => w_block_data,
        block_valid => w_block_valid,
        cmd_perm    => w_cmd_perm,
        cmd_squeeze => w_cmd_squeeze,
        domain_sep  => open,           -- Unused in this implementation
        core_busy   => w_core_busy
    );

    -- Only start the buffer AFTER we have finished the re-initialization
    buf_start_z <= start_z when (transaction_init_done = '1' and main_state = IDLE_RUN) else '0';

    -- Core: The Ascon permutation engine
    U_CORE: entity work.ascon_cxof128_core
    port map (
        clk        => clk,
        rst        => rst,
        -- Permutation starts from: buffer command OR IV init
        -- REMOVED w_cmd_squeeze to prevent skipping the first output block
        start_perm => (w_cmd_perm or iv_start_perm),
        absorb_en  => w_block_valid,
        init_state => ctrl_init_state,
        block_in   => w_block_data,
        block_out  => w_core_out,
        core_busy  => w_core_busy,
        perm_done  => w_perm_done
    );


    -- ========================================================================
    -- OUTPUT SIGNAL ROUTING
    -- ========================================================================
    
    -- Hash output is S[0] with bytes swapped to MSB-first (big-endian)
    -- This matches the format shown in KAT_cxof128.txt
    hash_out <= byte_swap(w_core_out);
    
    -- Only signal buffer_ready after IV initialization is complete
    -- This prevents the buffer from accepting data during startup
    buffer_ready <= buf_ready_raw when (main_state = IDLE_RUN) else '0';
    
    -- Hash output is valid when core is idle and we're in normal operation
    hash_valid <= not w_core_busy when (main_state = IDLE_RUN) else '0';

    -- ========================================================================
    -- INITIALIZATION STATE MACHINE
    -- ========================================================================
    -- Handles the one-time startup sequence after reset.
    
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then 
                -- Reset everything
                main_state <= RESET_STATE; 
                ctrl_init_state <= '0';
                iv_start_perm <= '0';
                internal_reset_pulse <= '0';
            else
                -- Clear the pulse signal by default
                iv_start_perm <= '0';
                internal_reset_pulse <= '0';
                
                case main_state is
                
                    when RESET_STATE => 
                        -- Step 1: Tell the core to initialize with IV
                        ctrl_init_state <= '1';
                        main_state <= INIT_IV_START;
                        
                    when INIT_IV_START =>
                        -- Step 2: Clear init signal and start the IV permutation
                        -- This is a ONE-CYCLE PULSE to start exactly one P12
                        ctrl_init_state <= '0';
                        iv_start_perm <= '1';  -- Pulse!
                        main_state <= INIT_IV_WAIT;
                        
                    when INIT_IV_WAIT => 
                        -- Step 3: Wait for the IV P12 to complete
                        if w_perm_done = '1' then 
                            main_state <= IDLE_RUN; 
                        end if;
                        
                    when IDLE_RUN => 
                        -- Step 4: Normal operation
                        -- Check for new transaction start to trigger re-initialization
                        if start_z = '0' then
                            transaction_init_done <= '0';
                        elsif start_z = '1' and transaction_init_done = '0' then
                            -- New start detected! TRIGGER HARD RESET!
                            transaction_init_done <= '1';
                            internal_reset_pulse <= '1'; -- Activates combined_rst logic
                            main_state <= RESET_STATE;
                            -- No need to set ctrl_init_state here, RESET_STATE does it
                        end if;
                        
                end case;
            end if;
        end if;
    end process;
    
end Behavioral;