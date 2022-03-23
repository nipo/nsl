library ieee;
use ieee.std_logic_1164.all;

library nsl_data;
use nsl_data.bytestream.all;

package fifo is

  function fifo_shift_fillness(
    storage : byte_string;
    fillness : natural;

    valid : boolean;
    data : byte;

    ready : boolean
    ) return natural;

  function fifo_shift_data(
    storage : byte_string;
    fillness : natural;

    valid : boolean;
    data : byte;

    ready : boolean
    ) return byte_string;

  function fifo_can_push(
    storage : byte_string;
    fillness : natural) return boolean;

  function fifo_can_pop(
    storage : byte_string;
    fillness : natural) return boolean;

  function fifo_ready(
    storage : byte_string;
    fillness : natural) return std_ulogic;

  function fifo_valid(
    storage : byte_string;
    fillness : natural) return std_ulogic;

end package fifo;

package body fifo is

  function fifo_shift_data(
    storage : byte_string;
    fillness : natural;

    valid : boolean;
    data : byte;

    ready : boolean
    ) return byte_string
  is
    variable push, pop : boolean;
    variable ret: byte_string(storage'range);
  begin
    pop := ready and fillness /= 0;
    push := valid and fillness < storage'length;

    if pop then
      ret := shift_left(storage);
    else
      ret := storage;
    end if;

    if push then
      if pop then
        ret(fillness-1) := data;
      else
        ret(fillness) := data;
      end if;
    end if;

    return ret;
  end function;

  function fifo_shift_fillness(
    storage : byte_string;
    fillness : natural;

    valid : boolean;
    data : byte;

    ready : boolean
    ) return natural
  is
    variable push, pop : boolean;
  begin
    pop := ready and fillness /= 0;
    push := valid and fillness < storage'length;

    if push = pop then
      return fillness;
    elsif push then
      return fillness + 1;
    else
      return fillness - 1;
    end if;
  end function;

  function fifo_can_push(
    storage : byte_string;
    fillness : natural) return boolean
  is
  begin
    return fillness < storage'length;
  end function;

  function fifo_can_pop(
    storage : byte_string;
    fillness : natural) return boolean
  is
  begin
    return fillness /= 0;
  end function;

  function fifo_ready(
    storage : byte_string;
    fillness : natural) return std_ulogic
  is
  begin
    if fifo_can_push(storage, fillness) then
      return '1';
    else
      return '0';
    end if;
  end function;

  function fifo_valid(
    storage : byte_string;
    fillness : natural) return std_ulogic
  is
  begin
    if fifo_can_pop(storage, fillness) then
      return '1';
    else
      return '0';
    end if;
  end function;

end package body fifo;
