library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking;

entity interdomain_publish_counter is
  generic(
    data_width_c : integer;
    cycle_count_c : natural := 2;
    decode_stage_count_c : natural := 1
    );
  port(
    reset_n_i : in std_ulogic;
    clock_in_i : in std_ulogic;
    clock_out_i : in std_ulogic;

    target_i : in unsigned(data_width_c-1 downto 0);
    backward_i : in std_ulogic := '0';
    publish_o : out unsigned(data_width_c-1 downto 0);

    data_o : out unsigned(data_width_c-1 downto 0)
    );
end interdomain_publish_counter;

architecture beh of interdomain_publish_counter is

  type regs_t is
  record
    publish: unsigned(data_width_c-1 downto 0);
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_in_i, reset_n_i) is
  begin
    if rising_edge(clock_in_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.publish <= (others => '0');
    end if;
  end process;

  transition: process(r, target_i, backward_i) is
  begin
    rin <= r;

    if r.publish /= target_i then
      if backward_i = '1' then
        rin.publish <= r.publish - 1;
      else
        rin.publish <= r.publish + 1;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    publish_o <= r.publish;
  end process;

  crossing: nsl_clocking.interdomain.interdomain_counter
    generic map(
      cycle_count_c => cycle_count_c,
      data_width_c => data_width_c,
      decode_stage_count_c => decode_stage_count_c,
      input_is_gray_c => false,
      output_is_gray_c => false
      )
    port map(
      clock_in_i => clock_in_i,
      clock_out_i => clock_out_i,
      data_i => r.publish,
      data_o => data_o
      );

end beh;
