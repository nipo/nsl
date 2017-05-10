library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.flit.all;

entity flit_to_framed is
  port(
    p_resetn    : in  std_ulogic;
    p_clk       : in  std_ulogic;

    p_out_val   : out fifo_framed_cmd;
    p_out_ack   : in  fifo_framed_rsp;

    p_in_val    : in  flit_cmd;
    p_in_ack    : out flit_ack
    );
end entity;

architecture rtl of flit_to_framed is

  type state_t is (
    STATE_SIZE,
    STATE_DATA
    );
  
  type regs_t is record
    state: state_t;
    count: unsigned(7 downto 0);
  end record;
  
  signal r, rin : regs_t;
  
begin

  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= STATE_SIZE;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_out_ack, p_in_val)
  begin
    rin <= r;

    case r.state is
      when STATE_SIZE =>
        if p_in_val.val = '1' then
          rin.count <= unsigned(p_in_val.data) - 1;
          rin.state <= STATE_DATA;
        end if;

      when STATE_DATA =>
        if p_in_val.val = '1' and p_out_ack.ack = '1' then
          rin.count <= r.count - x"01";
          if r.count = X"00" then
            rin.state <= STATE_SIZE;
          end if;
        end if;
    end case;
  end process;

  output: process(r, p_out_ack, p_in_val)
  begin
    case r.state is
      when STATE_SIZE =>
        p_out_val.val <= '0';
        p_out_val.more <= 'X';
        p_out_val.data <= (others => 'X');
        p_in_ack.ack <= '1';

      when STATE_DATA =>
        p_out_val.val <= p_in_val.val;
        p_out_val.data <= p_in_val.data;
        p_in_ack.ack <= p_out_ack.ack;
        if r.count /= (r.count'range => '0') then
          p_out_val.more <= '1';
        else
          p_out_val.more <= '0';
        end if;
    end case;
  end process;

end architecture;
