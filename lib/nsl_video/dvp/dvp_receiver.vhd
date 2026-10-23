library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dvp_receiver is
  generic(
    vsync_active_c: std_ulogic := '1';
    href_active_c: std_ulogic := '1'
    );
  port(
    pclk_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    vsync_i: in std_ulogic;
    href_i: in std_ulogic;
    data_i: in std_ulogic_vector(7 downto 0);

    valid_o: out std_ulogic;
    sof_o: out std_ulogic;
    sol_o: out std_ulogic;
    data_o: out std_ulogic_vector(15 downto 0)
    );
end entity;

architecture beh of dvp_receiver is

  type regs_t is
  record
    -- Bus as sampled, one cycle before being looked at, so inputs
    -- only drive a register.
    vsync, href: std_ulogic;
    data: std_ulogic_vector(7 downto 0);

    in_line, odd: boolean;
    sof_pending, sol_pending: boolean;
    high: std_ulogic_vector(7 downto 0);

    valid, sof, sol: boolean;
    word: std_ulogic_vector(15 downto 0);
  end record;

  signal r, rin: regs_t;

begin

  regs: process(pclk_i, reset_n_i) is
  begin
    if rising_edge(pclk_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.in_line <= false;
      r.odd <= false;
      r.sof_pending <= false;
      r.sol_pending <= false;
      r.valid <= false;
    end if;
  end process;

  transition: process(r, vsync_i, href_i, data_i) is
  begin
    rin <= r;

    rin.vsync <= vsync_i;
    rin.href <= href_i;
    rin.data <= data_i;

    rin.valid <= false;
    rin.in_line <= r.href = href_active_c;

    if r.vsync = vsync_active_c then
      rin.sof_pending <= true;
    end if;

    if r.href = href_active_c then
      if not r.in_line then
        rin.sol_pending <= true;
        rin.odd <= true;
        rin.high <= r.data;
      elsif not r.odd then
        rin.odd <= true;
        rin.high <= r.data;
      else
        rin.odd <= false;
        rin.valid <= true;
        rin.word <= r.high & r.data;
        rin.sof <= r.sof_pending;
        rin.sol <= r.sol_pending;
        rin.sof_pending <= false;
        rin.sol_pending <= false;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    valid_o <= '0';
    sof_o <= '0';
    sol_o <= '0';
    data_o <= r.word;

    if r.valid then
      valid_o <= '1';
      if r.sof then
        sof_o <= '1';
      end if;
      if r.sol then
        sol_o <= '1';
      end if;
    end if;
  end process;

end architecture;
