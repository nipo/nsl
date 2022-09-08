library ieee;
use ieee.std_logic_1164.all;

library nsl_io, work, nsl_clocking, nsl_memory, nsl_logic;
use work.flit.all;
use work.link.all;
use work.rgmii.all;
use nsl_io.diff.all;
use nsl_logic.bool.all;

entity rgmii_tx_driver is
  generic(
    clock_delay_ps_c: natural := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    mode_i : in link_speed_t;
    flit_i : in rgmii_sdr_io_t;
    ready_o : out std_ulogic;

    sfd_o : out std_ulogic;

    rgmii_o : out rgmii_io_group_t
    );
end entity;

architecture beh of rgmii_tx_driver is

  type rgmii_bus is
  record
    f, s: rgmii_io_group_t;
  end record;

  signal rgmii_ddr_s: rgmii_io_group_t;

  function on_wire_first(data: rgmii_sdr_io_t;
                         clock: std_ulogic) return rgmii_io_group_t
  is
    variable ret : rgmii_io_group_t;
  begin
    ret.d := data.data(3 downto 0);
    ret.ctl := data.dv;
    ret.c := clock;
    return ret;
  end function;

  function on_wire_last(data: rgmii_sdr_io_t;
                        clock: std_ulogic) return rgmii_io_group_t
  is
    variable ret : rgmii_io_group_t;
  begin
    ret.d := data.data(7 downto 4);
    ret.ctl := data.dv xor data.er;
    ret.c := clock;
    return ret;
  end function;
  
  type regs_t is
  record
    div2: integer range 0 to 24;
    div: integer range 0 to 9;
    bus_out: rgmii_bus;
    frame_starting, sfd: boolean;
    mode : link_speed_t;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.mode <= LINK_SPEED_10;
      r.div <= 0;
      r.div2 <= 0;
    end if;
  end process;

  transition: process(r, flit_i, mode_i) is
  begin
    rin <= r;

    rin.mode <= mode_i;

    if r.mode /= mode_i then
      rin.div <= 0;
      rin.div2 <= 0;
    else
      case r.mode is
        when LINK_SPEED_10 =>
          -- In this mode, there is div2 doing a first divide by 25;
          -- then second div does 9, 6, 3, 0, which is piggy backed on
          -- matching states of the 100M mode.
          if r.div2 /= 0 then
            rin.div2 <= r.div2 - 1;
          else
            rin.div2 <= 24;

            if r.div /= 0 then
              rin.div <= r.div - 3;
            else
              rin.div <= 9;
            end if;
          end if;

        when LINK_SPEED_100 =>
          if r.div /= 0 then
            rin.div <= r.div - 1;
          else
            rin.div <= 9;
          end if;
          rin.div2 <= 0;

        when LINK_SPEED_1000 =>
          rin.div <= 0;
          rin.div2 <= 0;
      end case;
    end if;

    case r.mode is
      when LINK_SPEED_10 | LINK_SPEED_100 =>
        if r.div2 = 0 then
          case r.div is
            when 9 | 8 =>
              rin.bus_out.f <= on_wire_first(flit_i, '1');
              rin.bus_out.s <= on_wire_first(flit_i, '1');
            when 7 =>
              rin.bus_out.f <= on_wire_first(flit_i, '1');
              rin.bus_out.s <= on_wire_first(flit_i, '0');
            when 6 | 5 =>
              rin.bus_out.f <= on_wire_first(flit_i, '0');
              rin.bus_out.s <= on_wire_first(flit_i, '0');
            when 4 | 3 =>
              rin.bus_out.f <= on_wire_last(flit_i, '1');
              rin.bus_out.s <= on_wire_last(flit_i, '1');
            when 2 =>
              rin.bus_out.f <= on_wire_last(flit_i, '1');
              rin.bus_out.s <= on_wire_last(flit_i, '0');
            when 1 | 0 =>
              rin.bus_out.f <= on_wire_last(flit_i, '0');
              rin.bus_out.s <= on_wire_last(flit_i, '0');
            when others =>
              rin.bus_out.f <= on_wire_last(flit_i, '0');
              rin.bus_out.s <= on_wire_last(flit_i, '0');
          end case;
        end if;

      when LINK_SPEED_1000 =>
        rin.bus_out.f <= on_wire_first(flit_i, '1');
        rin.bus_out.s <= on_wire_last(flit_i, '0');
    end case;


    rin.sfd <= false;

    if r.div = 0 and r.div2 = 0 then
      if flit_i.dv = '0' then
        rin.frame_starting <= true;
      elsif flit_i.data = x"d5" and r.frame_starting then
        rin.frame_starting <= false;
        rin.sfd <= true;
      end if;
    end if;
  end process;

  sfd_o <= to_logic(r.sfd);
  ready_o <= to_logic(r.div = 0 and r.div2 = 0);
  
  ddr_output: nsl_io.ddr.ddr_bus_output
    generic map(
      ddr_width => 6
      )
    port map(
      clock_i          => to_diff(clock_i),
      d_i(3 downto 0)  => r.bus_out.f.d,
      d_i(4)           => r.bus_out.f.ctl,
      d_i(5)           => r.bus_out.f.c,
      d_i(9 downto 6)  => r.bus_out.s.d,
      d_i(10)          => r.bus_out.s.ctl,
      d_i(11)          => r.bus_out.s.c,
      dd_o(3 downto 0) => rgmii_ddr_s.d,
      dd_o(4)          => rgmii_ddr_s.ctl,
      dd_o(5)          => rgmii_ddr_s.c
      );

  clock_delay: nsl_io.delay.output_delay_fixed
    generic map(
      delay_ps_c => clock_delay_ps_c
      )
    port map(
      data_i => rgmii_ddr_s.c,
      data_o => rgmii_o.c
      );
  rgmii_o.ctl <= rgmii_ddr_s.ctl;
  rgmii_o.d <= rgmii_ddr_s.d;

end architecture;
