library ieee;
use ieee.std_logic_1164.all;

library nsl_memory, nsl_altera;

entity hps_bridge_channel is
  generic(
    width_c : positive;
    to_periphery_c : boolean;
    fifo_c : boolean
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_valid_i : in std_ulogic;
    in_data_i : in std_ulogic_vector(width_c-1 downto 0);
    in_ready_o : out std_ulogic;

    out_valid_o : out std_ulogic;
    out_data_o : out std_ulogic_vector(width_c-1 downto 0);
    out_ready_i : in std_ulogic
    );
end entity;

architecture beh of hps_bridge_channel is

  -- Beats the source may send after the receiving side deasserted
  -- its ready: one in each boundary register.
  constant in_flight_c : natural := 2;
  -- Fifo depth of the vendor adapters (2 ** 3 - 1)
  constant depth_c : positive := 7;

  signal fwd_in_s, fwd_out_s : std_ulogic_vector(width_c downto 0);
  signal ready_s, ready_out_s : std_ulogic_vector(0 downto 0);

begin

  fwd_in_s <= in_valid_i & in_data_i;

  fwd: nsl_altera.hps.hps_boundary_register
    generic map(
      width_c => width_c + 1,
      to_periphery_c => to_periphery_c
      )
    port map(
      clock_i => clock_i,
      data_i => fwd_in_s,
      data_o => fwd_out_s
      );

  bwd: nsl_altera.hps.hps_boundary_register
    generic map(
      width_c => 1,
      to_periphery_c => not to_periphery_c
      )
    port map(
      clock_i => clock_i,
      data_i => ready_s,
      data_o => ready_out_s
      );

  in_ready_o <= ready_out_s(0);

  direct: if not fifo_c
  generate
    out_valid_o <= fwd_out_s(width_c);
    out_data_o <= fwd_out_s(width_c-1 downto 0);
    ready_s(0) <= out_ready_i;
  end generate;

  buffered: if fifo_c
  generate
    -- Ready as the source saw it when it sent the beat now out of
    -- the forward register.
    signal ready_seen_s : std_ulogic;
    signal write_s, fifo_ready_s : std_ulogic;
    signal free_s : integer range 0 to depth_c;
  begin
    seen: process(clock_i)
    begin
      if rising_edge(clock_i) then
        ready_seen_s <= ready_out_s(0);
      end if;
    end process;

    write_s <= fwd_out_s(width_c) and ready_seen_s;

    fifo: nsl_memory.fifo.fifo_auto
      generic map(
        config_c => nsl_memory.fifo.fifo_config(
          data_width => width_c,
          word_count => depth_c,
          counters => true)
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i(0) => clock_i,
        out_data_o => out_data_o,
        out_ready_i => out_ready_i,
        out_valid_o => out_valid_o,
        in_data_i => fwd_out_s(width_c-1 downto 0),
        in_valid_i => write_s,
        in_ready_o => fifo_ready_s,
        in_free_o => free_s
        );

    ready_s(0) <= '1' when free_s > in_flight_c else '0';

    -- pragma translate_off
    overflow: process(clock_i)
    begin
      if rising_edge(clock_i) then
        assert reset_n_i = '0' or write_s /= '1' or fifo_ready_s = '1'
          report "hps_bridge_channel: beat accepted without room"
          severity failure;
      end if;
    end process;
    -- pragma translate_on
  end generate;

end architecture;
