library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ap_sim is
  port (
    p_clk : in std_ulogic;
    p_resetn : in std_ulogic;

    p_ready : out std_ulogic;

    p_ap : in unsigned(7 downto 0);

    p_a : in unsigned(5 downto 0);

    p_rdata : out unsigned(31 downto 0);
    p_rok : out std_logic;
    p_ren : in std_logic;

    p_wdata : in unsigned(31 downto 0);
    p_wen : in std_logic
    );
end entity;

architecture rtl of ap_sim is

  subtype data_t is unsigned(31 downto 0);
  type mem_t is array(natural range 0 to 63) of data_t;

  type regs_t is record
    waiting : integer;
    mem : mem_t;
    read_pending : boolean;
    raddr : natural range 0 to 63;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process (p_clk)
  begin
    if p_resetn = '0' then
      r.waiting <= 0;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  p_rok <= '1' when r.read_pending and r.waiting = 0 else '0';
  p_rdata <= r.mem(r.raddr) when r.read_pending and r.waiting = 0 else (p_rdata'range => '-');
  p_ready <= '1' when r.waiting = 0 else '0';
  
  transition: process (r, p_wen, p_ren, p_wdata, p_a)
    variable s_addr : natural range 0 to 63;
  begin
    s_addr := to_integer(to_01(p_a));
    rin <= r;

    if r.waiting > 0 then
      rin.waiting <= r.waiting - 1;
    else
      if r.read_pending then
        rin.read_pending <= false;
      end if;

      if p_wen = '1' then
        rin.mem(s_addr) <= p_wdata;
        rin.waiting <= 10;
      end if;

      if p_ren = '1' then
        rin.waiting <= 10;
        rin.read_pending <= true;
        rin.raddr <= s_addr;
      end if;
    end if;
  end process;
  
end architecture;

