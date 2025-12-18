-- ============================================================================
-- ASCON CXOF128 BUFFER - Data Flow Controller
-- ============================================================================
-- This module orchestrates the CXOF128 (Customizable XOF) hash computation.
-- It controls the sequence of absorption and squeezing phases according to
-- the Ascon-CXOF specification.
--
-- The CXOF128 algorithm processes data in this order:
--   1. Initialize with IV, then P12 (done by top module)
--   2. Absorb the customization string length (z_bit_len), then P12
--   3. Absorb the customization string data (Z) + padding, then P12
--   4. Absorb the message data (M) + padding, then P12
--   5. Squeeze out the hash output
--
-- This buffer handles input streaming, padding, and squeeze control.
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cxof_buffer is
    Port (
        -- Clock and Reset
        clk, rst      : in  std_logic;
        
        -- Configuration Inputs
        z_bit_len     : in  std_logic_vector(63 downto 0);  -- Length of Z in BITS (cslen * 8)
        out_len_bits  : in  std_logic_vector(31 downto 0);  -- Desired output length in bits
        
        -- Phase Control
        start_z       : in  std_logic;  -- Pulse to start Z (customization string) phase
        start_m       : in  std_logic;  -- Pulse to start M (message) phase
        
        -- Data Input Interface (streaming)
        data_in       : in  std_logic_vector(63 downto 0);  -- Input data word (64 bits = 8 bytes)
        valid_bytes   : in  unsigned(2 downto 0);           -- Number of valid bytes (0-7)
        last_word     : in  std_logic;                       -- High when this is the final word
        data_valid    : in  std_logic;                       -- High when data_in is valid
        
        -- Handshake
        buffer_ready  : out std_logic;  -- High when ready to accept data
        
        -- Core Interface (to ascon_cxof128_core)
        block_out     : out std_logic_vector(63 downto 0);  -- Data to send to core
        block_valid   : out std_logic;                       -- High to trigger absorption
        cmd_perm      : out std_logic;                       -- High to start permutation
        cmd_squeeze   : out std_logic;                       -- High during squeeze phase
        domain_sep    : out std_logic;                       -- Domain separation (unused)
        core_busy     : in  std_logic                        -- High when core is running
    );
end cxof_buffer;

architecture Behavioral of cxof_buffer is

    -- ========================================================================
    -- STATE MACHINE DEFINITION
    -- ========================================================================
    -- The buffer follows a strict sequence matching the software implementation.
    -- Each state corresponds to a specific phase of the CXOF128 algorithm.
    
    type state_type is (
        IDLE,              -- Waiting for start_z signal
        
        -- Phase 2: Absorb Z length
        ABSORB_CSLEN,      -- Send z_bit_len to core and start P12
        WAIT_CSLEN_PERM,   -- Wait for P12 to complete
        
        -- Phase 3: Absorb Z data
        STREAM_Z,          -- Receive Z data words from input
        ABSORB_Z_PAD,      -- Send padding byte for Z (if needed separately)
        WAIT_Z_PERM,       -- Wait for Z phase P12 to complete
        
        -- Transition between phases
        WAIT_M,            -- Wait for start_m signal
        
        -- Phase 4: Absorb M data
        STREAM_M,          -- Receive M (message) data words from input
        ABSORB_M_PAD,      -- Send padding byte for M (if needed separately)
        WAIT_M_PERM,       -- Wait for M phase P12 to complete
        
        -- Phase 5: Squeeze output
        SQUEEZE_LOOP,      -- Output hash blocks
        SQUEEZE_TRIGGER    -- Trigger P12 for next squeeze block
    );
    
    signal current_state : state_type := IDLE;
    
    -- Counter for tracking how many bits of output remain
    signal squeeze_count : unsigned(31 downto 0);
    
    -- Buffer to hold padding value between clock cycles
    signal pad_buffer : std_logic_vector(63 downto 0);

begin

    -- ========================================================================
    -- MAIN STATE MACHINE PROCESS
    -- ========================================================================
    
    process(clk)
        -- Variables for padding calculation
        variable v_pad_bit : std_logic_vector(63 downto 0);  -- Padding mask
        variable shift_amt : integer;                         -- Bit position for padding
    begin
        if rising_edge(clk) then
        
            -- ================================================================
            -- RESET HANDLING
            -- ================================================================
            if rst = '1' then
                current_state <= IDLE; 
                buffer_ready <= '0';
                block_valid <= '0';
                block_out <= (others => '0'); 
                domain_sep <= '0';
                cmd_squeeze <= '0';
                cmd_perm <= '0';
                
            else
                -- ============================================================
                -- DEFAULT SIGNAL VALUES
                -- ============================================================
                -- These signals are pulses - clear them each cycle unless
                -- explicitly set in the current state.
                block_valid <= '0';
                cmd_perm <= '0';
                cmd_squeeze <= '0'; 
                domain_sep <= '0';
                buffer_ready <= '0';
                
                -- ============================================================
                -- STATE MACHINE
                -- ============================================================
                case current_state is
                
                    -- ========================================================
                    -- IDLE: Wait for operation to start
                    -- ========================================================
                    when IDLE =>
                        -- When start_z is asserted, begin the hashing process
                        if start_z = '1' then
                            current_state <= ABSORB_CSLEN;
                        end if;

                    -- ========================================================
                    -- PHASE 2: ABSORB CUSTOMIZATION STRING LENGTH
                    -- ========================================================
                    -- According to Ascon-CXOF spec, first absorb cslen * 8 (bits)
                    -- then run P12 before processing the actual Z data.
                    
                    when ABSORB_CSLEN =>
                        if core_busy = '0' then
                            -- Send the Z length in bits to the core
                            block_out <= z_bit_len;
                            block_valid <= '1';  -- Trigger absorption
                            cmd_perm <= '1';     -- Also start P12
                            current_state <= WAIT_CSLEN_PERM;
                        end if;

                    when WAIT_CSLEN_PERM =>
                        -- Wait for the P12 permutation to complete
                        if core_busy = '0' then
                            current_state <= STREAM_Z;
                        end if;

                    -- ========================================================
                    -- PHASE 3: ABSORB CUSTOMIZATION STRING DATA (Z)
                    -- ========================================================
                    -- Stream in the Z data word by word. After the last word,
                    -- add padding (0x01) and run P12.
                    
                    when STREAM_Z =>
                        -- Signal that we're ready to receive data ONLY if core is idle
                        if core_busy = '0' then
                            buffer_ready <= '1';
                        else
                            buffer_ready <= '0';
                        end if;
                        
                        if data_valid = '1' and core_busy = '0' then
                            if last_word = '1' then
                                -- This is the final word - need to add padding
                                
                                if valid_bytes = 0 then
                                    -- FULL 8-BYTE LAST WORD:
                                    -- Absorb all 8 bytes with P12, then add padding separately.
                                    block_out <= data_in;
                                    block_valid <= '1';
                                    cmd_perm <= '1';  -- Start P12 for this full block
                                    -- After P12, add padding byte (0x01 at position 0)
                                    pad_buffer <= x"0000000000000001";
                                    current_state <= ABSORB_Z_PAD;
                                    
                                else
                                    -- PARTIAL BLOCK CASE:
                                    -- Combine data with padding in same word.
                                    -- Put 0x01 right after the last valid byte.
                                    shift_amt := to_integer(valid_bytes) * 8;
                                    v_pad_bit := (others => '0');
                                    v_pad_bit(shift_amt+7 downto shift_amt) := x"01";
                                    -- OR the padding into the data
                                    block_out <= data_in or v_pad_bit;
                                    block_valid <= '1';
                                    cmd_perm <= '1';  -- Absorb and start P12
                                    current_state <= WAIT_Z_PERM;
                                end if;
                                
                            else
                                -- FULL BLOCK CASE:
                                -- Full 8-byte block, absorb and run P12
                                block_out <= data_in;
                                block_valid <= '1';
                                cmd_perm <= '1';
                                -- Stay in STREAM_Z for more data
                            end if;
                        end if;

                    when ABSORB_Z_PAD =>
                        -- Send the padding byte (used when Z data was empty)
                        if core_busy = '0' then
                            block_out <= pad_buffer;
                            block_valid <= '1';
                            cmd_perm <= '1';  -- Absorb padding and start P12
                            current_state <= WAIT_Z_PERM;
                        end if;

                    when WAIT_Z_PERM =>
                        -- Wait for Z phase P12 to complete
                        if core_busy = '0' then
                            current_state <= WAIT_M;
                        end if;

                    -- ========================================================
                    -- WAIT FOR MESSAGE PHASE
                    -- ========================================================
                    when WAIT_M =>
                        -- Wait for the user to signal start of message phase
                        if start_m = '1' then
                            current_state <= STREAM_M;
                        end if;

                    -- ========================================================
                    -- PHASE 4: ABSORB MESSAGE DATA (M)
                    -- ========================================================
                    -- Same logic as Z phase: stream data, add padding at end.
                    
                    when STREAM_M =>
                        if core_busy = '0' then
                            buffer_ready <= '1';
                        else
                            buffer_ready <= '0';
                        end if;
                        
                        if data_valid = '1' and core_busy = '0' then
                            if last_word = '1' then
                                if valid_bytes = 0 then
                                    -- FULL 8-BYTE LAST WORD:
                                    -- Absorb with P12, then add padding separately.
                                    block_out <= data_in;
                                    block_valid <= '1';
                                    cmd_perm <= '1';
                                    pad_buffer <= x"0000000000000001";
                                    current_state <= ABSORB_M_PAD;
                                else
                                    -- Partial block with padding
                                    shift_amt := to_integer(valid_bytes) * 8;
                                    v_pad_bit := (others => '0');
                                    v_pad_bit(shift_amt+7 downto shift_amt) := x"01";
                                    block_out <= data_in or v_pad_bit;
                                    block_valid <= '1';
                                    cmd_perm <= '1';
                                    current_state <= WAIT_M_PERM;
                                end if;
                            else
                                -- Full block
                                block_out <= data_in;
                                block_valid <= '1';
                                cmd_perm <= '1';
                            end if;
                        end if;

                    when ABSORB_M_PAD =>
                        -- Send padding for empty message
                        if core_busy = '0' then
                            block_out <= pad_buffer;
                            block_valid <= '1';
                            cmd_perm <= '1';
                            current_state <= WAIT_M_PERM;
                        end if;

                    when WAIT_M_PERM =>
                        -- Wait for M phase P12 to complete
                        if core_busy = '0' then
                            -- Initialize squeeze counter with desired output length
                            squeeze_count <= unsigned(out_len_bits);
                            current_state <= SQUEEZE_LOOP;
                        end if;

                    -- ========================================================
                    -- PHASE 5: SQUEEZE OUTPUT
                    -- ========================================================
                    -- Output hash blocks. Each block is 64 bits.
                    -- After each block (except the last), run P12 for more output.
                    
                    when SQUEEZE_LOOP =>
                        -- Signal that we're in squeeze mode
                        cmd_squeeze <= '1';
                        
                        if squeeze_count > 64 then
                            -- More output needed - run P12 for next block
                            current_state <= SQUEEZE_TRIGGER;
                        else
                            -- Final block - we're done!
                            current_state <= IDLE;
                        end if;

                    when SQUEEZE_TRIGGER =>
                        -- Wait for core, then run P12 for next squeeze block
                        if core_busy = '0' then
                            cmd_perm <= '1';
                            squeeze_count <= squeeze_count - 64;  -- Decrease by 64 bits
                            current_state <= SQUEEZE_LOOP;
                        end if;

                end case;
            end if;
        end if;
    end process;
    
end Behavioral;