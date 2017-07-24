library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.mii.all;
use nsl.framed.all;

entity mii_to_framed is
  port(
    p_clk : in std_ulogic;
    p_resetn : in std_ulogic;

    p_mii_data : in mii_datapath;

    p_framed_val : out nsl.framed.framed_cmd;
    p_framed_ack : in nsl.framed.framed_rsp
    );
end entity;

architecture rtl of mii_to_framed is

  type state_t is (
    STATE_FILL0,
    STATE_FILL1,
    STATE_FILL2,
    STATE_FW0,
    STATE_FW1,
    STATE_LAST
    );
  
  type regs_t is record
    state: state_t;
    data_in: std_ulogic_vector(7 downto 0);
    data_out: std_ulogic_vector(7 downto 0);
  end record;
  
  signal r, rin : regs_t;

begin

  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= STATE_FILL0;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_mii_data, p_framed_ack)
  begin
    rin <= r;

    case r.state is
      when STATE_FILL0 =>
        if p_mii_data.dv = '1' then
          rin.state <= STATE_FILL1;
          rin.data_in(3 downto 0) <= p_mii_data.d;
        end if;

      when STATE_FILL1 =>
        rin.data_in(7 downto 4) <= p_mii_data.d;
        rin.state <= STATE_FILL2;

      when STATE_FW0 | STATE_FILL2 =>
        if p_mii_data.dv = '1' then
          rin.state <= STATE_FW1;
        else
          rin.state <= STATE_LAST;
        end if;
        rin.data_out <= r.data_in;
        rin.data_in(3 downto 0) <= p_mii_data.d;

      when STATE_FW1 =>
        rin.data_in(7 downto 4) <= p_mii_data.d;
        rin.state <= STATE_FW0;

      when STATE_LAST =>
        rin.state <= STATE_FILL0;
    end case;
  end process;
    
  moore: process(r, p_clk)
  begin
    case r.state is
      when STATE_FILL0 | STATE_FILL1 | STATE_FILL2 =>
        p_framed_val.val <= '0';
        p_framed_val.more <= '0';

      when STATE_FW0 =>
        p_framed_val.val <= '1';
        p_framed_val.more <= '1';

      when STATE_FW1 =>
        p_framed_val.val <= '0';
        p_framed_val.more <= '1';

      when STATE_LAST =>
        p_framed_val.val <= '1';
        p_framed_val.more <= '0';
    end case;
  end process;

  p_framed_val.data <= r.data_out;

end architecture;
