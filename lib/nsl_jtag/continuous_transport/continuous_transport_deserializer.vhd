library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_data;
use nsl_data.bytestream.all;
use nsl_jtag.continuous_transport.all;

-- Bit-to-byte receive front-end for continuous_transport (TCK domain).
--
-- Consumes one TDI bit per asserted shift. While unlocked it searches the
-- incoming bitstream for the preamble->SOF transition; once locked it counts
-- 8 shifts per byte and emits framed bytes. capture (batch start) drops the
-- lock so each batch re-acquires from its own SOF.
entity continuous_transport_deserializer is
  port(
    clock_i   : in  std_ulogic;         -- TCK
    reset_n_i : in  std_ulogic;

    shift_i   : in  std_ulogic;         -- one bit exchanged when '1'
    capture_i : in  std_ulogic;         -- Capture-DR: batch start
    tdi_i     : in  std_ulogic;         -- incoming bit

    locked_o     : out std_ulogic;      -- SOF acquired for this batch
    byte_o       : out byte;
    byte_valid_o : out std_ulogic       -- one-cycle strobe per framed byte
    );
end entity;

architecture beh of continuous_transport_deserializer is

  -- The 16-bit window holds [preamble byte][SOF byte] once aligned. JTAG is
  -- LSB-first and new bits enter at bit 15, so the most recent 8 bits (15..8)
  -- read back as the SOF byte and the previous 8 (7..0) as the preamble byte.
  constant sync_match_c : std_ulogic_vector(15 downto 0) := sof_byte_c & preamble_byte_c;

  type regs_t is
  record
    shreg      : std_ulogic_vector(15 downto 0);
    locked     : std_ulogic;
    bitcnt     : integer range 0 to 7;
    byte       : byte;
    byte_valid : std_ulogic;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.shreg <= (others => '0');
      r.locked <= '0';
      r.bitcnt <= 0;
      r.byte_valid <= '0';
    end if;
  end process;

  transition: process(r, shift_i, capture_i, tdi_i)
  begin
    rin <= r;
    rin.byte_valid <= '0';

    if shift_i = '1' then
      rin.shreg <= tdi_i & r.shreg(15 downto 1);

      if r.locked = '0' then
        if r.shreg = sync_match_c then
          rin.locked <= '1';
          rin.bitcnt <= 7;
        end if;
      else
        if r.bitcnt = 0 then
          rin.bitcnt <= 7;
          rin.byte <= r.shreg(15 downto 8);
          rin.byte_valid <= '1';
        else
          rin.bitcnt <= r.bitcnt - 1;
        end if;
      end if;
    end if;

    -- Batch boundary: drop framing, re-acquire from the new batch's SOF.
    if capture_i = '1' then
      rin.locked <= '0';
      rin.bitcnt <= 0;
    end if;
  end process;

  locked_o <= r.locked;
  byte_o <= r.byte;
  byte_valid_o <= r.byte_valid;

end architecture;
