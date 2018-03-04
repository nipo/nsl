library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.framed.all;
use nsl.sized.all;

entity sized_from_framed is
  generic(
    max_txn_length : natural := 2048
    );
  port(
    p_resetn    : in  std_ulogic;
    p_clk       : in  std_ulogic;

    p_in_val    : in framed_req;
    p_in_ack    : out framed_ack;

    p_out_val   : out sized_req;
    p_out_ack   : in sized_ack
    );
end entity;

architecture rtl of sized_from_framed is

  signal s_data_in_val, s_data_out_val: sized_req;
  signal s_data_in_ack, s_data_out_ack: sized_ack;

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

  transition: process(r, p_in_val, p_out_ack, s_data_out_val, s_data_in_ack)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_DATA;
        rin.count <= (rin.count'range => '1');

      when STATE_DATA =>
        if p_in_val.valid = '1' and s_data_in_ack.ready = '1' then
          rin.count <= r.count + 1;
          if p_in_val.last = '1' then
            rin.state <= STATE_SIZE_L;
          end if;
        end if;
        
      when STATE_SIZE_L =>
        if p_out_ack.ready = '1' then
          rin.state <= STATE_SIZE_H;
        end if;

      when STATE_SIZE_H =>
        if p_out_ack.ready = '1' then
          rin.state <= STATE_DATA_FLUSH;
        end if;

      when STATE_DATA_FLUSH =>
        if p_out_ack.ready = '1' and s_data_out_val.valid = '1' then
          rin.count <= r.count - 1;
          if r.count = 0 then
            rin.state <= STATE_DATA;
          end if;
        end if;
    end case;
  end process;

  data_fifo: nsl.sized.sized_fifo
    generic map(
      depth => max_txn_length,
      clk_count => 1
      )
    port map(
      p_resetn => p_resetn,
      p_clk(0) => p_clk,

      p_out_val => s_data_out_val,
      p_out_ack => s_data_out_ack,

      p_in_val => s_data_in_val,
      p_in_ack => s_data_in_ack
      );
  
  mux: process(r, p_in_val, s_data_in_ack, p_out_ack, s_data_out_val)
  begin
    p_out_val.valid <= '0';
    p_out_val.data <= (others => '-');
    s_data_in_val.valid <= '0';
    s_data_in_val.data <= (others => '-');
    p_in_ack.ready <= '0';
    s_data_out_ack.ready <= '0';

    case r.state is
      when STATE_RESET =>
        null;
        
      when STATE_DATA =>
        s_data_in_val.valid <= p_in_val.valid;
        s_data_in_val.data <= p_in_val.data;
        p_in_ack.ready <= s_data_in_ack.ready;

      when STATE_SIZE_L =>
        p_out_val.valid <= '1';
        p_out_val.data <= std_ulogic_vector(r.count(7 downto 0));

      when STATE_SIZE_H =>
        p_out_val.valid <= '1';
        p_out_val.data <= std_ulogic_vector(r.count(15 downto 8));

      when STATE_DATA_FLUSH =>
        p_out_val <= s_data_out_val;
        s_data_out_ack <= p_out_ack;

    end case;
  end process;

end architecture;
