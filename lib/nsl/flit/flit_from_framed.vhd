library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.flit.all;

entity flit_from_framed is
  generic(
    data_depth  : natural := 512;
    txn_depth   : natural := 4
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

  signal s_data_in_val, s_data_out_val, s_size_in_val, s_size_out_val: flit_cmd;
  signal s_data_in_ack, s_data_out_ack, s_size_in_ack, s_size_out_ack: flit_ack;

  type state_t is (
    STATE_DATA,
    STATE_HEADER
    );
  
  type regs_t is record
    in_state, out_state: state_t;
    out_count, in_count: unsigned(7 downto 0);
  end record;
  
  signal r, rin : regs_t;
  
begin

  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.out_count <= x"00";
      r.in_count <= x"00";
      r.in_state <= STATE_DATA;
      r.out_state <= STATE_HEADER;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_in_val, p_out_ack,
                      s_data_in_ack, s_size_in_ack,
                      s_data_out_val, s_size_out_val)
  begin
    rin <= r;

    case r.in_state is
      when STATE_DATA =>
        if p_in_val.val = '1' and s_data_in_ack.ack = '1' then
          rin.in_count <= r.in_count + 1;
          if p_in_val.more = '0' then
            rin.in_state <= STATE_HEADER;
          end if;
        end if;

      when STATE_HEADER =>
        if s_size_in_ack.ack = '1' then
          rin.in_state <= STATE_DATA;
          rin.in_count <= (others => '0');
        end if;
    end case;
    
    case r.out_state is
      when STATE_DATA =>
        if s_data_out_val.val = '1' and p_out_ack.ack = '1' then
          rin.out_count <= r.out_count - 1;
          if r.out_count = X"00" then
            rin.out_state <= STATE_HEADER;
          end if;
        end if;

      when STATE_HEADER =>
        if s_size_out_val.val = '1' and p_out_ack.ack = '1' then
          rin.out_state <= STATE_DATA;
          rin.out_count <= unsigned(s_size_out_val.data) - 1;
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

  p_in: process(r.in_state, s_data_in_ack, p_in_val)
  begin
    case r.in_state is
      when STATE_DATA =>
        p_in_ack.ack <= s_data_in_ack.ack;
        s_data_in_val.val <= p_in_val.val;
        s_size_in_val.val <= '0';
      when STATE_HEADER =>
        p_in_ack.ack <= '0';
        s_data_in_val.val <= '0';
        s_size_in_val.val <= '1';
    end case;
    s_size_in_val.data <= std_ulogic_vector(r.in_count);
    s_data_in_val.data <= p_in_val.data;
  end process;
  
  size_fifo: nsl.flit.flit_fifo_sync
    generic map(
      depth => txn_depth
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,

      p_out_val => s_size_out_val,
      p_out_ack => s_size_out_ack,
      p_in_val => s_size_in_val,
      p_in_ack => s_size_in_ack
      );

  p_out: process(r.out_state, s_size_out_val, s_data_out_val, p_out_ack)
  begin
    case r.out_state is
      when STATE_HEADER =>
        p_out_val <= s_size_out_val;
        s_data_out_ack.ack <= '0';
        s_size_out_ack.ack <= p_out_ack.ack;

      when STATE_DATA =>
        p_out_val <= s_data_out_val;
        s_data_out_ack.ack <= p_out_ack.ack;
        s_size_out_ack.ack <= '0';
    end case;
  end process;

end architecture;
