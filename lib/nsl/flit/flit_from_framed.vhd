library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.flit.all;

entity flit_from_framed is
  generic(
    data_depth  : natural := 2048
    );
  port(
    p_resetn    : in  std_ulogic;
    p_clk       : in  std_ulogic;

    p_in_val    : in fifo_framed_cmd;
    p_in_ack    : out fifo_framed_rsp;

    p_out_val   : out flit_cmd;
    p_out_ack   : in flit_ack
    );
end entity;

architecture rtl of flit_from_framed is

  signal s_data_in_val, s_data_out_val: flit_cmd;
  signal s_data_in_ack, s_data_out_ack: flit_ack;

  type state_t is (
    STATE_RESET,
    STATE_DATA,
    STATE_SIZE_L,
    STATE_SIZE_H,
    STATE_DATA_FLUSH
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

  transition: process(r, p_in_val, p_out_ack,
                      s_data_out_val, s_data_in_ack)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_DATA;
        rin.count <= (rin.count'range => '1');

      when STATE_DATA =>
        if p_in_val.val = '1' and s_data_in_ack.ack = '1' then
          rin.count <= r.count + 1;
          if p_in_val.more = '0' then
            rin.state <= STATE_SIZE_L;
          end if;
        end if;
        
      when STATE_SIZE_L =>
        if p_out_ack.ack = '1' then
          rin.state <= STATE_SIZE_H;
        end if;

      when STATE_SIZE_H =>
        if p_out_ack.ack = '1' then
          rin.state <= STATE_DATA_FLUSH;
        end if;

      when STATE_DATA_FLUSH =>
        if p_out_ack.ack = '1' then
          rin.count <= r.count - 1;
          if r.count = 0 then
            rin.state <= STATE_DATA;
          end if;
        end if;
    end case;
  end process;

  data_fifo: nsl.flit.flit_fifo_sync
    generic map(
      depth => data_depth
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,

      p_out_val => s_data_out_val,
      p_out_ack => s_data_out_ack,

      p_in_val => s_data_in_val,
      p_in_ack => s_data_in_ack
      );

  moore: process(r, p_in_val, s_data_in_ack, p_out_ack, s_data_out_val)
  begin
    p_out_val.val <= '0';
    p_out_val.data <= (others => 'X');
    s_data_in_val.val <= '0';
    s_data_in_val.data <= (others => 'X');
    p_in_ack.ack <= '0';
    s_data_out_ack.ack <= '0';

    case r.state is
      when STATE_RESET =>
        null;
        
      when STATE_DATA =>
        s_data_in_val.val <= p_in_val.val;
        s_data_in_val.data <= p_in_val.data;
        p_in_ack.ack <= s_data_in_ack.ack;

      when STATE_SIZE_L =>
        p_out_val.val <= '1';
        p_out_val.data <= std_ulogic_vector(r.count(7 downto 0));

      when STATE_SIZE_H =>
        p_out_val.val <= '1';
        p_out_val.data <= std_ulogic_vector(r.count(15 downto 8));

      when STATE_DATA_FLUSH =>
        p_out_val.val <= s_data_out_val.val;
        p_out_val.data <= s_data_out_val.data;
        s_data_out_ack.ack <= p_out_ack.ack;

    end case;
  end process;

end architecture;
