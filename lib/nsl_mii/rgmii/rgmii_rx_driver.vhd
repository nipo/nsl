library ieee;
use ieee.std_logic_1164.all;

library nsl_io, nsl_mii, nsl_clocking, nsl_memory, nsl_logic;
use nsl_mii.mii.all;
use nsl_mii.rgmii.all;
use nsl_io.diff.all;
use nsl_logic.bool.all;

entity rgmii_rx_driver is
  generic(
    clock_delay_ps_c: natural := 0
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    rx_clock_o : out std_ulogic;

    mode_i : in rgmii_mode_t;
    rgmii_i : in  nsl_mii.mii.rgmii_io_group_t;

    flit_o : out rgmii_sdr_io_t;
    valid_o : out std_ulogic
    );
end entity;

architecture beh of rgmii_rx_driver is

  type rgmii_in_group_t is record
    data : std_ulogic_vector(3 downto 0);
    ctl  : std_ulogic;
  end record;

  type rgmii_in_pipe_t is array (integer range <>) of rgmii_in_group_t;

  constant resync_depth_c : integer := 16;
  signal rgmii_sdr_s: rgmii_in_pipe_t(0 to 1);
  signal rgmii_ddr_s: rgmii_io_group_t;
  signal rgmii_clock_s, reset_n_s : std_ulogic;
  signal resync_free_s: integer range 0 to resync_depth_c;
  signal mode_s : std_ulogic_vector(1 downto 0);

  type state_t is (
    ST_UNSYNC,
    ST_INTERFRAME,
    ST_PREAMBLE,
    ST_PREAMBLE_FOUND,
    ST_FRAME
    );
  
  type regs_t is
  record
    pipe: rgmii_in_pipe_t(0 to 3);
    mode: rgmii_mode_t;
    reset_n: std_ulogic;

    is_second: boolean;
    state: state_t;
    
    flit : rgmii_sdr_io_t;
    flit_valid : std_ulogic;

    resync_pressure: boolean;
  end record;

  signal r, rin: regs_t;
  
begin

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => rgmii_clock_s,
      data_i => reset_n_i,
      data_o => reset_n_s
      );

  mode_resync: nsl_clocking.interdomain.interdomain_static_reg
    generic map(
      data_width_c => 2
      )
    port map(
      input_clock_i => clock_i,
      data_i => to_logic(mode_i),
      data_o => mode_s
      );
  
  regs: process(rgmii_clock_s, reset_n_s) is
  begin
    if rising_edge(rgmii_clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      r.reset_n <= '0';
      r.state <= ST_UNSYNC;
      r.is_second <= false;
      r.resync_pressure <= false;
    end if;
  end process;

  transition: process(r, rgmii_sdr_s, mode_s, resync_free_s) is
  begin
    rin <= r;

    rin.pipe <= r.pipe(2 to 3) & rgmii_sdr_s;
    rin.reset_n <= '1';

    if resync_free_s < 4 then
      rin.resync_pressure <= true;
    end if;

    rin.mode <= to_mode(mode_s);
    if r.mode /= to_mode(mode_s) then
      rin.reset_n <= '0';
      rin.state <= ST_UNSYNC;
      rin.is_second <= false;
      rin.resync_pressure <= false;
    end if;

    case r.mode is
      when RGMII_MODE_1000 =>
        -- All cycles are valid
        rin.flit_valid <= '1';
        rin.state <= ST_UNSYNC;
        -- Take both edges
        rin.flit.data <= r.pipe(1).data & r.pipe(0).data;
        rin.flit.dv <= r.pipe(0).ctl;
        rin.flit.er <= r.pipe(1).ctl xor r.pipe(0).ctl;

        if r.resync_pressure
          and r.pipe(0).ctl = '0'
          and r.pipe(1).ctl = '0'
          and r.pipe(2).ctl = '0'
          and r.pipe(3).ctl = '0' then
          rin.resync_pressure <= false;
          rin.flit_valid <= '0';
        end if;

      when RGMII_MODE_10 | RGMII_MODE_100 =>
        -- One cycle out of 2 is valid
        rin.is_second <= not r.is_second;
        rin.flit_valid <= to_logic(r.is_second);
        -- Take first half cycle, for two consecutive cycles
        rin.flit.data <= r.pipe(2).data & r.pipe(0).data;
        rin.flit.dv <= r.pipe(0).ctl and r.pipe(2).ctl;
        rin.flit.er <= r.pipe(2).ctl xor r.pipe(2).ctl;

        case r.state is
          when ST_UNSYNC =>
            -- Don't take anything
            rin.is_second <= false;
            rin.flit_valid <= '0';

          when ST_INTERFRAME =>
            if r.pipe(0).ctl = '1' and r.pipe(2).ctl = '1' then
              rin.state <= ST_PREAMBLE;
            end if;

          when ST_PREAMBLE =>
            if r.pipe(0).ctl = '1' and r.pipe(2).ctl = '1' and
              r.pipe(0).data = x"5" and r.pipe(2).data = x"5" then
              rin.state <= ST_PREAMBLE_FOUND;
            end if;

          when ST_PREAMBLE_FOUND =>
            -- On some phys (Like VSC8531), there may be an odd number
            -- of preamble nibbles in RGMII 10/100 mode. Realign here.
            if r.pipe(0).ctl = '1' and r.pipe(2).ctl = '1' and
              r.pipe(0).data = x"5" and r.pipe(2).data = x"d" then
              rin.state <= ST_FRAME;
              rin.is_second <= false;
              rin.flit_valid <= '1';
            end if;

          when ST_FRAME =>
            null;
        end case;

        -- Common
        if r.pipe(0).ctl = '0' and r.pipe(2).ctl = '0' then
          rin.state <= ST_INTERFRAME;
        end if;
    end case;
  end process;            
  
  cross_domain: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 10,
      word_count_c => resync_depth_c,
      output_slice_c => true,
      input_slice_c => true,
      clock_count_c => 2
      )
    port map(
      reset_n_i => r.reset_n,
      clock_i(0) => rgmii_clock_s,
      clock_i(1) => clock_i,

      out_data_o(7 downto 0) => flit_o.data,
      out_data_o(8) => flit_o.dv,
      out_data_o(9) => flit_o.er,
      out_valid_o => valid_o,
      out_ready_i => '1',

      in_data_i(7 downto 0) => r.flit.data,
      in_data_i(8) => r.flit.dv,
      in_data_i(9) => r.flit.er,
      in_valid_i => r.flit_valid,
      in_free_o => resync_free_s
      );

  from_rgmii_clock: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => rgmii_ddr_s.c,
      clock_o => rgmii_clock_s
      );

  rx_clock_o <= rgmii_clock_s;
  
  clock_delay: nsl_io.delay.input_delay_fixed
    generic map(
      delay_ps_c => clock_delay_ps_c
      )
    port map(
      data_i => rgmii_i.c,
      data_o => rgmii_ddr_s.c
      );
  rgmii_ddr_s.ctl <= rgmii_i.ctl;
  rgmii_ddr_s.d <= rgmii_i.d;
  
  ddr_input: nsl_io.ddr.ddr_bus_input
    generic map(
      ddr_width => 5,
      invert_clock_polarity_c => true
      )
    port map(
      clock_i          => to_diff(rgmii_clock_s),

      dd_i(3 downto 0) => rgmii_ddr_s.d,
      dd_i(4)          => rgmii_ddr_s.ctl,

      d_o(3 downto 0)  => rgmii_sdr_s(0).data,
      d_o(4)           => rgmii_sdr_s(0).ctl,
      d_o(8 downto 5)  => rgmii_sdr_s(1).data,
      d_o(9)           => rgmii_sdr_s(1).ctl
      );

end architecture;