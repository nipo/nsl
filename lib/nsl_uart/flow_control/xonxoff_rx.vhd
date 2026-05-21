library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_bnoc, nsl_logic;
use nsl_logic.bool.all;
use nsl_bnoc.pipe.all;
use nsl_data.bytestream.all;

entity xonxoff_rx is
  generic(
    xoff_c: byte := x"13";
    xon_c: byte := x"11";
    extra_rx_depth_c : natural := 2;
    timeout_after_c : natural := 0
    );
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    enable_i : in std_ulogic := '1';
    
    peer_ready_o : out std_ulogic;
    rx_ready_o : out std_ulogic;
    
    serdes_i : in pipe_req_t;
    serdes_o : out pipe_ack_t;

    rx_o : out pipe_req_t;
    rx_i : in pipe_ack_t
    );
end entity;

architecture beh of xonxoff_rx is

  constant fifo_depth_c : natural := 2 + extra_rx_depth_c;
  constant timeout_after_real_c : natural := if_else(timeout_after_c > 0, timeout_after_c - 1, 0);
  
  type regs_t is
  record
    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;
    peer_ready: std_ulogic;
    timeout: integer range 0 to timeout_after_real_c;
  end record;

  signal r, rin: regs_t;

  -- An incoming byte that is an XON/XOFF flow-control symbol. Such bytes are
  -- out-of-band: they must be interpreted and consumed even when the rx fifo
  -- is full, otherwise a stalled rx path would permanently mask the peer's
  -- keepalive and leave peer_ready latched low.
  signal flow_control_s : boolean;

begin

  flow_control_s <= enable_i = '1' and serdes_i.valid = '1'
                    and (serdes_i.data = xon_c or serdes_i.data = xoff_c);

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.fifo_fillness <= 0;
      r.timeout <= 0;
      r.peer_ready <= '1';
    end if;
  end process;

  transition: process(r, rx_i, serdes_i, enable_i, flow_control_s) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    if rx_i.ready = '1' and r.fifo_fillness /= 0 then
      fifo_pop := true;
    end if;

    if timeout_after_c /= 0 then
      if r.timeout /= 0 then
        rin.timeout <= r.timeout - 1;
      else
        rin.peer_ready <= '0';
      end if;
    end if;

    if flow_control_s then
      -- XON/XOFF is consumed here, never pushed to the fifo, regardless of
      -- fifo fullness.
      rin.timeout <= timeout_after_real_c;
      rin.peer_ready <= to_logic(serdes_i.data = xon_c);
    elsif serdes_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
      fifo_push := true;
    end if;
    
    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= serdes_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= serdes_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  serdes_o <= pipe_accept(flow_control_s or r.fifo_fillness < fifo_depth_c);
  rx_o <= pipe_flit(r.fifo(0), r.fifo_fillness /= 0);
  peer_ready_o <= r.peer_ready or not enable_i;
  rx_ready_o <= to_logic(r.fifo_fillness < 2);

end architecture;
