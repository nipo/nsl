library ieee;
use ieee.std_logic_1164.all;

library nsl_logic, work;
use nsl_logic.bool.all;
use work.sgmii.all;

entity sgmii_autoneg is
  generic(
    link_timer_cycles_c : natural := 1250000
    );
  port(
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;

    config_i    : in  config_reg_t;
    restart_i   : in  std_ulogic := '0';

    rx_config_valid_i : in  std_ulogic;
    rx_config_i       : in  config_reg_t;
    rx_idle_i         : in  std_ulogic;

    send_config_o    : out std_ulogic;
    tx_config_o      : out config_reg_t;
    link_up_o        : out std_ulogic;
    partner_config_o : out config_reg_t
    );
end entity;

architecture beh of sgmii_autoneg is

  constant ack_bit_c : natural := 14;
  constant match_count_c : natural := 3;

  type state_t is (
    ST_AN_ENABLE,
    ST_ABILITY_DETECT,
    ST_ACKNOWLEDGE_DETECT,
    ST_COMPLETE_ACKNOWLEDGE,
    ST_IDLE_DETECT,
    ST_LINK_OK
    );

  type regs_t is
  record
    state          : state_t;
    link_timer     : natural range 0 to link_timer_cycles_c;
    match_count    : natural range 0 to match_count_c;
    partner_config : config_reg_t;
    idle_count     : natural range 0 to match_count_c;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_AN_ENABLE;
      r.link_timer <= link_timer_cycles_c;
      r.match_count <= 0;
      r.partner_config <= (others => '0');
      r.idle_count <= 0;
    end if;
  end process;

  transition: process(r, config_i, restart_i, rx_config_valid_i,
                      rx_config_i, rx_idle_i)
  begin
    rin <= r;

    if restart_i = '1' then
      rin.state <= ST_AN_ENABLE;
      rin.link_timer <= link_timer_cycles_c;
      rin.match_count <= 0;
      rin.idle_count <= 0;
    else
      case r.state is
        when ST_AN_ENABLE =>
          if r.link_timer = 0 then
            rin.state <= ST_ABILITY_DETECT;
            rin.match_count <= 0;
          else
            rin.link_timer <= r.link_timer - 1;
          end if;

        when ST_ABILITY_DETECT =>
          if rx_config_valid_i = '1' then
            if rx_config_i = r.partner_config
              and r.match_count /= 0 then
              if r.match_count >= match_count_c - 1 then
                rin.state <= ST_ACKNOWLEDGE_DETECT;
              else
                rin.match_count <= r.match_count + 1;
              end if;
            else
              rin.partner_config <= rx_config_i;
              rin.match_count <= 1;
            end if;
          end if;

        when ST_ACKNOWLEDGE_DETECT =>
          if rx_config_valid_i = '1'
            and rx_config_i(ack_bit_c) = '1' then
            rin.state <= ST_COMPLETE_ACKNOWLEDGE;
            rin.link_timer <= link_timer_cycles_c;
          end if;

        when ST_COMPLETE_ACKNOWLEDGE =>
          if r.link_timer = 0 then
            rin.state <= ST_IDLE_DETECT;
            rin.idle_count <= 0;
          else
            rin.link_timer <= r.link_timer - 1;
          end if;

        when ST_IDLE_DETECT =>
          if rx_idle_i = '1' then
            if r.idle_count >= match_count_c - 1 then
              rin.state <= ST_LINK_OK;
            else
              rin.idle_count <= r.idle_count + 1;
            end if;
          end if;

        when ST_LINK_OK =>
          null;
      end case;
    end if;
  end process;

  moore: process(r, config_i)
  begin
    link_up_o <= '0';
    send_config_o <= '0';
    tx_config_o <= config_i;
    partner_config_o <= r.partner_config;

    case r.state is
      when ST_AN_ENABLE | ST_ABILITY_DETECT =>
        send_config_o <= '1';

      when ST_ACKNOWLEDGE_DETECT | ST_COMPLETE_ACKNOWLEDGE =>
        send_config_o <= '1';
        tx_config_o <= config_i(15) & '1' & config_i(13 downto 0);

      when ST_IDLE_DETECT =>
        null;

      when ST_LINK_OK =>
        link_up_o <= '1';
    end case;
  end process;

end architecture;
