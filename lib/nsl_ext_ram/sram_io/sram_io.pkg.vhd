library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_io, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_ext_ram.timing.all;

-- Pin side of a synchronous SRAM controller.
--
-- One access per controller cycle: an address, a direction, and the
-- write payload that goes with it.  There is no command encoding to
-- speak of, so this boundary is nothing like the DFI one the DRAM
-- controllers use; what it shares is the rule that matters.
--
-- Latency belongs to the PHY.  The controller presents write data on
-- the same cycle as its command and the PHY puts it on the wire the
-- part's write latency later; the PHY raises rdata_valid when read
-- data has come back.  A core therefore never learns how far away the
-- part is, and a board that needs another cycle of flight is a PHY
-- generic rather than a different core.
package sram_io is

  constant max_dq_byte_count_c: natural := 8;
  constant max_address_width_c: natural := 24;

  subtype dq_t is byte_string(0 to max_dq_byte_count_c - 1);
  subtype lane_bits_t is std_ulogic_vector(0 to max_dq_byte_count_c - 1);

  -- Controller to PHY.
  type master_t is
  record
    valid: std_ulogic;
    write: std_ulogic;
    address: unsigned(max_address_width_c - 1 downto 0);
    -- Write payload, presented with its command.  A set mask bit
    -- leaves its byte lane untouched in the array.
    wdata: dq_t;
    wmask: lane_bits_t;
    wparity: lane_bits_t;
  end record;

  -- PHY to controller.
  type slave_t is
  record
    rdata: dq_t;
    rparity: lane_bits_t;
    -- Asserted on the cycle rdata holds the answer to a read
    rdata_valid: std_ulogic;
  end record;

  function master_idle(part_c: sram_part_t) return master_t;
  function read_command(part_c: sram_part_t;
                        address: unsigned) return master_t;
  function write_command(part_c: sram_part_t;
                         address: unsigned;
                         data: byte_string;
                         mask: std_ulogic_vector;
                         parity: std_ulogic_vector := "") return master_t;
  function slave_idle(part_c: sram_part_t) return slave_t;
  function rdata_beat(part_c: sram_part_t;
                      data: byte_string;
                      parity: std_ulogic_vector := "") return slave_t;

  -- The meaningful part of a payload, as the part's width says.
  function value(part_c: sram_part_t; dat: dq_t) return byte_string;
  function lanes(part_c: sram_part_t; bits: lane_bits_t)
    return std_ulogic_vector;

  -- Parity of each byte lane, for the ninth bit the part stores beside
  -- it.  The part gives that bit no meaning of its own -- it keeps
  -- what it is handed and returns it -- so any convention serves, as
  -- long as the writer and the reader share one.
  function lane_parity(data: byte_string) return std_ulogic_vector;

  component sram_phy is
    generic(
      part_c: sram_part_t;
      timing_c: sram_timing_t;
      -- Controller cycles from a command on io_i to its read data on
      -- io_o.  It counts the part's own latency, the output and input
      -- registers either side of it, and the flight time on the board.
      read_delay_ck_c: natural
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      io_i: in master_t;
      io_o: out slave_t;

      -- Forwarded half a period behind the controller clock, so the
      -- part samples in the middle of what the pins hold.
      clock_o: out std_ulogic;
      -- Chip select, the only one the part's three enables need
      cs_n_o: out std_ulogic;
      -- Clock enable.  Held asserted: the pipeline runs at a constant
      -- rate and select carries everything an idle cycle needs.
      cen_n_o: out std_ulogic;
      we_n_o: out std_ulogic;
      bw_n_o: out std_ulogic_vector;
      oe_n_o: out std_ulogic;
      a_o: out unsigned;
      dq_o: out nsl_io.io.tristated_vector;
      dq_i: in std_ulogic_vector;
      dqp_o: out nsl_io.io.tristated_vector;
      dqp_i: in std_ulogic_vector
      );
  end component;

end package sram_io;

package body sram_io is

  function master_idle(part_c: sram_part_t) return master_t
  is
    variable ret: master_t;
  begin
    ret.valid := '0';
    ret.write := '-';
    ret.address := (others => '-');
    ret.wdata := (others => dontcare_byte_c);
    ret.wmask := (others => '-');
    ret.wparity := (others => '-');

    return ret;
  end function;

  function read_command(part_c: sram_part_t;
                        address: unsigned) return master_t
  is
    variable ret: master_t := master_idle(part_c);
  begin
    ret.valid := '1';
    ret.write := '0';
    ret.address := resize(address, max_address_width_c);

    return ret;
  end function;

  function write_command(part_c: sram_part_t;
                         address: unsigned;
                         data: byte_string;
                         mask: std_ulogic_vector;
                         parity: std_ulogic_vector := "") return master_t
  is
    alias data_v: byte_string(0 to data'length - 1) is data;
    alias mask_v: std_ulogic_vector(0 to mask'length - 1) is mask;
    alias parity_v: std_ulogic_vector(0 to parity'length - 1) is parity;
    variable ret: master_t := master_idle(part_c);
  begin
    assert data'length = part_c.dq_byte_count
      report "sram_io: write payload is not the part's width"
      severity failure;

    ret.valid := '1';
    ret.write := '1';
    ret.address := resize(address, max_address_width_c);
    ret.wdata(0 to data'length - 1) := data_v;
    ret.wmask(0 to mask'length - 1) := mask_v;
    if parity'length = 0 then
      ret.wparity(0 to part_c.dq_byte_count - 1) := lane_parity(data_v);
    else
      ret.wparity(0 to parity'length - 1) := parity_v;
    end if;

    return ret;
  end function;

  function slave_idle(part_c: sram_part_t) return slave_t
  is
    variable ret: slave_t;
  begin
    ret.rdata := (others => dontcare_byte_c);
    ret.rparity := (others => '-');
    ret.rdata_valid := '0';

    return ret;
  end function;

  function rdata_beat(part_c: sram_part_t;
                      data: byte_string;
                      parity: std_ulogic_vector := "") return slave_t
  is
    alias data_v: byte_string(0 to data'length - 1) is data;
    alias parity_v: std_ulogic_vector(0 to parity'length - 1) is parity;
    variable ret: slave_t := slave_idle(part_c);
  begin
    ret.rdata_valid := '1';
    ret.rdata(0 to data'length - 1) := data_v;
    ret.rparity(0 to parity'length - 1) := parity_v;

    return ret;
  end function;

  function value(part_c: sram_part_t; dat: dq_t) return byte_string
  is
  begin
    return dat(0 to part_c.dq_byte_count - 1);
  end function;

  function lanes(part_c: sram_part_t; bits: lane_bits_t)
    return std_ulogic_vector
  is
  begin
    return bits(0 to part_c.dq_byte_count - 1);
  end function;

  function lane_parity(data: byte_string) return std_ulogic_vector
  is
    alias data_v: byte_string(0 to data'length - 1) is data;
    variable ret: std_ulogic_vector(0 to data'length - 1);
    variable bit_v: std_ulogic;
  begin
    for i in data_v'range
    loop
      bit_v := '0';
      for b in data_v(i)'range
      loop
        bit_v := bit_v xor data_v(i)(b);
      end loop;
      ret(i) := bit_v;
    end loop;

    return ret;
  end function;

end package body sram_io;
