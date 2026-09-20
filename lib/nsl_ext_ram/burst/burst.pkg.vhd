library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.bytestream.all;

-- Handshake between a memory controller's user side and its core.
--
-- One transfer is a whole burst at one address: a command, then the
-- payload, one controller cycle per beat.  Nothing here says what kind
-- of part is underneath, so the same AXI frontend serves a DRAM core
-- that has banks and rows and an SRAM core that has neither.
package burst is

  constant max_byte_address_width_c: natural := 34;
  -- Widest controller cycle any generation asks for: a DDR3 core runs
  -- eight phases of two edges over a four byte bus.
  constant max_cycle_byte_count_c: natural := 64;
  constant max_burst_cycle_count_c: natural := 16;

  subtype byte_address_t is unsigned(max_byte_address_width_c - 1 downto 0);
  subtype cycle_data_t is byte_string(0 to max_cycle_byte_count_c - 1);
  subtype cycle_mask_t is std_ulogic_vector(0 to max_cycle_byte_count_c - 1);

  -- One memory access: a whole burst at one address.
  type cmd_t is
  record
    valid: std_ulogic;
    write: std_ulogic;
    -- Address of the first byte, aligned on a burst
    address: byte_address_t;
  end record;

  type cmd_ack_t is
  record
    ready: std_ulogic;
  end record;

  -- Write payload, one controller cycle per beat.  A set mask bit
  -- leaves its byte untouched in the array.
  type wdata_t is
  record
    valid: std_ulogic;
    data: cycle_data_t;
    mask: cycle_mask_t;
  end record;

  type wdata_ack_t is
  record
    ready: std_ulogic;
  end record;

  type rdata_t is
  record
    valid: std_ulogic;
    data: cycle_data_t;
  end record;

  type rdata_ack_t is
  record
    ready: std_ulogic;
  end record;

  function cmd_idle return cmd_t;
  function cmd_request(address: unsigned; write: boolean) return cmd_t;
  function wdata_idle return wdata_t;
  function wdata_beat(data: byte_string;
                      mask: std_ulogic_vector := "") return wdata_t;
  function rdata_idle return rdata_t;
  function rdata_beat(data: byte_string) return rdata_t;
  function accept(ready: boolean) return cmd_ack_t;
  function accept(ready: boolean) return wdata_ack_t;
  function accept(ready: boolean) return rdata_ack_t;

end package burst;

package body burst is

  function cmd_idle return cmd_t
  is
    variable ret: cmd_t;
  begin
    ret.valid := '0';
    ret.write := '-';
    ret.address := (others => '-');

    return ret;
  end function;

  function cmd_request(address: unsigned; write: boolean) return cmd_t
  is
    variable ret: cmd_t;
  begin
    ret.valid := '1';
    if write then
      ret.write := '1';
    else
      ret.write := '0';
    end if;
    ret.address := resize(address, max_byte_address_width_c);

    return ret;
  end function;

  function wdata_idle return wdata_t
  is
    variable ret: wdata_t;
  begin
    ret.valid := '0';
    ret.data := (others => dontcare_byte_c);
    ret.mask := (others => '-');

    return ret;
  end function;

  function wdata_beat(data: byte_string;
                      mask: std_ulogic_vector := "") return wdata_t
  is
    alias data_v: byte_string(0 to data'length - 1) is data;
    alias mask_v: std_ulogic_vector(0 to mask'length - 1) is mask;
    variable ret: wdata_t;
  begin
    ret.valid := '1';
    ret.data := (others => dontcare_byte_c);
    ret.data(0 to data'length - 1) := data_v;
    ret.mask := (others => '-');
    if mask'length = 0 then
      ret.mask(0 to data'length - 1) := (0 to data'length - 1 => '0');
    else
      ret.mask(0 to mask'length - 1) := mask_v;
    end if;

    return ret;
  end function;

  function rdata_idle return rdata_t
  is
    variable ret: rdata_t;
  begin
    ret.valid := '0';
    ret.data := (others => dontcare_byte_c);

    return ret;
  end function;

  function rdata_beat(data: byte_string) return rdata_t
  is
    alias data_v: byte_string(0 to data'length - 1) is data;
    variable ret: rdata_t;
  begin
    ret.valid := '1';
    ret.data := (others => dontcare_byte_c);
    ret.data(0 to data'length - 1) := data_v;

    return ret;
  end function;

  function accept(ready: boolean) return cmd_ack_t
  is
    variable ret: cmd_ack_t;
  begin
    if ready then
      ret.ready := '1';
    else
      ret.ready := '0';
    end if;

    return ret;
  end function;

  function accept(ready: boolean) return wdata_ack_t
  is
    variable ret: wdata_ack_t;
  begin
    if ready then
      ret.ready := '1';
    else
      ret.ready := '0';
    end if;

    return ret;
  end function;

  function accept(ready: boolean) return rdata_ack_t
  is
    variable ret: rdata_ack_t;
  begin
    if ready then
      ret.ready := '1';
    else
      ret.ready := '0';
    end if;

    return ret;
  end function;

end package body burst;
