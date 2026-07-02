library ieee;
use ieee.std_logic_1164.all;

library nsl_line_coding, nsl_logic, work;
use nsl_line_coding.ibm_8b10b.all;
use nsl_logic.bool.all;
use work.flit.all;
use work.sgmii.all;

entity sgmii_pcs_tx is
  port(
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;

    flit_i      : in  mii_flit_t;

    symbol_o    : out nsl_line_coding.ibm_8b10b.data_t;

    send_config_i : in  std_ulogic;
    config_i      : in  config_reg_t;
    link_up_i     : in  std_ulogic
    );
end entity;

architecture beh of sgmii_pcs_tx is

  type state_t is (
    ST_IDLE,
    ST_I_D,
    ST_C_D,
    ST_C_LO,
    ST_C_HI,
    ST_F_DATA,
    ST_F_T,
    ST_F_R
    );

  type regs_t is
  record
    state    : state_t;
    c_toggle : boolean;
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
      r.c_toggle <= false;
    end if;
  end process;

  transition: process(r, flit_i, send_config_i, config_i, link_up_i)
  begin
    rin <= r;
    symbol_o <= K28_5;

    case r.state is
      when ST_IDLE =>
        if link_up_i = '1' and flit_i.valid = '1' then
          symbol_o <= K27_7;
          rin.state <= ST_F_DATA;
        elsif send_config_i = '1' then
          symbol_o <= K28_5;
          rin.state <= ST_C_D;
        else
          symbol_o <= K28_5;
          rin.state <= ST_I_D;
        end if;

      when ST_I_D =>
        symbol_o <= data(16, 2);
        rin.state <= ST_IDLE;

      when ST_C_D =>
        if r.c_toggle then
          symbol_o <= data(2, 2);
        else
          symbol_o <= data(21, 5);
        end if;
        rin.c_toggle <= not r.c_toggle;
        rin.state <= ST_C_LO;

      when ST_C_LO =>
        symbol_o <= data(config_i(7 downto 0));
        rin.state <= ST_C_HI;

      when ST_C_HI =>
        symbol_o <= data(config_i(15 downto 8));
        rin.state <= ST_IDLE;

      when ST_F_DATA =>
        if flit_i.valid = '1' then
          symbol_o <= data(flit_i.data);
          rin.state <= ST_F_DATA;
        else
          symbol_o <= K29_7;
          rin.state <= ST_F_R;
        end if;

      when ST_F_T =>
        -- Not used as a distinct state; /T/ is output in the
        -- ST_F_DATA → ST_F_R transition above. Kept for completeness.
        symbol_o <= K29_7;
        rin.state <= ST_F_R;

      when ST_F_R =>
        symbol_o <= K23_7;
        rin.state <= ST_IDLE;
    end case;
  end process;

end architecture;
