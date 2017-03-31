library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.swd.all;

entity dap_sim is
  port (
    p_clk : in std_ulogic;
    p_dap_a : in unsigned(1 downto 0);
    p_dap_ad : in std_logic;
    p_dap_rdata : out unsigned(31 downto 0);
    p_dap_ready : out std_logic;
    p_dap_ren : in std_logic;
    p_dap_wdata : in unsigned(31 downto 0);
    p_dap_wen : in std_logic
    );
end entity;

architecture rtl of dap_sim is

  subtype data_t is unsigned(31 downto 0);
  type mem_t is array(natural range 0 to 7) of data_t;
  signal s_data : mem_t := (others => (others => '0'));
  signal s_ad : natural range 0 to 4;
  signal s_addr : natural range 0 to 7;
  signal waiting : integer := 0;
  
begin

  s_ad <= 4 when p_dap_ad = '1' else 0;
  s_addr <= to_integer(p_dap_a) + s_ad;
  p_dap_ready <= '1' when waiting = 0 else '0';
  p_dap_rdata <= s_data(s_addr);

  process (p_dap_wen, p_clk)
  begin
    if waiting /= 0 and rising_edge(p_clk) then
      waiting <= waiting - 1;
    elsif rising_edge(p_dap_wen) then
      s_data(s_addr) <= p_dap_wdata;
      if s_addr = 0 then
        waiting <= to_integer(p_dap_wdata(7 downto 0));
      end if;
    end if;
  end process;
  
end architecture;

