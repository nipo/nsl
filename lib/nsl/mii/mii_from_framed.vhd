library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.mii.all;
use nsl.framed.all;

entity mii_from_framed is
  generic(
    inter_frame : natural := 56
    );
  port(
    p_clk : in std_ulogic;
    p_resetn : in std_ulogic;

    p_mii_data : out mii_datapath;

    p_framed_val : in nsl.framed.framed_req;
    p_framed_ack : out nsl.framed.framed_ack
    );
end entity;

architecture rtl of mii_from_framed is

  type state_t is (
    STATE_IDLE,
    STATE_FW0,
    STATE_FW1,
    STATE_IFS
    );
  
  type regs_t is record
    wait_ctr: natural range 0 to inter_frame;
    state: state_t;
    data: std_ulogic_vector(7 downto 0);
    underflow: std_ulogic;
    done: std_ulogic;
  end record;
  
  signal r, rin : regs_t;
  
begin

  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= STATE_IDLE;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_framed_val)
  begin
    rin <= r;

    case r.state is
      when STATE_IDLE =>
        if p_framed_val.val = '1' then
          rin.state <= STATE_FW0;
          rin.data <= p_framed_val.data;
          rin.underflow <= '0';
          rin.done <= '0';
        end if;

      when STATE_FW0 =>
        rin.state <= STATE_FW1;

      when STATE_FW1 =>
        if r.done = '1' then
          rin.state <= STATE_IFS;
          rin.wait_ctr <= inter_frame;
        else
          rin.state <= STATE_FW0;
          rin.done <= not p_framed_val.more;
          if p_framed_val.val = '1' then
            rin.data <= p_framed_val.data;
          else
            rin.data <= (others => 'X');
            rin.underflow <= '1';
          end if;
        end if;

      when STATE_IFS =>
        if r.wait_ctr = 0 then
          rin.state <= STATE_IDLE;
        else
          rin.wait_ctr <= r.wait_ctr - 1;
        end if;
    end case;
  end process;

  moore: process(r, p_clk)
  begin
    if falling_edge(p_clk) then
      case r.state is
        when STATE_IDLE =>
          p_mii_data.dv <= '0';
          p_mii_data.er <= '0';
          p_mii_data.d <= (others => 'X');
          p_framed_ack.ack <= '1';

        when STATE_FW0 =>
          p_mii_data.dv <= '1';
          p_mii_data.er <= r.underflow;
          p_mii_data.d <= r.data(3 downto 0);
          p_framed_ack.ack <= '0';

        when STATE_FW1 =>
          p_mii_data.dv <= '1';
          p_mii_data.er <= r.underflow;
          p_mii_data.d <= r.data(7 downto 4);
          p_framed_ack.ack <= not r.done;

        when STATE_IFS =>
          p_mii_data.dv <= '0';
          p_mii_data.er <= '0';
          p_mii_data.d <= (others => 'X');
          p_framed_ack.ack <= '0';
      end case;
    end if;
  end process;

end architecture;
