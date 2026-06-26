library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_data;
use nsl_data.bytestream.all;
use nsl_jtag.continuous_transport.all;

-- Byte-to-bit transmit back-end for continuous_transport (TCK domain).
--
-- On each batch (capture) it emits, LSB-first, an optional alignment pad of
-- pad_i bits, then preamble_count_c preamble bytes, then the SOF, then payload
-- bytes pulled from the framer. byte_ready_o strobes when a payload byte is
-- latched, asking the framer for the next one; the framer must keep the next
-- byte to send on byte_i (it always has one -- idle at worst).
entity continuous_transport_serializer is
  generic(
    preamble_count_c : positive := preamble_min_c
    );
  port(
    clock_i   : in  std_ulogic;         -- TCK
    reset_n_i : in  std_ulogic;

    shift_i   : in  std_ulogic;         -- one bit exchanged when '1'
    capture_i : in  std_ulogic;         -- Capture-DR: batch start
    update_i  : in  std_ulogic;         -- Update-DR: batch end
    pad_i     : in  integer range 0 to 7;  -- active alignment pad

    tdo_o     : out std_ulogic;         -- outgoing bit (combinational)

    byte_i      : in  byte;  -- next payload byte
    byte_ready_o : out std_ulogic        -- payload byte latched, advance framer
    );
end entity;

architecture beh of continuous_transport_serializer is

  type state_t is (
    ST_IDLE,
    ST_PAD,
    ST_PRE,
    ST_PAY
    );

  type regs_t is
  record
    state      : state_t;
    pre_left : integer range 0 to preamble_count_c-1;
    shreg    : byte;
    bit_left : integer range 0 to 7;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_IDLE;
    end if;
  end process;

  transition: process(r, shift_i, capture_i, update_i, pad_i, byte_i)
  begin
    rin <= r;

    case r.state is
      when ST_IDLE =>
        null;

      when ST_PAD =>
        rin.shreg <= '-' & r.shreg(r.shreg'left downto 1);
        if r.bit_left = 0 then
          rin.state <= ST_PRE;
          rin.pre_left <= preamble_count_c - 1;
          rin.shreg <= preamble_byte_c;
          rin.bit_left <= 7;
        else
          rin.bit_left <= r.bit_left - 1;
        end if;

      when ST_PRE =>
        rin.shreg <= '-' & r.shreg(r.shreg'left downto 1);
        if r.bit_left = 0 then
          if r.pre_left /= 0 then
            rin.pre_left <= r.pre_left - 1;
            rin.shreg <= preamble_byte_c;
          else
            rin.state <= ST_PAY;
            rin.shreg <= sof_byte_c;
          end if;
          rin.bit_left <= 7;
        else
          rin.bit_left <= r.bit_left - 1;
        end if;

      when ST_PAY =>
        rin.shreg <= '-' & r.shreg(r.shreg'left downto 1);
        if r.bit_left = 0 then
          rin.shreg <= byte_i;
          rin.bit_left <= 7;
        else
          rin.bit_left <= r.bit_left - 1;
        end if;
    end case;

    if capture_i = '1' then
      rin.bit_left <= pad_i;
      rin.shreg <= (others => '0');
      rin.state <= ST_PAD;
    end if;

    if update_i = '1' then
      rin.state <= ST_IDLE;
    end if;
  end process;

  tdo_o <= r.shreg(0);
  byte_ready_o <= '1' when r.bit_left = 0 and r.state = ST_PAY else '0';

end architecture;
