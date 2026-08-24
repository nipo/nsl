library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_math, nsl_logic, work;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;
use work.mac.all;
use work.vlan.all;

entity vlan_mux is
  generic(
    header_length_c : integer := 0;
    vlan_id_c : vlan_id_vector
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    untagged_i : in nsl_bnoc.committed.committed_req;
    untagged_o : out nsl_bnoc.committed.committed_ack;

    tagged_i : in nsl_bnoc.committed.committed_req_array(0 to vlan_id_c'length-1);
    tagged_o : out nsl_bnoc.committed.committed_ack_array(0 to vlan_id_c'length-1);

    out_o : out nsl_bnoc.committed.committed_req;
    out_i : in nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of vlan_mux is

  alias vlan_id_l_c : vlan_id_vector(0 to vlan_id_c'length-1) is vlan_id_c;

  -- Source 0 is the untagged pipe, i+1 maps to vlan_id_l_c(i)
  constant source_count_c : integer := vlan_id_c'length + 1;

  type state_t is (
    ST_RESET,
    ST_HEADER,
    ST_ADDR,
    ST_TAG,
    ST_DATA
    );

  type regs_t is
  record
    state : state_t;
    ctr : integer range 0 to nsl_math.arith.max(11, header_length_c-1);
    tag : byte_string(0 to 3);
    tagged : boolean;
  end record;

  signal r, rin: regs_t;

  signal funnel_req_s : committed_req_array(0 to source_count_c-1);
  signal funnel_ack_s : committed_ack_array(0 to source_count_c-1);
  signal selected_s : integer range 0 to source_count_c - 1;
  signal merged_s : nsl_bnoc.committed.committed_bus;

begin

  funnel_req_s(0) <= untagged_i;
  untagged_o <= funnel_ack_s(0);

  tagged_map: for i in 0 to vlan_id_c'length-1
  generate
    funnel_req_s(i+1) <= tagged_i(i);
    tagged_o(i) <= funnel_ack_s(i+1);
  end generate;

  funnel: nsl_bnoc.committed.committed_funnel
    generic map(
      source_count_c => source_count_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      selected_o => selected_s,

      in_i => funnel_req_s,
      in_o => funnel_ack_s,

      out_o => merged_s.req,
      out_i => merged_s.ack
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, merged_s.req, out_i, selected_s) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        if merged_s.req.valid = '1' then
          rin.tagged <= selected_s /= 0;
          if selected_s /= 0 then
            rin.tag <= to_be(to_unsigned(ethertype_vlan, 16))
                       & to_be(to_unsigned(vlan_id_l_c(selected_s-1), 16));
          end if;
          if header_length_c /= 0 then
            rin.state <= ST_HEADER;
            rin.ctr <= header_length_c - 1;
          else
            rin.state <= ST_ADDR;
            rin.ctr <= 11;
          end if;
        end if;

      when ST_HEADER =>
        if merged_s.req.valid = '1' and out_i.ready = '1' then
          if merged_s.req.last = '1' then
            rin.state <= ST_RESET;
          elsif r.ctr = 0 then
            rin.state <= ST_ADDR;
            rin.ctr <= 11;
          else
            rin.ctr <= r.ctr - 1;
          end if;
        end if;

      when ST_ADDR =>
        if merged_s.req.valid = '1' and out_i.ready = '1' then
          if merged_s.req.last = '1' then
            rin.state <= ST_RESET;
          elsif r.ctr = 0 then
            if r.tagged then
              rin.state <= ST_TAG;
              rin.ctr <= 3;
            else
              rin.state <= ST_DATA;
            end if;
          else
            rin.ctr <= r.ctr - 1;
          end if;
        end if;

      when ST_TAG =>
        if out_i.ready = '1' then
          rin.tag <= shift_left(r.tag);
          if r.ctr = 0 then
            rin.state <= ST_DATA;
          else
            rin.ctr <= r.ctr - 1;
          end if;
        end if;

      when ST_DATA =>
        if merged_s.req.valid = '1' and out_i.ready = '1'
          and merged_s.req.last = '1' then
          rin.state <= ST_RESET;
        end if;
    end case;
  end process;

  mealy: process(r, merged_s.req, out_i) is
  begin
    out_o.valid <= '0';
    out_o.last <= '-';
    out_o.data <= (others => '-');
    merged_s.ack.ready <= '0';

    case r.state is
      when ST_RESET =>
        null;

      when ST_HEADER | ST_ADDR | ST_DATA =>
        out_o <= merged_s.req;
        merged_s.ack.ready <= out_i.ready;

      when ST_TAG =>
        out_o.valid <= '1';
        out_o.last <= '0';
        out_o.data <= r.tag(0);
    end case;
  end process;

end architecture;
