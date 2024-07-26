library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.bytestream.all;

entity xonxoff_rx is
  generic(
    xoff_c: byte := x"13";
    xon_c: byte := x"11"
    );
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    ready_o : out std_ulogic;
    
    serdes_data_i  : in byte;
    serdes_valid_i : in std_ulogic;
    serdes_ready_o : out std_ulogic

    rx_data_o      : out byte;
    rx_valid_o     : out std_ulogic;
    rx_ready_i     : in std_ulogic
    );
end entity;

architecture beh of xonxoff_rx is

  constant fifo_depth_c : integer := 2;

  type regs_t is
  record
    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;
    ready: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if reset_n_i = '0' then
      r.fifo_fillness <= 0;
      r.ready <= '1';
    end if;
  end process;

  transition: process(r, rx_ready_i, serdes_valid_i, serdes_data_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    if rx_ready_i = '1' and r.fifo_fillness /= 0 then
      fifo_pop := true;
    end if;

    if serdes_valid_i = '1' and r.fifo_fillness < fifo_depth_c then
      if serdes_data_i = xon_c then
        rin.ready <= '1';
      elsif serdes_data_i = xoff_c then
        rin.ready <= '0';
      else
        fifo_push := true;
      end if;
    end if;
    
    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= serdes_data_i;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= serdes_data_i;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  serdes_ready_o <= '1' when r.fifo_fillness < fifo_depth_c else '0';
  rx_valid_o <= '1' when r.fifo_fillness /= 0 else '0';
  rx_data_o <= r.fifo(0);
  ready_o <= r.ready;

end architecture;
