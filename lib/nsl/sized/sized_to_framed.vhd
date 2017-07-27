library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.framed.all;
use nsl.sized.all;

entity sized_to_framed is
  port(
    p_resetn    : in  std_ulogic;
    p_clk       : in  std_ulogic;

    p_inval     : out std_ulogic;

    p_out_val   : out framed_req;
    p_out_ack   : in  framed_ack;

    p_in_val    : in  sized_req;
    p_in_ack    : out sized_ack
    );
end entity;

architecture rtl of sized_to_framed is

  type state_t is (
    STATE_RESET,
    STATE_INVAL,
    STATE_SIZE_L,
    STATE_SIZE_H,
    STATE_DATA
    );
  
  type regs_t is record
    state: state_t;
    count: unsigned(15 downto 0);
  end record;
  
  signal r, rin : regs_t;
  
begin

  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= STATE_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_out_ack, p_in_val)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_SIZE_L;

      when STATE_INVAL =>
        if p_in_val.data = x"00" then
          rin.state <= STATE_RESET;
        end if;

      when STATE_SIZE_L =>
        if p_in_val.val = '1' then
          rin.count(7 downto 0) <= unsigned(p_in_val.data);
          rin.state <= STATE_SIZE_H;
        end if;

      when STATE_SIZE_H =>
        if p_in_val.val = '1' then
          rin.count(15 downto 8) <= unsigned(p_in_val.data);
          if r.count(7 downto 0) = x"FF" and p_in_val.data = x"FF" then
            rin.state <= STATE_INVAL;
          else
            rin.state <= STATE_DATA;
          end if;
        end if;

      when STATE_DATA =>
        if p_in_val.val = '1' and p_out_ack.ack = '1' then
          rin.count <= r.count - 1;
          if r.count = 0 then
            rin.state <= STATE_SIZE_L;
          end if;
        end if;
    end case;
  end process;

  output: process(r, p_out_ack, p_in_val)
  begin
    case r.state is
      when STATE_INVAL =>
        p_out_val.val <= '0';
        p_out_val.more <= '-';
        p_out_val.data <= (others => '-');
        p_in_ack.ack <= '1';
        p_inval <= '1';

      when STATE_RESET =>
        p_out_val.val <= '0';
        p_out_val.more <= '-';
        p_out_val.data <= (others => '-');
        p_in_ack.ack <= '0';
        p_inval <= '1';

      when STATE_SIZE_L | STATE_SIZE_H =>
        p_out_val.val <= '0';
        p_out_val.more <= '-';
        p_out_val.data <= (others => '-');
        p_in_ack.ack <= '1';
        p_inval <= '0';

      when STATE_DATA =>
        p_out_val.val <= p_in_val.val;
        p_out_val.data <= p_in_val.data;
        p_in_ack.ack <= p_out_ack.ack;
        if r.count /= 0 then
          p_out_val.more <= '1';
        else
          p_out_val.more <= '0';
        end if;
        p_inval <= '0';
    end case;
  end process;

end architecture;
