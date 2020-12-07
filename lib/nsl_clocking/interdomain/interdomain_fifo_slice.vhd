library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking;

entity interdomain_fifo_slice is
  generic(
    data_width_c   : integer
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic_vector(0 to 1);

    out_data_o  : out std_ulogic_vector(data_width_c-1 downto 0);
    out_ready_i : in  std_ulogic;
    out_valid_o : out std_ulogic;

    in_data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
    in_valid_i : in  std_ulogic;
    in_ready_o : out std_ulogic
    );
end entity;

architecture beh of interdomain_fifo_slice is

  type in_regs_t is
  record
    sn : std_ulogic;
    data : std_ulogic_vector(data_width_c-1 downto 0);
  end record;
  
  signal in_r, in_rin, out_sin : in_regs_t;

  signal ito_in, ito_out : std_ulogic_vector(data_width_c downto 0);
  
  type out_regs_t is
  record
    nesn : std_ulogic;
  end record;
  
  signal out_r, out_rin, in_sout : out_regs_t;
  signal s_resetn : std_ulogic_vector(0 to 1);

begin

  reset_sync: nsl_clocking.async.async_multi_reset
    generic map(
      domain_count_c => 2,
      debounce_count_c => 5
      )
    port map(
      clock_i => clock_i,
      master_i => reset_n_i,
      slave_o => s_resetn
      );

  in_regs: process(clock_i(0), s_resetn(0))
  begin
    if s_resetn(0) = '0' then
      in_r.sn <= '0';
    elsif not clock_i(0)'stable and clock_i(0) = '1' then
      in_r <= in_rin;
    end if;
  end process;

  out_regs: process(clock_i(1), s_resetn(1))
  begin
    if s_resetn(1) = '0' then
      out_r.nesn <= '1';
    elsif not clock_i(1)'stable and clock_i(1) = '1' then
      out_r <= out_rin;
    end if;
  end process;

  in_transition: process(in_data_i, in_valid_i, in_r, in_sout)
  begin
    in_rin <= in_r;

    if in_r.sn /= in_sout.nesn and in_valid_i = '1' then
      in_rin.data <= in_data_i;
      in_rin.sn <= not in_r.sn;
    end if;
  end process;

  in_ready_o <= '1' when in_r.sn /= in_sout.nesn else '0';

  out_transition: process(out_ready_i, out_r, out_sin)
  begin
    out_rin <= out_r;

    if out_sin.sn = out_r.nesn and out_ready_i = '1' then
      out_rin.nesn <= not out_r.nesn;
    end if;
  end process;

  out_valid_o <= '1' when out_sin.sn = out_r.nesn else '0';
  out_data_o <= out_sin.data;

  in_to_out_sn: nsl_clocking.interdomain.interdomain_reg
    generic map(
      stable_count_c => 1,
      cycle_count_c => 2,
      data_width_c => 1 + data_width_c
      )
    port map(
      clock_i => clock_i(1),
      data_i => ito_in,
      data_o => ito_out
      );
  
  ito_in <= in_r.sn & in_r.data;
  out_sin.data <= ito_out(out_sin.data'range);
  out_sin.sn <= ito_out(out_sin.data'length);

  out_to_in: nsl_clocking.interdomain.interdomain_reg
    generic map(
      cycle_count_c => 2,
      data_width_c => 1
      )
    port map(
      clock_i => clock_i(0),
      data_i(0) => out_r.nesn,
      data_o(0) => in_sout.nesn
      );
  
end architecture;
