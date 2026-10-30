library ieee;
use ieee.std_logic_1164.all;

-- Word alignment supervisor for a transceiver lane.
--
-- Keeps the transceiver's comma aligner enabled until the link partner
-- has delivered valid data for stabilization_count_c consecutive cycles,
-- then freezes alignment and reports ready. A restart request, or the
-- absence of valid data for lost_count_c cycles, re-arms the aligner.
--
-- When bypass_c is set (e.g. far-end PMA loopback, where the received
-- stream is not a comma-framed one) alignment is disabled permanently and
-- ready is always asserted.
entity lane_aligner is
  generic(
    bypass_c              : boolean := false;
    stabilization_count_c : natural := 300;
    flush_count_c         : natural := 64;
    lost_count_c          : natural := 2**16
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- Link partner data is currently valid
    valid_i   : in std_ulogic;
    -- Request to drop alignment and start over
    restart_i : in std_ulogic;

    -- Enable for the transceiver's comma alignment
    align_en_o : out std_ulogic;
    ready_o    : out std_ulogic
    );
end entity;

architecture beh of lane_aligner is

begin

  no_align : if bypass_c generate
    align_en_o <= '0';
    ready_o    <= '1';
  end generate;

  need_alignment : if not bypass_c generate

    type align_state_t is (ST_RESET, ST_FLUSH, ST_WAIT_VALID, ST_STABLE);

    type align_regs_t is record
      state       : align_state_t;
      count       : integer range 0 to stabilization_count_c - 1;
      lost_count  : integer range 0 to lost_count_c - 1;
      align_en    : std_ulogic;
      align_ready : std_ulogic;
    end record;

    signal r_align, rin_align : align_regs_t;

  begin

    align_en_o <= r_align.align_en;
    ready_o    <= r_align.align_ready;

    align_reg : process(reset_n_i, clock_i)
    begin
      if rising_edge(clock_i) then
        r_align <= rin_align;
      end if;

      if reset_n_i = '0' then
        r_align.state       <= ST_RESET;
        r_align.align_en    <= '1';
        r_align.align_ready <= '0';
      end if;
    end process;

    transition : process(r_align, restart_i, valid_i) is
    begin
      rin_align <= r_align;

      case r_align.state is
        when ST_RESET =>
          rin_align.align_en    <= '1';
          rin_align.align_ready <= '0';
          rin_align.count       <= flush_count_c - 1;  -- ignore valid while stale value drains
          rin_align.state       <= ST_FLUSH;

        when ST_FLUSH =>
          if r_align.count = 0 then
            rin_align.count <= stabilization_count_c - 1;
            rin_align.state <= ST_WAIT_VALID;
          else
            rin_align.count <= r_align.count - 1;
          end if;

        when ST_WAIT_VALID =>           -- needs N *consecutive* valid cycles
          if valid_i = '0' then
            rin_align.count <= stabilization_count_c - 1;
          elsif r_align.count = 0 then
            rin_align.align_en    <= '0';
            rin_align.align_ready <= '1';
            rin_align.lost_count  <= lost_count_c - 1;
            rin_align.state       <= ST_STABLE;
          else
            rin_align.count <= r_align.count - 1;
          end if;

        when ST_STABLE =>
          if restart_i = '1' then
            rin_align.state <= ST_RESET;
          elsif valid_i = '1' then
            rin_align.lost_count <= lost_count_c - 1;
          elsif r_align.lost_count = 0 then  -- self-heal: link gone, re-arm aligner
            rin_align.state <= ST_RESET;
          else
            rin_align.lost_count <= r_align.lost_count - 1;
          end if;
      end case;
    end process;

  end generate;

end architecture;
