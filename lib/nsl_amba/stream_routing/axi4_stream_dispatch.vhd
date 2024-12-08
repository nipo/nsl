library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_math;
use nsl_amba.axi4_stream.all;

entity axi4_stream_dispatch is
  generic(
    in_config_c : config_t;
    out_config_c : config_t;
    destination_count_c : positive
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_vector(0 to destination_count_c-1);
    out_i : in slave_vector(0 to destination_count_c-1)
    );
end entity;

architecture beh of axi4_stream_dispatch is

  constant route_width_c : integer := in_config_c.id_width - out_config_c.id_width;
  
  type state_t is (
    ST_RESET,
    ST_ELECT,
    ST_FORWARD
    );

  type regs_t is record
    state : state_t;
    elected : natural range 0 to destination_count_c - 1;
  end record;

  signal r, rin: regs_t;
  
begin

  assert route_width_c >= nsl_math.arith.log2(destination_count_c)
    report "Input config should have additional ID bits to extract routing info"
    severity failure;
  
  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, in_i, out_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_ELECT;

      when ST_ELECT =>
        if is_valid(in_config_c, in_i) then
          rin.elected <= to_integer(unsigned(in_i.id(in_config_c.id_width-1 downto out_config_c.id_width)));
          rin.state <= ST_FORWARD;
        end if;

      when ST_FORWARD =>
        if is_valid(in_config_c, in_i)
          and is_last(in_config_c, in_i)
          and is_ready(out_config_c, out_i(r.elected)) then
          rin.state <= ST_ELECT;
        end if;
    end case;
  end process;

  mux: process(r, in_i, out_i)
  begin
    for i in out_o'range
    loop
      out_o(i) <= transfer(out_config_c, in_config_c, in_i);

      if i /= r.elected or r.state /= ST_FORWARD then
        out_o(i).valid <= '0';
      end if;
    end loop;

    in_o <= out_i(r.elected);

    if r.state /= ST_FORWARD then
      in_o.ready <= '0';
    end if;
  end process;

end architecture;
