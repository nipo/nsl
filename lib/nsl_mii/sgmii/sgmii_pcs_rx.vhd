library ieee;
use ieee.std_logic_1164.all;

library nsl_line_coding, work;
use nsl_line_coding.ibm_8b10b.all;
use work.flit.all;
use work.sgmii.all;

entity sgmii_pcs_rx is
  port(
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;

    symbol_i    : in  nsl_line_coding.ibm_8b10b.data_t;
    symbol_expected_o : out std_ulogic;

    flit_o         : out mii_flit_t;
    config_valid_o : out std_ulogic;
    config_o       : out config_reg_t;
    valid_o        : out std_ulogic;
    idle_match_o   : out std_ulogic
    );
end entity;

architecture beh of sgmii_pcs_rx is

  type state_t is (
    ST_IDLE,
    ST_COMMA,
    ST_CONFIG_D,
    ST_CONFIG_LO,
    ST_DATA,
    ST_END_T
    );

  type regs_t is
  record
    state      : state_t;
    config_reg : config_reg_t;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_IDLE;
    end if;
  end process;

  transition: process(r, symbol_i)
  begin
    rin <= r;

    flit_o.data <= x"00";
    flit_o.valid <= '0';
    flit_o.error <= '0';
    config_valid_o <= '0';
    config_o <= r.config_reg;
    valid_o <= '0';
    symbol_expected_o <= '1';
    idle_match_o <= '0';

    case r.state is
      when ST_IDLE =>
        if symbol_i = K28_5 then
          rin.state <= ST_COMMA;
        elsif symbol_i = K27_7 then
          rin.state <= ST_DATA;
          flit_o.data <= x"55";
          flit_o.valid <= '1';
          valid_o <= '1';
        else
          symbol_expected_o <= '0';
        end if;

      when ST_COMMA =>
        if symbol_i = data(5, 6) or symbol_i = data(16, 2) then
          rin.state <= ST_IDLE;
          idle_match_o <= '1';
        elsif symbol_i = data(21, 5) or symbol_i = data(2, 2) then
          rin.state <= ST_CONFIG_D;
        elsif symbol_i = K27_7 then
          rin.state <= ST_DATA;
          flit_o.data <= x"55";
          flit_o.valid <= '1';
          valid_o <= '1';
        elsif symbol_i = K28_5 then
          rin.state <= ST_COMMA;
        else
          symbol_expected_o <= '0';
          rin.state <= ST_IDLE;
        end if;

      when ST_CONFIG_D =>
        if symbol_i.control = '0' then
          rin.state <= ST_CONFIG_LO;
          rin.config_reg(7 downto 0) <= symbol_i.data;
        else
          rin.state <= ST_IDLE;
        end if;

      when ST_CONFIG_LO =>
        if symbol_i.control = '0' then
          rin.state <= ST_IDLE;
          rin.config_reg(15 downto 8) <= symbol_i.data;
          config_valid_o <= '1';
          config_o <= symbol_i.data & r.config_reg(7 downto 0);
        else
          rin.state <= ST_IDLE;
        end if;

      when ST_DATA =>
        if symbol_i.control = '0' then
          flit_o.data <= symbol_i.data;
          flit_o.valid <= '1';
          valid_o <= '1';
        elsif symbol_i = K29_7 then
          rin.state <= ST_END_T;
          valid_o <= '1';
        elsif symbol_i = K30_7 then
          flit_o.data <= x"fe";
          flit_o.valid <= '1';
          flit_o.error <= '1';
          valid_o <= '1';
        else
          symbol_expected_o <= '0';
          flit_o.data <= symbol_i.data;
          flit_o.valid <= '1';
          flit_o.error <= '1';
          valid_o <= '1';
        end if;

      when ST_END_T =>
        if symbol_i = K23_7 then
          null; -- carrier extend, absorbed
        elsif symbol_i = K28_5 then
          rin.state <= ST_COMMA;
        else
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

end architecture;
