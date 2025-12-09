-- ============================================================================
-- ASCON CXOF128 CORE - Permutation Engine
-- ============================================================================
-- This module implements the heart of the Ascon algorithm: the permutation.
-- The Ascon permutation transforms a 320-bit state (5 x 64-bit words) through
-- 12 rounds of cryptographic mixing to achieve diffusion and confusion.
--
-- Key Features:
-- - 320-bit internal state (S[0] to S[4], each 64 bits)
-- - 12-round permutation (P12) for maximum security
-- - Supports data absorption (XOR input into S[0])
-- - Outputs S[0] for hash squeezing
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ascon_cxof128_core is
    Port (
        -- Clock and Reset
        clk, rst   : in  std_logic;
        
        -- Control Signals
        start_perm : in  std_logic;  -- Pulse high to start a 12-round permutation
        absorb_en  : in  std_logic;  -- When high, XOR block_in into S[0]
        init_state : in  std_logic;  -- Reset state to Initial Value (IV)
        
        -- Data Interface
        block_in   : in  std_logic_vector(63 downto 0);  -- Input data to absorb
        block_out  : out std_logic_vector(63 downto 0); -- Output = S[0] for squeezing
        
        -- Status Signals
        core_busy  : out std_logic;  -- High when permutation is running
        perm_done  : out std_logic   -- Pulse high when permutation completes
    );
end ascon_cxof128_core;

architecture Behavioral of ascon_cxof128_core is

    -- ========================================================================
    -- STATE DEFINITION
    -- ========================================================================
    -- Ascon uses a 320-bit state split into 5 words of 64 bits each.
    -- S[0] is the "rate" part - used for absorbing input and squeezing output.
    -- S[1..4] are the "capacity" part - provides security margin.
    
    type state_array is array (0 to 4) of std_logic_vector(63 downto 0);
    signal S, S_next : state_array;  -- Current and next state
    
    -- Round counter: 0 to 11 for 12 rounds
    signal round_ctr : integer range 0 to 15;
    signal round_active : std_logic := '0';  -- High when running permutation
    
    -- ========================================================================
    -- ROUND CONSTANTS
    -- ========================================================================
    -- Each round uses a different constant to break symmetry.
    -- These values are part of the Ascon specification.
    
    type round_const_array is array (0 to 11) of std_logic_vector(7 downto 0);
    constant RC_TABLE : round_const_array := (
        x"f0", x"e1", x"d2", x"c3",   -- Rounds 0-3
        x"b4", x"a5", x"96", x"87",   -- Rounds 4-7
        x"78", x"69", x"5a", x"4b"    -- Rounds 8-11
    );

    -- ========================================================================
    -- ROTATE RIGHT FUNCTION
    -- ========================================================================
    -- Rotates a 64-bit value right by n positions.
    -- This is the key operation in the linear diffusion layer.
    -- Example: ROR64(ABCD, 1) = DABC (last bit moves to front)
    
    function ROR64(val : std_logic_vector; n : integer) return std_logic_vector is
    begin
        -- Take lower n bits and concatenate with upper (64-n) bits
        return val(n-1 downto 0) & val(63 downto n);
    end function;

begin

    -- ========================================================================
    -- MAIN STATE MACHINE PROCESS
    -- ========================================================================
    -- Controls the permutation execution and data absorption.
    
    process(clk)
    begin
        if rising_edge(clk) then
        
            -- RESET / INITIALIZE
            -- When reset or init_state is high, load the Initial Value (IV).
            -- The IV for CXOF128 encodes: rate=8 bytes, rounds=12, variant=4
            if rst = '1' or init_state = '1' then
                S(0) <= x"0000080000cc0004";  -- CXOF128 IV (from Ascon spec)
                S(1) <= (others=>'0');         -- Capacity words start at zero
                S(2) <= (others=>'0');
                S(3) <= (others=>'0');
                S(4) <= (others=>'0');
                round_active <= '0';
                round_ctr <= 0;
                perm_done <= '0';
                
            -- PERMUTATION RUNNING
            -- Execute one round per clock cycle
            elsif round_active = '1' then
                S <= S_next;  -- Apply the round function result
                
                if round_ctr = 11 then 
                    -- Last round complete - permutation finished
                    round_active <= '0';
                    perm_done <= '1';
                    round_ctr <= 0;
                else 
                    -- More rounds to go
                    round_ctr <= round_ctr + 1;
                    perm_done <= '0';
                end if;
                
            -- IDLE STATE
            -- Can absorb data or start a new permutation
            else
                perm_done <= '0';
                
                -- ABSORB: XOR input data into rate word S[0]
                -- This is how we feed data into the hash function
                if absorb_en = '1' then 
                    S(0) <= S(0) xor block_in; 
                end if;
                
                -- START PERMUTATION
                -- Begin the 12-round permutation
                if start_perm = '1' then 
                    round_active <= '1';
                    round_ctr <= 0; 
                end if;
            end if;
        end if;
    end process;
    
    -- ========================================================================
    -- OUTPUT SIGNALS
    -- ========================================================================
    
    -- Busy when running or about to run permutation
    core_busy <= round_active or start_perm;
    
    -- Hash output is always S[0] (the rate word)
    block_out <= S(0);

    -- ========================================================================
    -- ROUND FUNCTION (Combinational Logic)
    -- ========================================================================
    -- Computes S_next from S in a single clock cycle.
    -- The round function has 3 layers:
    --   1. Add round constant
    --   2. Substitution (S-box applied to each bit column)
    --   3. Linear diffusion (rotate and XOR)
    
    process(S, round_ctr)
        variable x0, x1, x2, x3, x4 : std_logic_vector(63 downto 0);  -- Working state
        variable t0, t1, t2, t3, t4 : std_logic_vector(63 downto 0);  -- After S-box
        variable rc                 : std_logic_vector(63 downto 0);  -- Round constant
    begin
        -- Copy current state to working variables
        x0 := S(0); x1 := S(1); x2 := S(2); x3 := S(3); x4 := S(4);
        
        -- ====================================================================
        -- LAYER 1: CONSTANT ADDITION
        -- ====================================================================
        -- Add round constant to x2 to break symmetry between rounds
        rc := (others => '0');
        rc(7 downto 0) := RC_TABLE(round_ctr);
        x2 := x2 xor rc;
        
        -- ====================================================================
        -- LAYER 2: SUBSTITUTION (S-box)
        -- ====================================================================
        -- The Ascon S-box operates on 5-bit columns of the state.
        -- It's implemented as a series of XOR and AND-NOT operations.
        
        -- 2A. Linear Input Mixing
        -- These XORs prepare the state for the non-linear layer
        x0 := x0 xor x4;
        x4 := x4 xor x3;
        x2 := x2 xor x1;
        
        -- 2B. Chi Layer (Non-Linear Core)
        -- This is the heart of the S-box. The AND-NOT operation
        -- provides non-linearity essential for cryptographic security.
        -- Formula: t[i] = x[i] XOR (NOT x[i+1] AND x[i+2])
        t0 := x0 xor (not x1 and x2);
        t1 := x1 xor (not x2 and x3);
        t2 := x2 xor (not x3 and x4);
        t3 := x3 xor (not x4 and x0);
        t4 := x4 xor (not x0 and x1);
        
        -- 2C. Linear Output Mixing
        -- Final XORs and bit inversion to complete the S-box
        t1 := t1 xor t0;  -- Mix t1 with t0
        t0 := t0 xor t4;  -- Mix t0 with t4
        t3 := t3 xor t2;  -- Mix t3 with t2
        t2 := not t2;     -- Invert all bits of t2
        
        -- ====================================================================
        -- LAYER 3: LINEAR DIFFUSION
        -- ====================================================================
        -- Each word is XORed with two rotated versions of itself.
        -- This spreads each input bit's influence across many output bits.
        -- The rotation amounts are carefully chosen for optimal diffusion.
        
        S_next(0) <= t0 xor ROR64(t0, 19) xor ROR64(t0, 28);  -- Rotate by 19 and 28
        S_next(1) <= t1 xor ROR64(t1, 61) xor ROR64(t1, 39);  -- Rotate by 61 and 39
        S_next(2) <= t2 xor ROR64(t2, 1)  xor ROR64(t2, 6);   -- Rotate by 1 and 6
        S_next(3) <= t3 xor ROR64(t3, 10) xor ROR64(t3, 17);  -- Rotate by 10 and 17
        S_next(4) <= t4 xor ROR64(t4, 7)  xor ROR64(t4, 41);  -- Rotate by 7 and 41
        
    end process;
    
end Behavioral;