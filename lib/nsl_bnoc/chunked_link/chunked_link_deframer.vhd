library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;
use nsl_bnoc.chunked_link.all;

-- Receive deframer for chunked_link, usable on either end of the link.
--
-- Consumes the byte-aligned frame stream recovered by the transport and
-- decodes it:
--   * data frames     -> data bytes pushed out with last on the frame's end
--   * credit frames   -> credit_o strobe (absolute value)
--   * tx-level frames -> level_o strobe (absolute value)
--   * set-pad frames  -> pad_o strobe
--   * idle/reserved   -> ignored
-- Each end wires only the strobes meaningful for its direction and leaves
-- the others open; operand bytes of every known opcode are consumed either
-- way so framing never depends on the direction.
--
-- Flow control (credit) is assumed honoured by the sender, so the data sink
-- is expected to always accept; there is no back-pressure path.
entity chunked_link_deframer is
  port(
    clock_i   : in  std_ulogic;
    reset_n_i : in  std_ulogic;

    -- Byte-aligned frame stream from the transport.
    byte_i       : in  byte;
    byte_valid_i : in  std_ulogic;

    -- Recovered payload.
    rx_data_o  : out byte;
    rx_last_o  : out std_ulogic;
    rx_valid_o : out std_ulogic;

    -- Decoded control, each a one-cycle strobe with its value.
    credit_o     : out unsigned(credit_bits_c-1 downto 0);
    credit_set_o : out std_ulogic;
    level_o      : out unsigned(credit_bits_c-1 downto 0);
    level_set_o  : out std_ulogic;
    pad_o        : out std_ulogic_vector(2 downto 0);
    pad_set_o    : out std_ulogic
    );
end entity;

architecture beh of chunked_link_deframer is

  type state_t is (
    ST_HEADER,
    ST_DATA,
    ST_CREDIT_LSB,
    ST_CREDIT_MSB,
    ST_LEVEL_LSB,
    ST_LEVEL_MSB
    );

  type regs_t is
  record
    state     : state_t;
    data_left : integer range 0 to data_bytes_max_c-1;
    last      : std_ulogic;
    lsb       : byte;

    rx_data    : byte;
    rx_last    : std_ulogic;
    rx_valid   : std_ulogic;
    credit     : unsigned(credit_bits_c-1 downto 0);
    credit_set : std_ulogic;
    level      : unsigned(credit_bits_c-1 downto 0);
    level_set  : std_ulogic;
    pad        : std_ulogic_vector(2 downto 0);
    pad_set    : std_ulogic;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_HEADER;
      r.data_left <= 0;
      r.rx_valid <= '0';
      r.credit_set <= '0';
      r.level_set <= '0';
      r.pad_set <= '0';
    end if;
  end process;

  transition: process(r, byte_i, byte_valid_i)
  begin
    rin <= r;
    rin.rx_valid <= '0';
    rin.credit_set <= '0';
    rin.level_set <= '0';
    rin.pad_set <= '0';

    if byte_valid_i = '1' then
      case r.state is
        when ST_HEADER =>
          if std_match(byte_i, data_header_mask_c) then
            -- Data frame: bit 6 = last, bits 5..0 = length - 1.
            rin.last <= byte_i(hdr_last_bit_c);
            rin.data_left <= to_integer(unsigned(byte_i(5 downto 0)));
            rin.state <= ST_DATA;
          elsif std_match(byte_i, ctl_set_pad_base_c) then
            rin.pad <= byte_i(2 downto 0);
            rin.pad_set <= '1';
          elsif byte_i = ctl_credit_c then
            rin.state <= ST_CREDIT_LSB;
          elsif byte_i = ctl_tx_level_c then
            rin.state <= ST_LEVEL_LSB;
          else
            -- idle or reserved: ignore.
            null;
          end if;

        when ST_DATA =>
          rin.rx_data <= byte_i;
          rin.rx_valid <= '1';
          if r.data_left = 0 then
            rin.rx_last <= r.last;
            rin.state <= ST_HEADER;
          else
            rin.rx_last <= '0';
            rin.data_left <= r.data_left - 1;
          end if;

        when ST_CREDIT_LSB =>
          rin.lsb <= byte_i;
          rin.state <= ST_CREDIT_MSB;

        when ST_CREDIT_MSB =>
          rin.credit <= unsigned(byte_i) & unsigned(r.lsb);
          rin.credit_set <= '1';
          rin.state <= ST_HEADER;

        when ST_LEVEL_LSB =>
          rin.lsb <= byte_i;
          rin.state <= ST_LEVEL_MSB;

        when ST_LEVEL_MSB =>
          rin.level <= unsigned(byte_i) & unsigned(r.lsb);
          rin.level_set <= '1';
          rin.state <= ST_HEADER;
      end case;
    end if;
  end process;

  rx_data_o <= r.rx_data;
  rx_last_o <= r.rx_last;
  rx_valid_o <= r.rx_valid;
  credit_o <= r.credit;
  credit_set_o <= r.credit_set;
  level_o <= r.level;
  level_set_o <= r.level_set;
  pad_o <= r.pad;
  pad_set_o <= r.pad_set;

end architecture;
