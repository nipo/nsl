
-- synthesis translate_off
-- This VHDL was converted from Verilog using the
-- Icarus Verilog VHDL Code Generator 12.0 (stable) ()
--
-- These are the GW1N and GW2A models.  Arora V's deserialisers are not
-- the same blocks: its IDES8 carries five shift stages a side where
-- these carry four, and cuts the word out of the later four, so a
-- GW5A pad hands the fabric the same wire two slots later than this
-- says.  The output serialisers do match.  A bench that simulates a
-- GW5A design against these will be that much optimistic about when a
-- capture arrives; doc/architecture_notes/gowin has the comparison.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Generated from Verilog module IDES4 (ides4.v:3)
--   LSREN = "true"
entity IDES4 is
  GENERIC (
    GSREN : string := "false";
    LSREN : string := "true"
    );
  port (
    CALIB : in std_logic;
    D : in std_logic;
    FCLK : in std_logic;
    PCLK : in std_logic;
    Q0 : out std_logic;
    Q1 : out std_logic;
    Q2 : out std_logic;
    Q3 : out std_logic;
    RESET : in std_logic
  );
end entity; 

-- Generated from Verilog module IDES4 (ides4.v:3)
--   LSREN = "true"
architecture from_verilog of IDES4 is
  signal CALIBdata : unsigned(2 downto 0);  -- Declared at ides4.v:22
  signal CALIBdata_rising_p : std_logic;  -- Declared at ides4.v:21
  signal D_data : unsigned(3 downto 0);  -- Declared at ides4.v:16
  signal D_en : std_logic := '0';  -- Declared at ides4.v:17
  signal D_en1 : std_logic := '0';  -- Declared at ides4.v:17
  signal Dd0 : std_logic;  -- Declared at ides4.v:15
  signal Dd0_reg0 : std_logic;  -- Declared at ides4.v:24
  signal Dd0_reg1 : std_logic;  -- Declared at ides4.v:24
  signal Dd1 : std_logic;  -- Declared at ides4.v:15
  signal Dd1_reg0 : std_logic;  -- Declared at ides4.v:24
  signal Dd1_reg1 : std_logic;  -- Declared at ides4.v:24
  signal Dd_sel : std_logic := '0';  -- Declared at ides4.v:18
  signal Q_data : unsigned(3 downto 0);  -- Declared at ides4.v:19
  signal tmp_ivl_13 : std_logic;  -- Temporary created at ides4.v:91
  signal tmp_ivl_22 : unsigned(3 downto 0);  -- Temporary created at ides4.v:151
  signal tmp_ivl_5 : std_logic;  -- Temporary created at ides4.v:90
  signal tmp_ivl_7 : std_logic;  -- Temporary created at ides4.v:90
  signal tmp_ivl_8 : std_logic;  -- Temporary created at ides4.v:90
  signal calib_state : std_logic := '0';  -- Declared at ides4.v:18
  signal data : unsigned(3 downto 0);  -- Declared at ides4.v:16
  signal dcnt_en : std_logic;  -- Declared at ides4.v:23
  signal grstn : std_logic;  -- Declared at ides4.v:9
  signal lrstn : std_logic;  -- Declared at ides4.v:10
  signal reset_delay : std_logic;  -- Declared at ides4.v:20
begin
  lrstn <= not RESET;
  tmp_ivl_8 <= not tmp_ivl_7;
  CALIBdata_rising_p <= tmp_ivl_5 and tmp_ivl_8;
  tmp_ivl_13 <= CALIBdata_rising_p and calib_state;
  dcnt_en <= not tmp_ivl_13;
  tmp_ivl_22 <= Q_data;
  tmp_ivl_5 <= CALIBdata(1);
  tmp_ivl_7 <= CALIBdata(2);
  Q3 <= tmp_ivl_22(3);
  Q2 <= tmp_ivl_22(2);
  Q1 <= tmp_ivl_22(1);
  Q0 <= tmp_ivl_22(0);
  grstn <= '1';
  -- Removed one empty process
  
  
  -- Generated from always process in IDES4 (ides4.v:33)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Dd0 <= '0';
      else
        if (not lrstn) = '1' then
          Dd0 <= '0';
        else
          Dd0 <= D;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES4 (ides4.v:43)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or falling_edge(FCLK) then
      if (not grstn) = '1' then
        Dd1 <= '0';
      else
        if (not lrstn) = '1' then
          Dd1 <= '0';
        else
          Dd1 <= D;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES4 (ides4.v:53)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Dd0_reg0 <= '0';
        Dd0_reg1 <= '0';
        Dd1_reg0 <= '0';
        Dd1_reg1 <= '0';
      else
        if (not lrstn) = '1' then
          Dd0_reg0 <= '0';
          Dd0_reg1 <= '0';
          Dd1_reg0 <= '0';
          Dd1_reg1 <= '0';
        else
          Dd0_reg0 <= Dd0;
          Dd0_reg1 <= Dd0_reg0;
          Dd1_reg0 <= Dd1;
          Dd1_reg1 <= Dd1_reg0;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES4 (ides4.v:72)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        reset_delay <= '0';
      else
        if (not lrstn) = '1' then
          reset_delay <= '0';
        else
          reset_delay <= '1';
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES4 (ides4.v:82)
  process (FCLK, reset_delay) is
  begin
    if (not reset_delay) = '1' then
      CALIBdata <= "000";
    elsif rising_edge(FCLK) then
      CALIBdata <= CALIBdata(0 + 1 downto 0) & CALIB;
    end if;
  end process;
  
  -- Generated from always process in IDES4 (ides4.v:93)
  process (FCLK, reset_delay) is
  begin
    if (not reset_delay) = '1' then
      calib_state <= '0';
      D_en1 <= '0';
      D_en <= '0';
      Dd_sel <= '0';
    elsif rising_edge(FCLK) then
      D_en <= not D_en1;
      if CALIBdata_rising_p = '1' then
        calib_state <= not calib_state;
        Dd_sel <= not Dd_sel;
      else
        calib_state <= calib_state;
        Dd_sel <= Dd_sel;
      end if;
      if dcnt_en = '1' then
        D_en1 <= not D_en1;
      else
        D_en1 <= D_en1;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES4 (ides4.v:117)
  process (Dd1_reg1, Dd1_reg0, Dd0_reg1, Dd0_reg0, Dd0, Dd_sel) is
  begin
    if Dd_sel = '1' then
      D_data(3) <= Dd0;
      D_data(2) <= Dd1_reg0;
      D_data(1) <= Dd0_reg0;
      D_data(0) <= Dd1_reg1;
    else
      D_data(3) <= Dd1_reg0;
      D_data(2) <= Dd0_reg0;
      D_data(1) <= Dd1_reg1;
      D_data(0) <= Dd0_reg1;
    end if;
  end process;
  
  -- Generated from always process in IDES4 (ides4.v:131)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        data <= X"0";
      else
        if (not lrstn) = '1' then
          data <= X"0";
        else
          if D_en = '1' then
            data <= D_data;
          end if;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES4 (ides4.v:141)
  process (lrstn, grstn, PCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(PCLK) then
      if (not grstn) = '1' then
        Q_data <= X"0";
      else
        if (not lrstn) = '1' then
          Q_data <= X"0";
        else
          Q_data <= data;
        end if;
      end if;
    end if;
  end process;
end architecture;

-- This VHDL was converted from Verilog using the
-- Icarus Verilog VHDL Code Generator 12.0 (stable) ()

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Generated from Verilog module IDES8 (ides8.v:1)
--   LSREN = "true"
entity IDES8 is
  GENERIC (
    GSREN : string := "false";
    LSREN : string := "true"
    );
  port (
    CALIB : in std_logic;
    D : in std_logic;
    FCLK : in std_logic;
    PCLK : in std_logic;
    Q0 : out std_logic;
    Q1 : out std_logic;
    Q2 : out std_logic;
    Q3 : out std_logic;
    Q4 : out std_logic;
    Q5 : out std_logic;
    Q6 : out std_logic;
    Q7 : out std_logic;
    RESET : in std_logic
  );
end entity; 

-- Generated from Verilog module IDES8 (ides8.v:1)
--   LSREN = "true"
architecture from_verilog of IDES8 is
  signal CALIBdata : unsigned(2 downto 0);  -- Declared at ides8.v:21
  signal CALIBdata_rising_p : std_logic;  -- Declared at ides8.v:20
  signal D_data : unsigned(7 downto 0);  -- Declared at ides8.v:14
  signal D_en : std_logic := '0';  -- Declared at ides8.v:16
  signal D_en0 : std_logic := '0';  -- Declared at ides8.v:16
  signal D_en1 : std_logic := '0';  -- Declared at ides8.v:16
  signal Dd0 : std_logic;  -- Declared at ides8.v:12
  signal Dd0_reg0 : std_logic;  -- Declared at ides8.v:23
  signal Dd0_reg1 : std_logic;  -- Declared at ides8.v:23
  signal Dd0_reg2 : std_logic;  -- Declared at ides8.v:23
  signal Dd0_reg3 : std_logic;  -- Declared at ides8.v:23
  signal Dd1 : std_logic;  -- Declared at ides8.v:13
  signal Dd1_reg0 : std_logic;  -- Declared at ides8.v:23
  signal Dd1_reg1 : std_logic;  -- Declared at ides8.v:23
  signal Dd1_reg2 : std_logic;  -- Declared at ides8.v:23
  signal Dd1_reg3 : std_logic;  -- Declared at ides8.v:23
  signal Dd_sel : std_logic := '0';  -- Declared at ides8.v:18
  signal Q_data : unsigned(7 downto 0);  -- Declared at ides8.v:17
  signal tmp_ivl_13 : std_logic;  -- Temporary created at ides8.v:72
  signal tmp_ivl_26 : unsigned(7 downto 0);  -- Temporary created at ides8.v:175
  signal tmp_ivl_5 : std_logic;  -- Temporary created at ides8.v:71
  signal tmp_ivl_7 : std_logic;  -- Temporary created at ides8.v:71
  signal tmp_ivl_8 : std_logic;  -- Temporary created at ides8.v:71
  signal calib_state : std_logic := '0';  -- Declared at ides8.v:18
  signal data : unsigned(7 downto 0);  -- Declared at ides8.v:15
  signal dcnt_en : std_logic;  -- Declared at ides8.v:22
  signal grstn : std_logic;  -- Declared at ides8.v:7
  signal lrstn : std_logic;  -- Declared at ides8.v:8
  signal reset_delay : std_logic;  -- Declared at ides8.v:19
begin
  lrstn <= not RESET;
  tmp_ivl_8 <= not tmp_ivl_7;
  CALIBdata_rising_p <= tmp_ivl_5 and tmp_ivl_8;
  tmp_ivl_13 <= CALIBdata_rising_p and calib_state;
  dcnt_en <= not tmp_ivl_13;
  tmp_ivl_26 <= Q_data;
  tmp_ivl_5 <= CALIBdata(1);
  tmp_ivl_7 <= CALIBdata(2);
  Q7 <= tmp_ivl_26(7);
  Q6 <= tmp_ivl_26(6);
  Q5 <= tmp_ivl_26(5);
  Q4 <= tmp_ivl_26(4);
  Q3 <= tmp_ivl_26(3);
  Q2 <= tmp_ivl_26(2);
  Q1 <= tmp_ivl_26(1);
  Q0 <= tmp_ivl_26(0);
  grstn <= '1';
  -- Removed one empty process
  
  
  -- Generated from always process in IDES8 (ides8.v:33)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Dd0 <= '0';
      else
        if (not lrstn) = '1' then
          Dd0 <= '0';
        else
          Dd0 <= D;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES8 (ides8.v:43)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or falling_edge(FCLK) then
      if (not grstn) = '1' then
        Dd1 <= '0';
      else
        if (not lrstn) = '1' then
          Dd1 <= '0';
        else
          Dd1 <= D;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES8 (ides8.v:53)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        reset_delay <= '0';
      else
        if (not lrstn) = '1' then
          reset_delay <= '0';
        else
          reset_delay <= '1';
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES8 (ides8.v:63)
  process (FCLK, reset_delay) is
  begin
    if (not reset_delay) = '1' then
      CALIBdata <= "000";
    elsif rising_edge(FCLK) then
      CALIBdata <= CALIBdata(0 + 1 downto 0) & CALIB;
    end if;
  end process;
  
  -- Generated from always process in IDES8 (ides8.v:74)
  process (FCLK, reset_delay) is
  begin
    if (not reset_delay) = '1' then
      calib_state <= '0';
      D_en1 <= '0';
      D_en0 <= '0';
      D_en <= '0';
      Dd_sel <= '0';
    elsif rising_edge(FCLK) then
      D_en <= D_en0 and (not D_en1);
      if CALIBdata_rising_p = '1' then
        calib_state <= not calib_state;
        Dd_sel <= not Dd_sel;
      else
        calib_state <= calib_state;
        Dd_sel <= Dd_sel;
      end if;
      if dcnt_en = '1' then
        D_en0 <= not D_en0;
      else
        D_en0 <= D_en0;
      end if;
      if dcnt_en = '1' then
        D_en1 <= D_en0 xor D_en1;
      else
        D_en1 <= D_en1;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES8 (ides8.v:106)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Dd0_reg0 <= '0';
        Dd0_reg1 <= '0';
        Dd0_reg2 <= '0';
        Dd0_reg3 <= '0';
        Dd1_reg0 <= '0';
        Dd1_reg1 <= '0';
        Dd1_reg2 <= '0';
        Dd1_reg3 <= '0';
      else
        if (not lrstn) = '1' then
          Dd0_reg0 <= '0';
          Dd0_reg1 <= '0';
          Dd0_reg2 <= '0';
          Dd0_reg3 <= '0';
          Dd1_reg0 <= '0';
          Dd1_reg1 <= '0';
          Dd1_reg2 <= '0';
          Dd1_reg3 <= '0';
        else
          Dd0_reg0 <= Dd0;
          Dd0_reg1 <= Dd0_reg0;
          Dd0_reg2 <= Dd0_reg1;
          Dd0_reg3 <= Dd0_reg2;
          Dd1_reg0 <= Dd1;
          Dd1_reg1 <= Dd1_reg0;
          Dd1_reg2 <= Dd1_reg1;
          Dd1_reg3 <= Dd1_reg2;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES8 (ides8.v:137)
  process (Dd1_reg3, Dd1_reg2, Dd1_reg1, Dd1_reg0, Dd0_reg3, Dd0_reg2, Dd0_reg1, Dd0_reg0, Dd0, Dd_sel) is
  begin
    if Dd_sel = '1' then
      D_data(7) <= Dd0;
      D_data(6) <= Dd1_reg0;
      D_data(5) <= Dd0_reg0;
      D_data(4) <= Dd1_reg1;
      D_data(3) <= Dd0_reg1;
      D_data(2) <= Dd1_reg2;
      D_data(1) <= Dd0_reg2;
      D_data(0) <= Dd1_reg3;
    else
      D_data(7) <= Dd1_reg0;
      D_data(6) <= Dd0_reg0;
      D_data(5) <= Dd1_reg1;
      D_data(4) <= Dd0_reg1;
      D_data(3) <= Dd1_reg2;
      D_data(2) <= Dd0_reg2;
      D_data(1) <= Dd1_reg3;
      D_data(0) <= Dd0_reg3;
    end if;
  end process;
  
  -- Generated from always process in IDES8 (ides8.v:159)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        data <= X"00";
      else
        if (not lrstn) = '1' then
          data <= X"00";
        else
          if D_en = '1' then
            data <= D_data;
          end if;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES8 (ides8.v:167)
  process (lrstn, grstn, PCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(PCLK) then
      if (not grstn) = '1' then
        Q_data <= X"00";
      else
        if (not lrstn) = '1' then
          Q_data <= X"00";
        else
          Q_data <= data;
        end if;
      end if;
    end if;
  end process;
end architecture;

-- This VHDL was converted from Verilog using the
-- Icarus Verilog VHDL Code Generator 12.0 (stable) ()

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Generated from Verilog module IDES10 (ides10.v:1)
--   LSREN = "true"
entity IDES10 is
  GENERIC (
    GSREN : string := "false";
    LSREN : string := "true"
    );
  port (
    CALIB : in std_logic;
    D : in std_logic;
    FCLK : in std_logic;
    PCLK : in std_logic;
    Q0 : out std_logic;
    Q1 : out std_logic;
    Q2 : out std_logic;
    Q3 : out std_logic;
    Q4 : out std_logic;
    Q5 : out std_logic;
    Q6 : out std_logic;
    Q7 : out std_logic;
    Q8 : out std_logic;
    Q9 : out std_logic;
    RESET : in std_logic
  );
end entity; 

-- Generated from Verilog module IDES10 (ides10.v:1)
--   LSREN = "true"
architecture from_verilog of IDES10 is
  signal CALIBdata : unsigned(2 downto 0);  -- Declared at ides10.v:21
  signal CALIBdata_rising_p : std_logic;  -- Declared at ides10.v:20
  signal D_data : unsigned(9 downto 0);  -- Declared at ides10.v:14
  signal D_en : std_logic := '0';  -- Declared at ides10.v:16
  signal D_en0 : std_logic := '0';  -- Declared at ides10.v:16
  signal D_en1 : std_logic := '0';  -- Declared at ides10.v:16
  signal D_en2 : std_logic := '0';  -- Declared at ides10.v:16
  signal Dd0 : std_logic;  -- Declared at ides10.v:12
  signal Dd0_reg0 : std_logic;  -- Declared at ides10.v:23
  signal Dd0_reg1 : std_logic;  -- Declared at ides10.v:23
  signal Dd0_reg2 : std_logic;  -- Declared at ides10.v:23
  signal Dd0_reg3 : std_logic;  -- Declared at ides10.v:23
  signal Dd0_reg4 : std_logic;  -- Declared at ides10.v:23
  signal Dd1 : std_logic;  -- Declared at ides10.v:13
  signal Dd1_reg0 : std_logic;  -- Declared at ides10.v:23
  signal Dd1_reg1 : std_logic;  -- Declared at ides10.v:23
  signal Dd1_reg2 : std_logic;  -- Declared at ides10.v:23
  signal Dd1_reg3 : std_logic;  -- Declared at ides10.v:23
  signal Dd1_reg4 : std_logic;  -- Declared at ides10.v:23
  signal Dd_sel : std_logic := '0';  -- Declared at ides10.v:18
  signal Q_data : unsigned(9 downto 0);  -- Declared at ides10.v:17
  signal tmp_ivl_13 : std_logic;  -- Temporary created at ides10.v:70
  signal tmp_ivl_16 : std_logic;  -- Temporary created at ides10.v:71
  signal tmp_ivl_18 : std_logic;  -- Temporary created at ides10.v:71
  signal tmp_ivl_20 : std_logic;  -- Temporary created at ides10.v:71
  signal tmp_ivl_36 : unsigned(9 downto 0);  -- Temporary created at ides10.v:192
  signal tmp_ivl_5 : std_logic;  -- Temporary created at ides10.v:69
  signal tmp_ivl_7 : std_logic;  -- Temporary created at ides10.v:69
  signal tmp_ivl_8 : std_logic;  -- Temporary created at ides10.v:69
  signal calib_state : std_logic := '0';  -- Declared at ides10.v:18
  signal data : unsigned(9 downto 0);  -- Declared at ides10.v:15
  signal dcnt_en : std_logic;  -- Declared at ides10.v:22
  signal dcnt_reset : std_logic;  -- Declared at ides10.v:22
  signal grstn : std_logic;  -- Declared at ides10.v:7
  signal lrstn : std_logic;  -- Declared at ides10.v:8
  signal reset_delay : std_logic;  -- Declared at ides10.v:19
begin
  lrstn <= not RESET;
  tmp_ivl_8 <= not tmp_ivl_7;
  CALIBdata_rising_p <= tmp_ivl_5 and tmp_ivl_8;
  tmp_ivl_13 <= CALIBdata_rising_p and calib_state;
  dcnt_en <= not tmp_ivl_13;
  tmp_ivl_16 <= not D_en1;
  tmp_ivl_18 <= D_en2 and tmp_ivl_16;
  tmp_ivl_20 <= not D_en0;
  dcnt_reset <= tmp_ivl_18 and tmp_ivl_20;
  tmp_ivl_36 <= Q_data;
  tmp_ivl_5 <= CALIBdata(1);
  tmp_ivl_7 <= CALIBdata(2);
  Q9 <= tmp_ivl_36(9);
  Q8 <= tmp_ivl_36(8);
  Q7 <= tmp_ivl_36(7);
  Q6 <= tmp_ivl_36(6);
  Q5 <= tmp_ivl_36(5);
  Q4 <= tmp_ivl_36(4);
  Q3 <= tmp_ivl_36(3);
  Q2 <= tmp_ivl_36(2);
  Q1 <= tmp_ivl_36(1);
  Q0 <= tmp_ivl_36(0);
  grstn <= '1';
  -- Removed one empty process
  
  
  -- Generated from always process in IDES10 (ides10.v:35)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Dd0 <= '0';
      else
        if (not lrstn) = '1' then
          Dd0 <= '0';
        else
          Dd0 <= D;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES10 (ides10.v:43)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or falling_edge(FCLK) then
      if (not grstn) = '1' then
        Dd1 <= '0';
      else
        if (not lrstn) = '1' then
          Dd1 <= '0';
        else
          Dd1 <= D;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES10 (ides10.v:51)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        reset_delay <= '0';
      else
        if (not lrstn) = '1' then
          reset_delay <= '0';
        else
          reset_delay <= '1';
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES10 (ides10.v:61)
  process (FCLK, reset_delay) is
  begin
    if (not reset_delay) = '1' then
      CALIBdata <= "000";
    elsif rising_edge(FCLK) then
      CALIBdata <= CALIBdata(0 + 1 downto 0) & CALIB;
    end if;
  end process;
  
  -- Generated from always process in IDES10 (ides10.v:73)
  process (FCLK, reset_delay) is
  begin
    if (not reset_delay) = '1' then
      calib_state <= '0';
      D_en0 <= '0';
      D_en1 <= '0';
      D_en2 <= '0';
      D_en <= '0';
      Dd_sel <= '0';
    elsif rising_edge(FCLK) then
      D_en <= (not D_en0) and D_en1;
      if CALIBdata_rising_p = '1' then
        calib_state <= not calib_state;
        Dd_sel <= not Dd_sel;
      else
        calib_state <= calib_state;
        Dd_sel <= Dd_sel;
      end if;
      if dcnt_en = '1' then
        D_en0 <= not (dcnt_reset or D_en0);
      else
        D_en0 <= D_en0;
      end if;
      if dcnt_en = '1' then
        D_en1 <= D_en0 xor D_en1;
      else
        D_en1 <= D_en1;
      end if;
      if dcnt_en = '1' then
        D_en2 <= ((D_en0 and D_en1) xor D_en2) and (not dcnt_reset);
      else
        D_en2 <= D_en2;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES10 (ides10.v:113)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Dd0_reg0 <= '0';
        Dd0_reg1 <= '0';
        Dd0_reg2 <= '0';
        Dd0_reg3 <= '0';
        Dd0_reg4 <= '0';
        Dd1_reg0 <= '0';
        Dd1_reg1 <= '0';
        Dd1_reg2 <= '0';
        Dd1_reg3 <= '0';
        Dd1_reg4 <= '0';
      else
        if (not lrstn) = '1' then
          Dd0_reg0 <= '0';
          Dd0_reg1 <= '0';
          Dd0_reg2 <= '0';
          Dd0_reg3 <= '0';
          Dd0_reg4 <= '0';
          Dd1_reg0 <= '0';
          Dd1_reg1 <= '0';
          Dd1_reg2 <= '0';
          Dd1_reg3 <= '0';
          Dd1_reg4 <= '0';
        else
          Dd0_reg0 <= Dd0;
          Dd0_reg1 <= Dd0_reg0;
          Dd0_reg2 <= Dd0_reg1;
          Dd0_reg3 <= Dd0_reg2;
          Dd0_reg4 <= Dd0_reg3;
          Dd1_reg0 <= Dd1;
          Dd1_reg1 <= Dd1_reg0;
          Dd1_reg2 <= Dd1_reg1;
          Dd1_reg3 <= Dd1_reg2;
          Dd1_reg4 <= Dd1_reg3;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES10 (ides10.v:150)
  process (Dd1_reg4, Dd1_reg3, Dd1_reg2, Dd1_reg1, Dd1_reg0, Dd0_reg4, Dd0_reg3, Dd0_reg2, Dd0_reg1, Dd0_reg0, Dd0, Dd_sel) is
  begin
    if Dd_sel = '1' then
      D_data(9) <= Dd0;
      D_data(8) <= Dd1_reg0;
      D_data(7) <= Dd0_reg0;
      D_data(6) <= Dd1_reg1;
      D_data(5) <= Dd0_reg1;
      D_data(4) <= Dd1_reg2;
      D_data(3) <= Dd0_reg2;
      D_data(2) <= Dd1_reg3;
      D_data(1) <= Dd0_reg3;
      D_data(0) <= Dd1_reg4;
    else
      D_data(9) <= Dd1_reg0;
      D_data(8) <= Dd0_reg0;
      D_data(7) <= Dd1_reg1;
      D_data(6) <= Dd0_reg1;
      D_data(5) <= Dd1_reg2;
      D_data(4) <= Dd0_reg2;
      D_data(3) <= Dd1_reg3;
      D_data(2) <= Dd0_reg3;
      D_data(1) <= Dd1_reg4;
      D_data(0) <= Dd0_reg4;
    end if;
  end process;
  
  -- Generated from always process in IDES10 (ides10.v:176)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        data <= "0000000000";
      else
        if (not lrstn) = '1' then
          data <= "0000000000";
        else
          if D_en = '1' then
            data <= D_data;
          end if;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in IDES10 (ides10.v:184)
  process (lrstn, grstn, PCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(PCLK) then
      if (not grstn) = '1' then
        Q_data <= "0000000000";
      else
        if (not lrstn) = '1' then
          Q_data <= "0000000000";
        else
          Q_data <= data;
        end if;
      end if;
    end if;
  end process;
end architecture;

-- This VHDL was converted from Verilog using the
-- Icarus Verilog VHDL Code Generator 12.0 (stable) ()

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Generated from Verilog module OSER4 (oser4.v:2)
--   HWL = "false"
--   LSREN = "true"
--   TXCLK_POL = 0
entity OSER4 is
  GENERIC (
    GSREN : string := "false";
    LSREN : string := "true"
    );
  port (
    D0 : in std_logic;
    D1 : in std_logic;
    D2 : in std_logic;
    D3 : in std_logic;
    FCLK : in std_logic;
    PCLK : in std_logic;
    Q0 : out std_logic;
    Q1 : out std_logic;
    RESET : in std_logic;
    TX0 : in std_logic;
    TX1 : in std_logic
  );
end entity; 

-- Generated from Verilog module OSER4 (oser4.v:2)
--   HWL = "false"
--   LSREN = "true"
--   TXCLK_POL = 0
architecture from_verilog of OSER4 is
  signal Dd1 : unsigned(3 downto 0);  -- Declared at oser4.v:13
  signal Dd2 : unsigned(3 downto 0);  -- Declared at oser4.v:13
  signal Dd3 : unsigned(3 downto 0);  -- Declared at oser4.v:13
  signal Q_data_n : std_logic;  -- Declared at oser4.v:17
  signal Q_data_p : std_logic;  -- Declared at oser4.v:17
  signal Qq_n : std_logic;  -- Declared at oser4.v:17
  signal Qq_p : std_logic;  -- Declared at oser4.v:17
  signal Ttx1 : unsigned(1 downto 0);  -- Declared at oser4.v:14
  signal Ttx2 : unsigned(1 downto 0);  -- Declared at oser4.v:14
  signal Ttx3 : unsigned(1 downto 0);  -- Declared at oser4.v:14
  signal d_en0 : std_logic;  -- Declared at oser4.v:16
  signal d_en1 : std_logic;  -- Declared at oser4.v:16
  signal d_up0 : std_logic;  -- Declared at oser4.v:15
  signal d_up1 : std_logic;  -- Declared at oser4.v:15
  signal dsel : std_logic := '0';  -- Declared at oser4.v:15
  signal grstn : std_logic;  -- Declared at oser4.v:18
  signal lrstn : std_logic;  -- Declared at oser4.v:18
  signal rstn_dsel : std_logic;  -- Declared at oser4.v:15
begin
  lrstn <= not RESET;
  d_en0 <= not dsel;
  d_en1 <= dsel;
  Q1 <= Q_data_p;
  Q0 <= Qq_n when FCLK = '1' else Qq_p;
  grstn <= '1';
  -- Removed one empty process
  
  
  -- Generated from always process in OSER4 (oser4.v:27)
  process (lrstn, grstn, PCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(PCLK) then
      if (not grstn) = '1' then
        Dd1 <= X"0";
        Ttx1 <= "00";
      else
        if (not lrstn) = '1' then
          Dd1 <= X"0";
          Ttx1 <= "00";
        else
          Dd1 <= D3 & D2 & D1 & D0;
          Ttx1 <= TX1 & TX0;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER4 (oser4.v:43)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        rstn_dsel <= '0';
      else
        if (not lrstn) = '1' then
          rstn_dsel <= '0';
        else
          rstn_dsel <= '1';
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER4 (oser4.v:56)
  process (FCLK, rstn_dsel) is
  begin
    if (not rstn_dsel) = '1' then
      dsel <= '0';
    elsif rising_edge(FCLK) then
      dsel <= not dsel;
    end if;
  end process;
  
  -- Generated from always process in OSER4 (oser4.v:68)
  process (FCLK, rstn_dsel) is
  begin
    if (not rstn_dsel) = '1' then
      d_up0 <= '0';
      d_up1 <= '0';
    elsif rising_edge(FCLK) then
      if d_en0 = '1' then
        d_up0 <= '1';
      else
        d_up0 <= '0';
      end if;
      if d_en1 = '1' then
        d_up1 <= '1';
      else
        d_up1 <= '0';
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER4 (oser4.v:88)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Dd2 <= X"0";
        Ttx2 <= "00";
      else
        if (not lrstn) = '1' then
          Dd2 <= X"0";
          Ttx2 <= "00";
        else
          if d_up0 = '1' then
            Dd2 <= Dd1;
            Ttx2 <= Ttx1;
          else
            Dd2 <= Dd2;
            Ttx2 <= Ttx2;
          end if;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER4 (oser4.v:107)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Dd3 <= X"0";
        Ttx3 <= "00";
      else
        if (not lrstn) = '1' then
          Dd3 <= X"0";
          Ttx3 <= "00";
        else
          if d_up1 = '1' then
            Dd3 <= Dd2;
            Ttx3 <= Ttx2;
          else
            Dd3(0) <= Dd3(2);
            Dd3(2) <= '0';
            Dd3(1) <= Dd3(3);
            Dd3(3) <= '0';
            Ttx3(0) <= Ttx3(1);
            Ttx3(1) <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER4 (oser4.v:129)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or falling_edge(FCLK) then
      if (not grstn) = '1' then
        Qq_n <= '0';
        Q_data_n <= '0';
      else
        if (not lrstn) = '1' then
          Qq_n <= '0';
          Q_data_n <= '0';
        else
          Qq_n <= Dd3(0);
          Q_data_n <= Ttx3(0);
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER4 (oser4.v:143)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Qq_p <= '0';
      else
        if (not lrstn) = '1' then
          Qq_p <= '0';
        else
          Qq_p <= Dd3(1);
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER4 (oser4.v:154)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Q_data_p <= '0';
      else
        if (not lrstn) = '1' then
          Q_data_p <= '0';
        else
          Q_data_p <= Q_data_n;
        end if;
      end if;
    end if;
  end process;
end architecture;

-- This VHDL was converted from Verilog using the
-- Icarus Verilog VHDL Code Generator 12.0 (stable) ()

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Generated from Verilog module OSER8 (oser8.v:2)
--   HWL = "false"
--   LSREN = "true"
--   TXCLK_POL = 0
entity OSER8 is
  GENERIC (
    GSREN : string := "false";
    LSREN : string := "true"
    );
  port (
    D0 : in std_logic;
    D1 : in std_logic;
    D2 : in std_logic;
    D3 : in std_logic;
    D4 : in std_logic;
    D5 : in std_logic;
    D6 : in std_logic;
    D7 : in std_logic;
    FCLK : in std_logic;
    PCLK : in std_logic;
    Q0 : out std_logic;
    Q1 : out std_logic;
    RESET : in std_logic;
    TX0 : in std_logic;
    TX1 : in std_logic;
    TX2 : in std_logic;
    TX3 : in std_logic
  );
end entity; 

-- Generated from Verilog module OSER8 (oser8.v:2)
--   HWL = "false"
--   LSREN = "true"
--   TXCLK_POL = 0
architecture from_verilog of OSER8 is
  signal Dd1 : unsigned(7 downto 0);  -- Declared at oser8.v:13
  signal Dd2 : unsigned(7 downto 0);  -- Declared at oser8.v:13
  signal Dd3 : unsigned(7 downto 0);  -- Declared at oser8.v:13
  signal Q_data_n : std_logic;  -- Declared at oser8.v:17
  signal Q_data_p : std_logic;  -- Declared at oser8.v:17
  signal Qq_n : std_logic;  -- Declared at oser8.v:17
  signal Qq_p : std_logic;  -- Declared at oser8.v:17
  signal Ttx1 : unsigned(3 downto 0);  -- Declared at oser8.v:14
  signal Ttx2 : unsigned(3 downto 0);  -- Declared at oser8.v:14
  signal Ttx3 : unsigned(3 downto 0);  -- Declared at oser8.v:14
  signal tmp_ivl_10 : std_logic;  -- Temporary created at oser8.v:69
  signal tmp_ivl_4 : std_logic;  -- Temporary created at oser8.v:68
  signal tmp_ivl_8 : std_logic;  -- Temporary created at oser8.v:69
  signal d_en0 : std_logic;  -- Declared at oser8.v:16
  signal d_en1 : std_logic;  -- Declared at oser8.v:16
  signal d_up0 : std_logic;  -- Declared at oser8.v:15
  signal d_up1 : std_logic;  -- Declared at oser8.v:15
  signal dcnt0 : std_logic := '0';  -- Declared at oser8.v:15
  signal dcnt1 : std_logic := '0';  -- Declared at oser8.v:15
  signal grstn : std_logic;  -- Declared at oser8.v:18
  signal lrstn : std_logic;  -- Declared at oser8.v:18
  signal rstn_dsel : std_logic;  -- Declared at oser8.v:15
begin
  lrstn <= not RESET;
  tmp_ivl_4 <= not dcnt1;
  d_en0 <= dcnt0 and tmp_ivl_4;
  tmp_ivl_8 <= not dcnt0;
  tmp_ivl_10 <= not dcnt1;
  d_en1 <= tmp_ivl_8 and tmp_ivl_10;
  Q1 <= Q_data_p;
  Q0 <= Qq_n when FCLK = '1' else Qq_p;
  grstn <= '1';
  -- Removed one empty process
  
  
  -- Generated from always process in OSER8 (oser8.v:28)
  process (lrstn, grstn, PCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(PCLK) then
      if (not grstn) = '1' then
        Dd1 <= X"00";
        Ttx1 <= X"0";
      else
        if (not lrstn) = '1' then
          Dd1 <= X"00";
          Ttx1 <= X"0";
        else
          Dd1 <= D7 & D6 & D5 & D4 & D3 & D2 & D1 & D0;
          Ttx1 <= TX3 & TX2 & TX1 & TX0;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER8 (oser8.v:44)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        rstn_dsel <= '0';
      else
        if (not lrstn) = '1' then
          rstn_dsel <= '0';
        else
          rstn_dsel <= '1';
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER8 (oser8.v:57)
  process (FCLK, rstn_dsel) is
  begin
    if (not rstn_dsel) = '1' then
      dcnt0 <= '0';
      dcnt1 <= '0';
    elsif rising_edge(FCLK) then
      dcnt0 <= not dcnt0;
      dcnt1 <= dcnt0 xor dcnt1;
    end if;
  end process;
  
  -- Generated from always process in OSER8 (oser8.v:71)
  process (FCLK, rstn_dsel) is
  begin
    if (not rstn_dsel) = '1' then
      d_up0 <= '0';
    elsif rising_edge(FCLK) then
      if d_en0 = '1' then
        d_up0 <= '1';
      else
        d_up0 <= '0';
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER8 (oser8.v:84)
  process (FCLK, rstn_dsel) is
  begin
    if (not rstn_dsel) = '1' then
      d_up1 <= '0';
    elsif rising_edge(FCLK) then
      if d_en1 = '1' then
        d_up1 <= '1';
      else
        d_up1 <= '0';
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER8 (oser8.v:97)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Dd2 <= X"00";
        Ttx2 <= X"0";
      else
        if (not lrstn) = '1' then
          Dd2 <= X"00";
          Ttx2 <= X"0";
        else
          if d_up0 = '1' then
            Dd2 <= Dd1;
            Ttx2 <= Ttx1;
          else
            Dd2 <= Dd2;
            Ttx2 <= Ttx2;
          end if;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER8 (oser8.v:116)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Dd3 <= X"00";
        Ttx3 <= X"0";
      else
        if (not lrstn) = '1' then
          Dd3 <= X"00";
          Ttx3 <= X"0";
        else
          if d_up1 = '1' then
            Dd3 <= Dd2;
            Ttx3 <= Ttx2;
          else
            Dd3(0) <= Dd3(2);
            Dd3(1) <= Dd3(3);
            Dd3(2) <= Dd3(4);
            Dd3(3) <= Dd3(5);
            Dd3(4) <= Dd3(6);
            Dd3(5) <= Dd3(7);
            Dd3(6) <= '0';
            Dd3(7) <= '0';
            Ttx3(0) <= Ttx3(1);
            Ttx3(1) <= Ttx3(2);
            Ttx3(2) <= Ttx3(3);
            Ttx3(3) <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER8 (oser8.v:146)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Qq_p <= '0';
        Q_data_p <= '0';
      else
        if (not lrstn) = '1' then
          Qq_p <= '0';
          Q_data_p <= '0';
        else
          Qq_p <= Dd3(1);
          Q_data_p <= Q_data_n;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER8 (oser8.v:160)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or falling_edge(FCLK) then
      if (not grstn) = '1' then
        Qq_n <= '0';
        Q_data_n <= '0';
      else
        if (not lrstn) = '1' then
          Qq_n <= '0';
          Q_data_n <= '0';
        else
          Qq_n <= Dd3(0);
          Q_data_n <= Ttx3(0);
        end if;
      end if;
    end if;
  end process;
end architecture;

-- This VHDL was converted from Verilog using the
-- Icarus Verilog VHDL Code Generator 12.0 (stable) ()

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Generated from Verilog module OSER10 (oser10.v:2)
--   LSREN = "true"
entity OSER10 is
  GENERIC (
    GSREN : string := "false";
    LSREN : string := "true"
    );
  port (
    D0 : in std_logic;
    D1 : in std_logic;
    D2 : in std_logic;
    D3 : in std_logic;
    D4 : in std_logic;
    D5 : in std_logic;
    D6 : in std_logic;
    D7 : in std_logic;
    D8 : in std_logic;
    D9 : in std_logic;
    FCLK : in std_logic;
    PCLK : in std_logic;
    Q : out std_logic;
    RESET : in std_logic
  );
end entity; 

-- Generated from Verilog module OSER10 (oser10.v:2)
--   LSREN = "true"
architecture from_verilog of OSER10 is
  signal Dd1 : unsigned(9 downto 0);  -- Declared at oser10.v:10
  signal Dd2 : unsigned(9 downto 0);  -- Declared at oser10.v:10
  signal Dd3 : unsigned(9 downto 0);  -- Declared at oser10.v:10
  signal Qq_n : std_logic;  -- Declared at oser10.v:13
  signal Qq_p : std_logic;  -- Declared at oser10.v:13
  signal tmp_ivl_12 : std_logic;  -- Temporary created at oser10.v:63
  signal tmp_ivl_4 : std_logic;  -- Temporary created at oser10.v:62
  signal tmp_ivl_6 : std_logic;  -- Temporary created at oser10.v:62
  signal tmp_ivl_8 : std_logic;  -- Temporary created at oser10.v:62
  signal d_en : std_logic;  -- Declared at oser10.v:12
  signal d_up0 : std_logic;  -- Declared at oser10.v:11
  signal d_up1 : std_logic;  -- Declared at oser10.v:11
  signal dcnt0 : std_logic := '0';  -- Declared at oser10.v:11
  signal dcnt1 : std_logic := '0';  -- Declared at oser10.v:11
  signal dcnt2 : std_logic := '0';  -- Declared at oser10.v:11
  signal dcnt_reset : std_logic;  -- Declared at oser10.v:12
  signal grstn : std_logic;  -- Declared at oser10.v:14
  signal lrstn : std_logic;  -- Declared at oser10.v:14
  signal rstn_dsel : std_logic;  -- Declared at oser10.v:11
begin
  lrstn <= not RESET;
  tmp_ivl_4 <= not dcnt0;
  tmp_ivl_6 <= not dcnt1;
  tmp_ivl_8 <= tmp_ivl_4 and tmp_ivl_6;
  dcnt_reset <= tmp_ivl_8 and dcnt2;
  tmp_ivl_12 <= not dcnt0;
  d_en <= tmp_ivl_12 and dcnt1;
  Q <= Qq_n when FCLK = '1' else Qq_p;
  grstn <= '1';
  -- Removed one empty process
  
  
  -- Generated from always process in OSER10 (oser10.v:25)
  process (lrstn, grstn, PCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(PCLK) then
      if (not grstn) = '1' then
        Dd1 <= "0000000000";
      else
        if (not lrstn) = '1' then
          Dd1 <= "0000000000";
        else
          Dd1 <= D9 & D8 & D7 & D6 & D5 & D4 & D3 & D2 & D1 & D0;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER10 (oser10.v:36)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        rstn_dsel <= '0';
      else
        if (not lrstn) = '1' then
          rstn_dsel <= '0';
        else
          rstn_dsel <= '1';
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER10 (oser10.v:49)
  process (FCLK, rstn_dsel) is
  begin
    if (not rstn_dsel) = '1' then
      dcnt0 <= '0';
      dcnt1 <= '0';
      dcnt2 <= '0';
    elsif rising_edge(FCLK) then
      dcnt0 <= not (dcnt0 or dcnt_reset);
      dcnt1 <= (dcnt0 xor dcnt1) and (not dcnt_reset);
      dcnt2 <= (dcnt2 xor (dcnt0 and dcnt1)) and (not dcnt_reset);
    end if;
  end process;
  
  -- Generated from always process in OSER10 (oser10.v:65)
  process (FCLK, rstn_dsel) is
  begin
    if (not rstn_dsel) = '1' then
      d_up0 <= '0';
      d_up1 <= '0';
    elsif rising_edge(FCLK) then
      if d_en = '1' then
        d_up0 <= '1';
        d_up1 <= '1';
      else
        d_up0 <= '0';
        d_up1 <= '0';
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER10 (oser10.v:81)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Dd2 <= "0000000000";
      else
        if (not lrstn) = '1' then
          Dd2 <= "0000000000";
        else
          if d_up0 = '1' then
            Dd2 <= Dd1;
          else
            Dd2 <= Dd2;
          end if;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER10 (oser10.v:96)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Dd3 <= "0000000000";
      else
        if (not lrstn) = '1' then
          Dd3 <= "0000000000";
        else
          if d_up1 = '1' then
            Dd3 <= Dd2;
          else
            Dd3(0) <= Dd3(2);
            Dd3(1) <= Dd3(3);
            Dd3(2) <= Dd3(4);
            Dd3(3) <= Dd3(5);
            Dd3(4) <= Dd3(6);
            Dd3(5) <= Dd3(7);
            Dd3(6) <= Dd3(8);
            Dd3(7) <= Dd3(9);
            Dd3(8) <= '0';
            Dd3(9) <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER10 (oser10.v:120)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or rising_edge(FCLK) then
      if (not grstn) = '1' then
        Qq_p <= '0';
      else
        if (not lrstn) = '1' then
          Qq_p <= '0';
        else
          Qq_p <= Dd3(1);
        end if;
      end if;
    end if;
  end process;
  
  -- Generated from always process in OSER10 (oser10.v:131)
  process (lrstn, grstn, FCLK) is
  begin
    if falling_edge(lrstn) or falling_edge(grstn) or falling_edge(FCLK) then
      if (not grstn) = '1' then
        Qq_n <= '0';
      else
        if (not lrstn) = '1' then
          Qq_n <= '0';
        else
          Qq_n <= Dd3(0);
        end if;
      end if;
    end if;
  end process;
end architecture;



-- synthesis translate_on
