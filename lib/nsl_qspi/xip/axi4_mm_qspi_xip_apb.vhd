library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_data, nsl_qspi;
use nsl_data.endian.all;

entity axi4_mm_qspi_xip_apb is
  generic(
    config_c: nsl_amba.axi4_mm.config_t;
    apb_config_c: nsl_amba.apb.config_t
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    apb_i: in nsl_amba.apb.master_t;
    apb_o: out nsl_amba.apb.slave_t;

    axi_i: in nsl_amba.axi4_mm.master_t;
    axi_o: out nsl_amba.axi4_mm.slave_t;

    cmd_o: out nsl_bnoc.framed.framed_req;
    cmd_i: in nsl_bnoc.framed.framed_ack;
    rsp_i: in nsl_bnoc.framed.framed_req;
    rsp_o: out nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of axi4_mm_qspi_xip_apb is

  type regs_t is
  record
    config: nsl_qspi.xip.xip_config_t;
  end record;

  signal r, rin: regs_t;

  signal reg_no_s: integer range 0 to 7;
  signal w_value_s: unsigned(31 downto 0);
  signal w_strobe_s: std_ulogic;
  signal r_value_s: unsigned(31 downto 0);
  signal r_strobe_s: std_ulogic;

begin

  assert apb_config_c.data_bus_width_l2 = 2
    report "QSPI XIP APB configuration interface must be 32 bits wide"
    severity failure;
  assert apb_config_c.address_width >= 5
    report "QSPI XIP APB configuration interface requires a 32-byte aperture"
    severity failure;

  regmap: nsl_amba.apb.apb_regmap
    generic map(
      config_c => apb_config_c,
      reg_count_l2_c => 3,
      endianness_c => ENDIAN_LITTLE
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      apb_i => apb_i,
      apb_o => apb_o,
      reg_no_o => reg_no_s,
      w_value_o => w_value_s,
      w_strobe_o => w_strobe_s,
      r_value_i => r_value_s,
      r_strobe_o => r_strobe_s
      );

  xip: nsl_qspi.xip.axi4_mm_qspi_xip
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      config_i => r.config,
      axi_i => axi_i,
      axi_o => axi_o,
      cmd_o => cmd_o,
      cmd_i => cmd_i,
      rsp_i => rsp_i,
      rsp_o => rsp_o
      );

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.config <= nsl_qspi.xip.xip_config_reset_c;
    end if;
  end process;

  transition: process(r, reg_no_s, w_value_s, w_strobe_s)
  begin
    rin <= r;

    if w_strobe_s = '1' then
      case reg_no_s is
        when 0 =>
          rin.config.enabled <= w_value_s(0) = '1';
          rin.config.quad_enable <= w_value_s(1) = '1';

        when 1 =>
          rin.config.flash_offset <= w_value_s;

        when 2 =>
          rin.config.divider <= to_integer(w_value_s(7 downto 0)) + 1;

        when 3 =>
          rin.config.single_profile.opcode <= std_ulogic_vector(w_value_s(7 downto 0));
          rin.config.single_profile.address_32 <= w_value_s(8) = '1';
          rin.config.single_profile.address_quad <= w_value_s(9) = '1';
          if to_integer(w_value_s(24 downto 16)) > 256 then
            rin.config.single_profile.dummy_cycles <= 256;
          else
            rin.config.single_profile.dummy_cycles <= to_integer(w_value_s(24 downto 16));
          end if;

        when 4 =>
          rin.config.quad_profile.opcode <= std_ulogic_vector(w_value_s(7 downto 0));
          rin.config.quad_profile.address_32 <= w_value_s(8) = '1';
          rin.config.quad_profile.address_quad <= w_value_s(9) = '1';
          if to_integer(w_value_s(24 downto 16)) > 256 then
            rin.config.quad_profile.dummy_cycles <= 256;
          else
            rin.config.quad_profile.dummy_cycles <= to_integer(w_value_s(24 downto 16));
          end if;

        when others =>
          null;
      end case;
    end if;
  end process;

  mealy: process(r, reg_no_s)
  begin
    r_value_s <= (others => '0');

    case reg_no_s is
      when 0 =>
        if r.config.enabled then
          r_value_s(0) <= '1';
        end if;

        if r.config.quad_enable then
          r_value_s(1) <= '1';
        end if;

      when 1 =>
        r_value_s <= r.config.flash_offset;

      when 2 =>
        r_value_s(7 downto 0) <= to_unsigned(r.config.divider-1, 8);

      when 3 =>
        r_value_s(7 downto 0) <= unsigned(r.config.single_profile.opcode);
        if r.config.single_profile.address_32 then
          r_value_s(8) <= '1';
        end if;

        if r.config.single_profile.address_quad then
          r_value_s(9) <= '1';
        end if;

        r_value_s(24 downto 16) <= to_unsigned(r.config.single_profile.dummy_cycles, 9);

      when 4 =>
        r_value_s(7 downto 0) <= unsigned(r.config.quad_profile.opcode);

        if r.config.quad_profile.address_32 then
          r_value_s(8) <= '1';
        end if;

        if r.config.quad_profile.address_quad then
          r_value_s(9) <= '1';
        end if;

        r_value_s(24 downto 16) <= to_unsigned(r.config.quad_profile.dummy_cycles, 9);

      when others =>
        null;
    end case;
  end process;
end architecture;
