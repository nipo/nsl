library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.bytestream.all;

entity xonxoff_tx is
  generic(
    xoff_c: byte := x"13";
    xon_c: byte := x"11"
    );
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    ready_i     : in std_ulogic;

    tx_data_i  : in byte;
    tx_valid_i : in std_ulogic;
    tx_ready_o : out std_ulogic

    serdes_data_o      : out byte;
    serdes_valid_o     : out std_ulogic;
    serdes_ready_i     : in std_ulogic
    );
end entity;

architecture beh of xonxoff_tx is

  constant fifo_depth_c : integer := 2;

  type regs_t is
  record
    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;
    ready: std_ulogic;
    ready_changed: boolean;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if reset_n_i = '0' then
      r.fifo_fillness <= 0;
      r.ready <= '1';
      r.ready_changed <= false;
    end if;
  end process;

  transition: process(r, serdes_ready_i, tx_data_i, tx_valid_i, ready_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    if serdes_ready_i = '1' then
      if r.ready_changed then
        rin.ready_changed <= false;
      elsif r.fifo_fillness /= 0 then
        fifo_pop := true;
      end if;
    end if;

    if r.fifo_fillness < fifo_depth_c and tx_valid_i = '1' then
      fifo_push := true;
    end if;
    
    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= tx_data_i;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= tx_data_i;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;

    if ready_i /= r.ready then
      rin.ready_changed <= true;
      rin.ready <= ready_i;
    end if;
  end process;

  moore: process(r) is
  begin
    tx_ready_o <= '0';
    if r.fifo_fillness < fifo_depth_c then
      tx_ready_o <= '1';
    end if;

    serdes_valid_o <= '0';
    if r.ready_changed then
      serdes_valid_o <= '1';
      if r.ready = '1' then
        serdes_data_o <= xon_c;
      else
        serdes_data_o <= xoff_c;
      end if;
    elsif r.fifo_fillness /= 0 then
      serdes_valid_o <= '1';
      serdes_data_o <= r.fifo(0);
    end if;
  end process;

end architecture;
