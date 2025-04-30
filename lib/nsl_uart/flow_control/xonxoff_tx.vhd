library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_bnoc;
use nsl_bnoc.pipe.all;
use nsl_data.bytestream.all;

entity xonxoff_tx is
  generic(
    xoff_c: byte := x"13";
    xon_c: byte := x"11";
    refresh_every_c : integer := 0
    );
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    enable_i : in std_ulogic := '1';

    can_transmit_i : in std_ulogic := '1';
    can_receive_i : in std_ulogic := '1';

    tx_i : in pipe_req_t;
    tx_o : out pipe_ack_t;

    serdes_o : out pipe_req_t;
    serdes_i : in pipe_ack_t
    );
end entity;

architecture beh of xonxoff_tx is

  constant fifo_depth_c : integer := 2;

  type regs_t is
  record
    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;
    can_transmit: boolean;
    can_receive: boolean;
    can_receive_changed: boolean;
    can_receive_refresh: integer range 0 to refresh_every_c;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.fifo_fillness <= 0;
      r.can_transmit <= false;
      r.can_receive <= true;
      r.can_receive_changed <= false;
      r.can_receive_refresh <= refresh_every_c;
    end if;
  end process;

  transition: process(r, serdes_i, tx_i, tx_i, can_receive_i, can_transmit_i, enable_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    rin.can_transmit <= can_transmit_i = '1';

    if serdes_i.ready = '1' then
      if r.can_receive_changed then
        rin.can_receive_changed <= false;
      elsif r.fifo_fillness /= 0 and r.can_transmit then
        fifo_pop := true;
      end if;
    end if;

    if refresh_every_c /= 0 then
      if r.can_receive_changed then
        rin.can_receive_refresh <= refresh_every_c;
      elsif r.can_receive_refresh /= 0 then
        rin.can_receive_refresh <= r.can_receive_refresh - 1;
      else
        rin.can_receive_changed <= true;
      end if;
    end if;

    if r.fifo_fillness < fifo_depth_c and tx_i.valid = '1' then
      fifo_push := true;
    end if;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= tx_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= tx_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;

    if (can_receive_i = '1') /= r.can_receive then
      rin.can_receive_changed <= true;
      rin.can_receive <= can_receive_i = '1';
    end if;

    if enable_i = '0' then
      rin.can_receive_changed <= false;
      rin.can_receive <= true;
      rin.can_transmit <= true;
      rin.can_receive_refresh <= refresh_every_c;
    end if;
  end process;

  moore: process(r) is
  begin
    tx_o <= pipe_accept(r.fifo_fillness < fifo_depth_c);
    serdes_o <= pipe_req_idle_c;

    if r.can_receive_changed then
      if r.can_receive then
        serdes_o <= pipe_flit(xon_c);
      else
        serdes_o <= pipe_flit(xoff_c);
      end if;
    elsif r.can_transmit then
      serdes_o <= pipe_flit(r.fifo(0), valid => r.fifo_fillness /= 0);
    end if;
  end process;

end architecture;
