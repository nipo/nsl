library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet, nsl_math;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_inet.ethernet.all;

entity ethernet_receiver is
  generic(
    ethertype_c : ethertype_vector;
    l1_header_length_c : integer := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_address_i : in mac48_t;

    l1_i : in nsl_bnoc.framed.framed_req;
    l1_o : out nsl_bnoc.framed.framed_ack;

    -- Valid at least on first word of frame on l3_o.
    l3_type_index_o : out integer range 0 to ethertype_c'length - 1;
    l3_o : out nsl_bnoc.framed.framed_req;
    l3_i : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of ethernet_receiver is

  type state_t is (
    ST_RESET,
    ST_RX_HEADER,
    ST_RX_DADDR,
    ST_RX_SADDR,
    ST_RX_TYPE,
    ST_DECIDE,
    ST_TX_HEADER,
    ST_TX_SADDR,
    ST_TX_CONTEXT,
    ST_FW_DATA,
    ST_TX_STATUS,
    ST_DROP
    );

  constant left_max: integer := nsl_math.arith.max(6, l1_header_length_c)-1;
  
  type regs_t is
  record
    state : state_t;
    local_addr, addr : mac48_t;
    left : integer range 0 to left_max;
    ethertype : integer range 0 to ethertype_c'length-1;
    type_len : byte_string(0 to 1);
    header : byte_string(0 to l1_header_length_c-1);
    addr_context : byte;
    rx_ok : std_ulogic;
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

  transition: process(r, l1_i, l3_i, local_address_i) is
  begin
    rin <= r;

    rin.local_addr <= local_address_i;

    case r.state is
      when ST_RESET =>
        if l1_header_length_c /= 0 then
          rin.state <= ST_RX_HEADER;
          rin.left <= l1_header_length_c-1;
        else
          rin.state <= ST_RX_DADDR;
          rin.left <= 5;
        end if;
        rin.rx_ok <= '1';

      when ST_RX_HEADER =>
        if l1_i.valid = '1' then
          rin.header <= r.header(1 to l1_header_length_c-1) & byte(l1_i.data);
          if l1_i.last = '1' then
            rin.state <= ST_RESET;
          elsif r.left = 0 then
            rin.state <= ST_RX_DADDR;
            rin.left <= 5;
          else
            rin.left <= r.left - 1;
          end if;
        end if;

      when ST_RX_DADDR =>
        if l1_i.valid = '1' then
          rin.addr <= r.addr(1 to 5) & byte(l1_i.data);
          if l1_i.last = '1' then
            rin.state <= ST_RESET;
          elsif r.left /= 0 then
            rin.left <= r.left - 1;
          else
            rin.left <= 5;
            rin.state <= ST_RX_SADDR;
          end if;
        end if;
        
      when ST_RX_SADDR =>
        if l1_i.valid = '1' then
          if r.left = 5 then
            -- First cycle of SADDR, r.addr contains full DADDR
            if r.addr = ethernet_broadcast_addr_c then
              rin.addr_context <= x"01";
            elsif r.addr = r.local_addr then
              rin.addr_context <= x"00";
            else
              rin.state <= ST_DROP;
            end if;
          end if;

          rin.addr <= r.addr(1 to 5) & byte(l1_i.data);
          if l1_i.last = '1' then
            rin.state <= ST_RESET;
          elsif r.left /= 0 then
            rin.left <= r.left - 1;
          else
            rin.left <= 1;
            rin.state <= ST_RX_TYPE;
          end if;
        end if;

      when ST_RX_TYPE =>
        if l1_i.valid = '1' then
          rin.type_len <= r.type_len(1 to 1) & byte(l1_i.data);
          if l1_i.last = '1' then
            rin.state <= ST_RESET;
          elsif r.left /= 0 then
            rin.left <= r.left - 1;
          else
            rin.state <= ST_DECIDE;
          end if;
        end if;

      when ST_DECIDE =>
        -- Default
        rin.state <= ST_DROP;

        for i in ethertype_c'range
        loop
          if to_unsigned(ethertype_c(i), 16) = from_le(r.type_len) then
            if l1_header_length_c /= 0 then
              rin.state <= ST_TX_HEADER;
            else
              rin.state <= ST_TX_SADDR;
              rin.left <= 5;
            end if;
            rin.ethertype <= i;
          end if;
        end loop;

      when ST_TX_HEADER =>
        if l3_i.ready = '1' then
          if r.left = 0 then
            rin.left <= 5;
            rin.state <= ST_TX_SADDR;
          else
            rin.left <= r.left - 1;
            rin.header <= r.header(1 to l1_header_length_c-1) & byte'("--------");
          end if;
        end if;

      when ST_TX_SADDR =>
        if l3_i.ready = '1' then
          if r.left = 0 then
            rin.state <= ST_TX_CONTEXT;
          else
            rin.left <= r.left - 1;
            rin.addr <= r.addr(1 to 5) & byte'("--------");
          end if;
        end if;
        
      when ST_TX_CONTEXT =>
        if l3_i.ready = '1' then
          rin.state <= ST_FW_DATA;
          rin.left <= 5;
        end if;

      when ST_FW_DATA =>
        if l3_i.ready = '1' and l1_i.valid = '1' and l1_i.last = '1' then
          rin.state <= ST_TX_STATUS;
        end if;

      when ST_TX_STATUS =>
        if l3_i.ready = '1' then
          rin.state <= ST_RESET;
        end if;

      when ST_DROP =>
        if l1_i.valid = '1' and l1_i.last = '1' then
          rin.state <= ST_RESET;
        end if;
    end case;
  end process;

  mealy: process(r, l1_i, l3_i) is
  begin
    l3_o.valid <= '0';
    l3_o.last <= '-';
    l3_o.data <= (others => '-');
    l1_o.ready <= '0';
    l3_type_index_o <= r.ethertype;

    case r.state is
      when ST_RESET | ST_DECIDE =>
        null;

      when ST_RX_HEADER | ST_RX_DADDR | ST_RX_SADDR | ST_RX_TYPE | ST_DROP =>
        l1_o.ready <= '1';

      when ST_TX_HEADER =>
        l3_o.valid <= '1';
        l3_o.last <= '0';
        l3_o.data <= r.header(0);

      when ST_TX_SADDR =>
        l3_o.valid <= '1';
        l3_o.last <= '0';
        l3_o.data <= r.addr(0);

      when ST_TX_CONTEXT =>
        l3_o.valid <= '1';
        l3_o.last <= '0';
        l3_o.data <= r.addr_context;

      when ST_FW_DATA =>
        l3_o <= l1_i;
        l1_o <= l3_i;

      when ST_TX_STATUS =>
        l3_o.valid <= '1';
        l3_o.last <= '1';
        l3_o.data <= "0000000" & r.rx_ok;
    end case;
  end process;

end architecture;
