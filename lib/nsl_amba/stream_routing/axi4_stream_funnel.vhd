library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_math;
use nsl_amba.axi4_stream.all;

entity axi4_stream_funnel is
  generic(
    in_config_c : config_t;
    out_config_c : config_t;
    source_count_c : positive
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_vector(0 to source_count_c-1);
    in_o : out slave_vector(0 to source_count_c-1);

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of axi4_stream_funnel is

  constant route_width_c : integer := out_config_c.id_width - in_config_c.id_width;
  
  type state_t is (
    ST_RESET,
    ST_ELECT_FAIR,
    ST_ELECT,
    ST_FORWARD
    );

  type regs_t is record
    state : state_t;
    elected : natural range 0 to source_count_c - 1;
  end record;

  signal r, rin: regs_t;
  
begin

  assert route_width_c = 0 or 2 ** route_width_c <= source_count_c
    report "Output config should have additional ID bits to insert routing info"
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

      when ST_ELECT_FAIR =>
        rin.state <= ST_ELECT;
        for i in source_count_c - 1 downto 0 loop
          if is_valid(in_config_c, in_i(i))
            and i /= r.elected then
            rin.elected <= i;
            rin.state <= ST_FORWARD;
          end if;
        end loop;

      when ST_ELECT =>
        for i in source_count_c - 1 downto 0 loop
          if is_valid(in_config_c, in_i(i)) then
            rin.elected <= i;
            rin.state <= ST_FORWARD;
          end if;
        end loop;

      when ST_FORWARD =>
        if is_valid(in_config_c, in_i(r.elected))
          and is_last(in_config_c, in_i(r.elected))
          and is_ready(out_config_c, out_i) then
          rin.state <= ST_ELECT_FAIR;
        end if;
    end case;
  end process;

  mux: process(r, in_i, out_i)
  begin
    for i in in_o'range
    loop
      in_o(i) <= out_i;

      if i /= r.elected or r.state /= ST_FORWARD then
        in_o(i).ready <= '0';
      end if;
    end loop;

    out_o <= transfer(out_config_c, in_config_c, in_i(r.elected));
    if route_width_c /= 0 then
      out_o.id(out_config_c.id_width-1 downto in_config_c.id_width)
        <= std_ulogic_vector(to_unsigned(r.elected, route_width_c));
    end if;

    if r.state /= ST_FORWARD then
      out_o.valid <= '0';
    end if;
  end process;

end architecture;
