-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): jmeno <login AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

  	-- Programovy citac - ukazatel do pameti programu
  	signal PC_addr : std_logic_vector(12 downto 0) := (others =>'0');
  	signal PC_inc : std_logic;
  	signal PC_dec : std_logic;

  	-- Pointer do pameti dat
  	signal PTR_addr : std_logic_vector(12 downto 0) := (12 => '1', others =>'0');
  	signal PTR_inc : std_logic;
	signal PTR_dec : std_logic;

  	-- Citac pro zacatek/konec while cyklu

	-- MX1 - vybrani zda se jedno o adresu programu nebo dat
	signal MX1_sel : std_logic;
	signal MX1_output : std_logic_vector(12 downto 0);

	-- MX2 - hodnota zapisovana do pameti
	signal MX2_sel : std_logic_vector(1 downto 0);
	signal MX2_output : std_logic_vector(7 downto 0);

	-- FSM
	type FSM is (
		S_START,
		S_FETCH,
		S_DECODE,
		S_PTR_INC,
		S_PTR_DEC,
		S_VAL_INC,
		S_VAL_DEC,
		S_WHILE_START,
		S_WHILE_END,
		S_DO_WHILE_START,
		S_DO_WHILE_END,
		S_WRITE,
		S_READ,
		S_NULL
	);
	signal curr_state : FSM := S_START;
	signal next_state : FSM;
begin

  	-- Programovy Citac
  	PC_cnt: process (CLK, RESET, PC_inc, PC_dec)
  	begin
    	if RESET = '1' then
			PC_addr <= (others => '0');
		elsif (CLK'event) and (CLK = '1') then
			if (PC_inc = '1') then
				PC_addr <= PC_addr + 1;
			elsif (PC_dec = '1') then
				PC_addr <= PC_addr - 1;		
			end if;
		end if;
  	end process;

	-- Citac pro ukazatel do pameti dat
	PTR_cnt: process (CLK, RESET, PTR_inc, PTR_dec)
	begin
		if RESET = '1' then
			PTR_addr <= (others => '0');
		elsif (CLK'event) and (CLK='1') then
			if (PTR_inc = '1') then
				PTR_addr <= PTR_addr + 1;
			elsif (PTR_dec = '1') then
				PTR_addr <= PTR_addr - 1;
			end if;
		end if;
	end process;

	-- MX1
	MX1: process (CLK, RESET, MX1_sel)
	begin
		if RESET = '1' then
			MX1_output <= (others => '0');
		elsif (CLK'event) and (CLK='1') then
			case MX1_sel is
				when '0' =>
					MX1_output <= PC_addr;
				when '1' =>
					MX1_output <= PTR_addr;
				when others =>
					MX1_output <= (others => '0');
			end case;
		end if;
	end process;
	DATA_ADDR <= MX1_output;

	-- MX2
	MX2: process(CLK, RESET, MX2_sel)
	begin
		if RESET = '1' then
			MX2_output <= (others => '0');
		elsif (CLK'event) and (CLK='1') then
			case MX2_sel is
				when "00" =>
					MX2_output <= IN_DATA;
				when "01" =>
					MX2_output <= DATA_RDATA + 1;
				when "10" =>
					MX2_output <= DATA_RDATA - 1;
				when others =>
					MX2_output <= (others => '0'); 
			end case;
		end if;
		DATA_WDATA <= MX2_OUTPUT;
	end process;

	--FSM
	state: process (CLK, RESET, EN)
	begin
		if RESET = '1' then
			curr_state <= S_START;
		elsif (CLK'event) and (CLK='1') then
			if EN = '1' then
				curr_state <= next_state;
			end if;
		end if;
    end process;

	next_state_logic: process(curr_state)
	begin
		PC_inc <= '0';
		PC_dec <= '0';
		PTR_inc <= '0';
		PTR_dec <= '0';
		DATA_EN <= '0';
		DATA_RDWR <= '0';
		IN_REQ <= '0';
		OUT_WE <= '0';
		MX1_sel <= '0';
		MX2_sel <= "00";

		case curr_state is
			when S_START =>
				next_state <= S_FETCH;
			when S_FETCH =>
				DATA_EN <= '1';
				next_state <= S_DECODE;
			when S_DECODE =>
				case DATA_RDATA is
					when x"3E" =>
						next_state <= S_PTR_INC;
					when x"3C" =>
						next_state <= S_PTR_DEC;
					when x"2B" =>
						next_state <= S_VAL_INC;
					when x"2D" =>
						next_state <= S_VAL_DEC;
					when x"5B" =>
						next_state <= S_WHILE_START;
					when x"5D" =>
						next_state <= S_WHILE_END;
					when x"28" =>
						next_state <= S_DO_WHILE_START;
					when x"29" =>
						next_state <= S_DO_WHILE_END;
					when x"2E" =>
						next_state <= S_WRITE;
					when x"2C" =>
						next_state <= S_READ;
					when x"00" =>
						next_state <= S_NULL;
					when others =>
						next_state <= S_FETCH;
						PC_inc <= '1';
				end case;
			when S_PTR_INC =>
				MX1_sel <= '1';
				PTR_inc <= '1';
				PC_inc <= '1';
				next_state <= S_FETCH;
			when S_PTR_DEC =>
				MX1_sel <= '1';
				PTR_dec <= '1';
				PC_inc <= '1';
				next_state <= S_FETCH;
			when others =>
				next_state <= S_FETCH;
				PC_inc <= '1';
		end case;
	end process;

end behavioral;

