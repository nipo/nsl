library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_sdio;
use nsl_data.bytestream.all;
use nsl_data.crc.all;

-- Simulation models of what sits at the far end of an SD bus.
package testing is

  -- A card's 128-bit register, with the checksum placed where a card
  -- places it: over the first 120 bits, in bits 7 to 1, followed by a
  -- one.  The trailing bits of the argument are ignored.
  function card_register(content: std_ulogic_vector) return std_ulogic_vector;

  -- Answer to a command, from its start bit to its end bit.  Index is
  -- the six bits a card puts after the direction bit, which is the
  -- index of the command answered for most commands and ones for the
  -- answers that have no room for it.
  function short_response(index: natural;
                          payload: std_ulogic_vector;
                          with_crc: boolean := true)
    return std_ulogic_vector;

  -- Answer carrying one of the card's registers, checksum included,
  -- from its start bit to its end bit.  The end bit is the register's
  -- own trailing one.
  function long_response(content: std_ulogic_vector)
    return std_ulogic_vector;

  -- Bits one data line carries for a block, in the order it carries
  -- them.  A byte goes out from its top, and within the group of bits
  -- the lines carry together, the highest line takes the highest bit.
  function to_lane_bits(data: byte_string;
                        width: nsl_sdio.sdio.bus_width_t;
                        lane: natural) return std_ulogic_vector;

  -- Puts what one line carried back where it belongs in a block
  procedure lane_bits_merge(data: inout byte_string;
                            bits: in std_ulogic_vector;
                            width: in nsl_sdio.sdio.bus_width_t;
                            lane: in natural);

  -- Checksum of what one line carried, highest coefficient in the
  -- highest bit, which is the order the line carries it in
  function lane_crc(bits: std_ulogic_vector) return std_ulogic_vector;

  -- Content a block holds until something writes to it, derived from
  -- its address so that a whole card takes no memory to model.
  function default_block(lba: unsigned;
                         byte_count: positive := 512) return byte_string;

  -- Identification of the modelled card: a made-up manufacturer, a
  -- product name and a serial number.
  constant default_cid_c: std_ulogic_vector(127 downto 8)
    := x"9f4e534e534c534401123456780199";

  -- Specific data of a high capacity card holding block_count blocks
  -- of 512 bytes, which the capacity field counts in groups of 1024.
  function csd_v2(block_count: natural;
                  high_speed: boolean := true) return std_ulogic_vector;

  -- A card on an SD bus: the identification sequence, the states it
  -- walks through, the registers it answers with, and single and
  -- multiple block transfers over one or four data lines.
  --
  -- Command and data are two engines in a card, and they are two
  -- processes here, so a host that stops a stream mid block is
  -- answered while that block is still going out.
  --
  -- Blocks read back what their address says they hold until written,
  -- which is what makes a card of any size fit in a model.  Only
  -- blocks of 512 bytes exist, as on any card holding more than two
  -- gigabytes.
  --
  -- Timings are those of a card rather than of an ideal wire.  The
  -- model answers a while after the edge a card answers, leaves the
  -- wires indeterminate in between, and reads what a host drives on
  -- the rising edge with a setup check.  A host sampling where a card
  -- is not holding anything steady therefore fails here the way it
  -- would fail on a bus.
  component testing_card_model is
    generic(
      -- Edge the card answers.  Default speed is the falling one,
      -- which is what a card comes up in.
      output_edge_c: nsl_sdio.link.card_output_edge_t
        := nsl_sdio.link.OUTPUT_ON_FALLING;
      -- Delay from that edge to the moment the card puts the matching
      -- value on the wires.  A card is allowed 14 ns.
      output_delay_c: time := 14 ns;
      -- How long the card still holds the previous value past that
      -- edge.  Between the two, the wires carry nothing a host may
      -- read, and this model says so.
      output_hold_c: time := 2500 ps;
      -- Setup a card needs on its inputs, which it checks rather than
      -- relies on
      input_setup_c: time := 5 ns;
      -- Bus periods between the end of a command and the start of its
      -- answer.  The bus allows 2 to 64.
      response_delay_cycle_c: natural := 4;
      -- Bus periods a card holds DAT0 low after answering a command
      -- that leaves it busy, and after storing a block
      busy_cycle_c: natural := 12;
      -- Bus periods between the end of a command's answer and the
      -- block the card sends for it
      data_delay_cycle_c: natural := 4;
      -- Blocks the model remembers having been written.  Every other
      -- block reads back as whatever its address says it holds.
      written_block_count_c: natural := 8;
      -- Times the card claims to be still powering up before it
      -- answers that it is ready
      power_up_poll_count_c: natural := 3;
      cid_c: std_ulogic_vector(127 downto 8) := default_cid_c;
      block_count_c: natural := 65536
      );
    port(
      sdio_i: in nsl_sdio.sdio.sdio_slave_i;
      sdio_o: out nsl_sdio.sdio.sdio_slave_o
      );
  end component;

end package testing;

package body testing is

  function to_lane_bits(data: byte_string;
                        width: nsl_sdio.sdio.bus_width_t;
                        lane: natural) return std_ulogic_vector
  is
    constant lane_count_c: natural := nsl_sdio.sdio.lane_count(width);
    constant group_count_c: natural := 8 / lane_count_c;
    variable ret: std_ulogic_vector(0 to data'length * group_count_c - 1);
  begin
    for i in 0 to data'length - 1
    loop
      for g in 0 to group_count_c - 1
      loop
        ret(i * group_count_c + g)
          := data(data'low + i)(8 - (g + 1) * lane_count_c + lane);
      end loop;
    end loop;

    return ret;
  end function;

  procedure lane_bits_merge(data: inout byte_string;
                            bits: in std_ulogic_vector;
                            width: in nsl_sdio.sdio.bus_width_t;
                            lane: in natural)
  is
    constant lane_count_c: natural := nsl_sdio.sdio.lane_count(width);
    constant group_count_c: natural := 8 / lane_count_c;
  begin
    for i in 0 to data'length - 1
    loop
      for g in 0 to group_count_c - 1
      loop
        data(data'low + i)(8 - (g + 1) * lane_count_c + lane)
          := bits(bits'low + i * group_count_c + g);
      end loop;
    end loop;
  end procedure;

  function lane_crc(bits: std_ulogic_vector) return std_ulogic_vector
  is
    variable state: crc_state_t := crc_init(nsl_sdio.link.dat_crc_params_c);
    variable ret: std_ulogic_vector(15 downto 0);
  begin
    -- Bit at a time rather than over the whole string: the parallel
    -- form of the update builds a mask per output bit, which for a
    -- block's worth of bits costs more than the simulation it serves.
    for i in bits'range
    loop
      state := crc_update(nsl_sdio.link.dat_crc_params_c, state, bits(i));
    end loop;

    ret := crc_spill_vector(nsl_sdio.link.dat_crc_params_c, state);

    return ret;
  end function;

  function default_block(lba: unsigned;
                         byte_count: positive := 512) return byte_string
  is
    -- However a caller numbered the bits of an address
    alias l: unsigned(lba'length - 1 downto 0) is lba;
    variable ret: byte_string(0 to byte_count - 1);
    variable seed: natural;
  begin
    for i in ret'range
    loop
      seed := (to_integer(l(15 downto 0)) * 2654
               + i * 131
               + i / 16 * 17
               + 11) mod 256;
      ret(i) := std_ulogic_vector(to_unsigned(seed, 8));
    end loop;

    return ret;
  end function;

  function card_register(content: std_ulogic_vector) return std_ulogic_vector
  is
    variable c: std_ulogic_vector(119 downto 0);
    variable crc: crc_state_t;
    variable ret: std_ulogic_vector(127 downto 0);
  begin
    c := content(content'left downto content'left - 119);
    crc := crc_update(nsl_sdio.link.cmd_crc_params_c,
                      crc_init(nsl_sdio.link.cmd_crc_params_c),
                      c);
    ret := c & crc_spill_vector(nsl_sdio.link.cmd_crc_params_c, crc) & '1';

    return ret;
  end function;

  function short_response(index: natural;
                          payload: std_ulogic_vector;
                          with_crc: boolean := true)
    return std_ulogic_vector
  is
    constant head_c: std_ulogic_vector(39 downto 0)
      := '0' & '0'
         & std_ulogic_vector(to_unsigned(index, 6))
         & std_ulogic_vector(resize(unsigned(payload), 32));
    constant crc_c: crc_state_t := crc_update(nsl_sdio.link.cmd_crc_params_c,
                                              crc_init(nsl_sdio.link.cmd_crc_params_c),
                                              head_c);
    variable ret: std_ulogic_vector(47 downto 0);
  begin
    if with_crc then
      ret := head_c & crc_spill_vector(nsl_sdio.link.cmd_crc_params_c, crc_c) & '1';
    else
      ret := head_c & "1111111" & '1';
    end if;

    return ret;
  end function;

  function long_response(content: std_ulogic_vector)
    return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(135 downto 0);
  begin
    ret := '0' & '0' & "111111"
           & content(content'left downto content'left - 127);

    return ret;
  end function;

  function csd_v2(block_count: natural;
                  high_speed: boolean := true) return std_ulogic_vector
  is
    variable content: std_ulogic_vector(127 downto 8) := (others => '0');
  begin
    -- Second version of the structure, the one that counts capacity
    -- rather than describing the array
    content(127 downto 126) := "01";
    -- Read access time, a millisecond, and no clocks on top of it
    content(119 downto 112) := x"0e";
    content(111 downto 104) := x"00";
    if high_speed then
      content(103 downto 96) := x"5a";
    else
      content(103 downto 96) := x"32";
    end if;
    -- Command classes: the basic, block read, block write and
    -- application specific ones
    content(95 downto 84) := x"5b5";
    -- Blocks of 512 bytes, whole ones only
    content(83 downto 80) := x"9";
    -- Capacity, in groups of 1024 blocks, minus one
    content(69 downto 48) := std_ulogic_vector(to_unsigned(block_count / 1024 - 1, 22));
    -- Erase happens one block at a time
    content(47) := '1';
    content(46 downto 39) := x"7f";
    -- Write takes four times as long as read, in blocks of 512 bytes
    content(28 downto 26) := "010";
    content(25 downto 22) := x"9";
    -- Contents may be copied, and nothing is write protected
    content(14) := '1';

    return card_register(content);
  end function;

end package body testing;
