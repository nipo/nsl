library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_inet.ethernet.all;

entity ethernet_transmitter is
  generic(
    l1_header_length_c : integer := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_address_i : in mac48_t;

    l3_type_i : in ethertype_t;
    l3_i : in nsl_bnoc.committed.committed_req;
    l3_o : out nsl_bnoc.committed.committed_ack;

    l1_o : out nsl_bnoc.committed.committed_req;
    l1_i : in nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of ethernet_transmitter is

  type state_t is (
    ST_RESET,
    ST_FILL,
    ST_FW_HEADER_DADDR,
    ST_TX_SADDR,
    ST_TX_TYPE,
    ST_FW_DATA,
    ST_TX_FAILED
    );

  type regs_t is
  record
    state : state_t;
    left : integer range 0 to 5 + l1_header_length_c;
    txbuf : byte_string(0 to 5);
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, l1_i, l3_i, local_address_i, l3_type_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_FILL;

      when ST_FILL =>
        if l3_i.valid = '1' and l3_i.last = '0' then
          rin.state <= ST_FW_HEADER_DADDR;
          rin.left <= 5 + l1_header_length_c;
          rin.txbuf(0) <= byte(l3_i.data);
        end if;
        
      when ST_FW_HEADER_DADDR =>
        if l3_i.valid = '1' and l1_i.ready = '1' then
          rin.txbuf(0) <= byte(l3_i.data);

          if l3_i.last = '1' then
            rin.state <= ST_TX_FAILED;
          elsif r.left /= 0 then
            rin.left <= r.left - 1;
          else
            rin.state <= ST_TX_SADDR;
            rin.left <= 5;
            if l3_i.data(0) = '1' then
              rin.txbuf(0 to 5) <= ethernet_broadcast_addr_c;
            else
              rin.txbuf(0 to 5) <= local_address_i;
            end if;
          end if;
        end if;

      when ST_TX_SADDR =>
        if l1_i.ready = '1' then
          if r.left /= 0 then
            rin.left <= r.left - 1;
            rin.txbuf(0 to rin.txbuf'right-1) <= r.txbuf(1 to r.txbuf'right);
          else
            rin.state <= ST_TX_TYPE;
            rin.txbuf(0 to 1) <= to_le(to_unsigned(l3_type_i, 16));
            rin.left <= 1;
          end if;
        end if;

      when ST_TX_TYPE =>
        if l1_i.ready = '1' then
          if r.left /= 0 then
            rin.left <= r.left - 1;
            rin.txbuf(0 to rin.txbuf'right-1) <= r.txbuf(1 to r.txbuf'right);
          else
            rin.state <= ST_FW_DATA;
          end if;
        end if;

      when ST_FW_DATA =>
        if l3_i.valid = '1' and l1_i.ready = '1' and l3_i.last = '1' then
          rin.state <= ST_RESET;
        end if;

      when ST_TX_FAILED =>
        if l1_i.ready = '1' then
          rin.state <= ST_RESET;
        end if;
    end case;
  end process;

  mealy: process(r, l1_i, l3_i) is
  begin
    l1_o.valid <= '0';
    l1_o.last <= '-';
    l1_o.data <= (others => '-');
    l3_o.ready <= '0';

    case r.state is
      when ST_RESET =>
        null;

      when ST_FILL =>
        l3_o.ready <= '1';

      when ST_FW_HEADER_DADDR =>
        l3_o <= l1_i;
        l1_o <= l3_i;
        l1_o.data <= r.txbuf(0);
        l1_o.last <= '0';

      when ST_TX_SADDR | ST_TX_TYPE =>
        l1_o.valid <= '1';
        l1_o.last <= '0';
        l1_o.data <= r.txbuf(0);

      when ST_FW_DATA =>
        l3_o <= l1_i;
        l1_o <= l3_i;

      when ST_TX_FAILED =>
        l1_o.valid <= '1';
        l1_o.last <= '1';
        l1_o.data <= x"00";
    end case;
  end process;

end architecture;
