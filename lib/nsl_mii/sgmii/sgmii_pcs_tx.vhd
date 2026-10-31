library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
    flit_ready_o : out std_ulogic;

    symbol_o    : out nsl_line_coding.ibm_8b10b.data_t;
    disparity_o : out std_ulogic;

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
    -- True when the code group sent THIS cycle sits on an even position.
    -- Ordered sets (/I/, /C/) must start on even positions, so a frame
    -- must end on an even boundary: /T/R/ or /T/R/R/.
    even     : boolean;
    -- Running disparity BEFORE the code group sent THIS cycle (true =
    -- positive). This PCS is the single source of truth for RD: it is
    -- exported on disparity_o and the encoder is told to use it, so the
    -- encoder's own RD state is irrelevant.
    rd_pos   : boolean;
  end record;

  signal r, rin: regs_t;

  -- True if encoding this symbol changes the running disparity.
  -- A symbol flips RD iff exactly one of its two sub-blocks (5b/6b, 3b/4b)
  -- is unbalanced (carries +/-2 disparity).
  --   6b unbalanced: D.x for x in {0,1,2,4,8,15,16,23,24,27,29,30,31},
  --                  plus K28 (but D28 is balanced).
  --   4b unbalanced: .y for y in {0,4,7}.
  -- Consequences: K28.5 flips RD; K23.7/K27.7/K29.7/K30.7 do not;
  -- D16.2 flips RD; D5.6 does not.
  function flips_rd(sym : nsl_line_coding.ibm_8b10b.data_t) return boolean is
    variable x : natural range 0 to 31;
    variable y : natural range 0 to 7;
    variable six_unbal  : boolean;
    variable four_unbal : boolean;
  begin
    x := to_integer(unsigned(sym.data(4 downto 0)));
    y := to_integer(unsigned(sym.data(7 downto 5)));

    case x is
      when 0 | 1 | 2 | 4 | 8 | 15 | 16 | 23 | 24 | 27 | 29 | 30 | 31 =>
        six_unbal := true;
      when 28 =>
        six_unbal := (sym.control = '1');
      when others =>
        six_unbal := false;
    end case;

    four_unbal := (y = 0) or (y = 4) or (y = 7);

    return six_unbal xor four_unbal;
  end function;

  -- Code group the transmitter puts on the wire in the cycle the
  -- state machine is in state r. The running disparity after it is
  -- also needed to compute the next state, so the choice is a
  -- function of the state and the inputs rather than a side effect
  -- of the state transition.
  function symbol_for(r : regs_t;
                      flit : mii_flit_t;
                      config : config_reg_t;
                      link_up : std_ulogic) return nsl_line_coding.ibm_8b10b.data_t
  is
  begin
    case r.state is
      when ST_IDLE =>
        if link_up = '1' and flit.valid = '1' then
          return K27_7;
        else
          return K28_5;
        end if;

      when ST_I_D =>
        -- r.rd_pos is the RD after the K28.5 just sent. Pick the idle
        -- ordered set so that it always ends with negative RD:
        --   RD positive here -> /I2/ (D16.2 flips RD to negative)
        --   RD negative here -> /I1/ (D5.6 is balanced, RD stays negative)
        if r.rd_pos then
          return data(16, 2);
        else
          return data(5, 6);
        end if;

      when ST_C_D =>
        if r.c_toggle then
          return data(2, 2);
        else
          return data(21, 5);
        end if;

      when ST_C_LO =>
        return data(config(7 downto 0));

      when ST_C_HI =>
        return data(config(15 downto 8));

      when ST_F_DATA =>
        if link_up = '1' and flit.valid = '1' then
          return data(flit.data);
        else
          return K29_7;
        end if;

      when ST_F_T =>
        -- Not used as a distinct state; /T/ is output in the
        -- ST_F_DATA -> ST_F_R transition above. Kept for completeness.
        return K29_7;

      when ST_F_R =>
        return K23_7;
    end case;
  end function;

begin

  disparity_o <= '1' when r.rd_pos else '0';

  flit_ready_o <= '0' when link_up_i = '0'
                  else '0' when flit_i.valid = '1'
                                and r.state /= ST_IDLE
                                and r.state /= ST_F_DATA
                  else '1';

  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_IDLE;
      r.c_toggle <= false;
      r.even <= true;
      r.rd_pos <= false;
    end if;
  end process;

  transition: process(r, flit_i, send_config_i, config_i, link_up_i)
  begin
    rin <= r;
    rin.even <= not r.even;

    case r.state is
      when ST_IDLE =>
        if link_up_i = '1' and flit_i.valid = '1' then
          rin.state <= ST_F_DATA;
        elsif send_config_i = '1' then
          rin.state <= ST_C_D;
        else
          rin.state <= ST_I_D;
        end if;

      when ST_I_D =>
        rin.state <= ST_IDLE;

      when ST_C_D =>
        rin.c_toggle <= not r.c_toggle;
        rin.state <= ST_C_LO;

      when ST_C_LO =>
        rin.state <= ST_C_HI;

      when ST_C_HI =>
        rin.state <= ST_IDLE;

      when ST_F_DATA =>
        if link_up_i = '1' and flit_i.valid = '1' then
          rin.state <= ST_F_DATA;
        else
          rin.state <= ST_F_R;
        end if;

      when ST_F_T =>
        rin.state <= ST_F_R;

      when ST_F_R =>
        if r.even then
          -- This /R/ is on an even slot, so the next slot would be odd:
          -- pad with another /R/ so the following ordered set starts even.
          rin.state <= ST_F_R;
        else
          rin.state <= ST_IDLE;
        end if;
    end case;

    rin.rd_pos <= r.rd_pos
                  xor flips_rd(symbol_for(r, flit_i, config_i, link_up_i));
  end process;

  mealy: process(r, flit_i, config_i, link_up_i)
  begin
    symbol_o <= symbol_for(r, flit_i, config_i, link_up_i);
  end process;

end architecture;
