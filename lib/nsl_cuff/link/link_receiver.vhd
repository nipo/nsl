library ieee;
use ieee.std_logic_1164.all;

library nsl_cuff, nsl_line_coding, nsl_logic, nsl_data;
use nsl_line_coding.ibm_8b10b.all;
use nsl_cuff.protocol.all;
use nsl_logic.logic.all;
use nsl_data.bytestream.all;
use nsl_cuff.lane.all;
use nsl_cuff.link.all;

entity link_receiver is
  generic(
    lane_count_c : natural;
    mtu_l2_c : natural range 0 to 15;
    ibm_8b10b_implementation_c : string := "logic"
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- From/to transceiver
    lane_i : in cuff_code_vector(0 to lane_count_c-1);
    align_restart_o : out std_ulogic;
    align_valid_o : out std_ulogic_vector(0 to lane_count_c-1);
    align_ready_i : in std_ulogic_vector(0 to lane_count_c-1);

    data_o : out cuff_data_vector(0 to lane_count_c-1);

    state_o: out link_state_t
    );
end entity;

architecture beh of link_receiver is

  type state_vector is array(0 to lane_count_c-1) of lane_state_t;
  signal state_s: state_vector;
  signal lane_restart_s, sync_sof_s, sync_eof_s: std_ulogic_vector(0 to lane_count_c-1);
  signal data_s: cuff_data_vector(0 to lane_count_c-1);

begin

  multi_lane: if lane_count_c > 1
  generate

    constant pipe_count_c: natural := 2;

    type lane_cycle_t is
    record
      data: cuff_data_t;
      sof, eof: boolean;
    end record;

    type lane_cycle_vector_t is array (natural range <>) of lane_cycle_t;

    type lane_data_t is
    record
      pipe: lane_cycle_vector_t(0 to pipe_count_c-1);
      head_index: natural range 0 to pipe_count_c-1;
      head: lane_cycle_t;
      state: lane_state_t;
    end record;

    type lane_vector_t is array (natural range <>) of lane_data_t;

    type regs_t is
    record
      state: link_state_t;
      restart: std_ulogic;
      lane: lane_vector_t(0 to lane_count_c-1);
      timeout: integer range 0 to 31;
    end record;

    signal r, rin: regs_t;

  begin

    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.restart <= '1';
      end if;
    end process;

    transition: process(r, data_s, lane_restart_s, state_s, sync_eof_s, sync_sof_s) is
      variable all_same_state, all_ready, all_aligned,
        all_sof, all_eof, any_other_sof: boolean;
    begin
      rin <= r;

      rin.restart <= or_reduce(lane_restart_s);

      all_sof := true;
      all_eof := true;
      any_other_sof := true;
      all_ready := true;
      all_same_state := true;

      for i in 0 to lane_count_c - 1
      loop
        rin.lane(i).pipe(0 to pipe_count_c-2) <= r.lane(i).pipe(1 to pipe_count_c-1);
        rin.lane(i).pipe(pipe_count_c-1).data <= data_s(i);
        rin.lane(i).pipe(pipe_count_c-1).sof <= sync_sof_s(i) = '1';
        rin.lane(i).pipe(pipe_count_c-1).eof <= sync_eof_s(i) = '1';
        rin.lane(i).state <= state_s(i);

        rin.lane(i).head <= r.lane(i).pipe(r.lane(i).head_index);
        all_sof := all_sof and r.lane(i).head.sof;
      end loop;

      all_ready := (r.lane(0).state /= LANE_BIT_ALIGN
                    and r.lane(0).state /= LANE_BIT_ALIGN);
      for i in 1 to lane_count_c - 1
      loop
        all_same_state := all_same_state and (r.lane(i).state = r.lane(0).state);
        any_other_sof := any_other_sof and r.lane(i).head.sof;
        all_ready := all_ready and (r.lane(i).state /= LANE_BIT_ALIGN);
      end loop;

      case r.state is
        when LINK_LANE_ALIGN =>
          if all_same_state and r.lane(0).state = LANE_BUS_ALIGN then
            rin.state <= LINK_BUS_ALIGN;
            rin.timeout <= 31;
          end if;

        when LINK_BUS_ALIGN =>
          if all_same_state then
            if all_sof then
              rin.state <= LINK_READY;
            elsif r.lane(0).head.sof then
              for i in 1 to lane_count_c-1
              loop
                if r.lane(i).head.eof then
                  rin.lane(i).head_index <= r.lane(i).head_index + 1;
                end if;
              end loop;
            elsif r.lane(0).head.eof and any_other_sof then
              for i in 1 to lane_count_c-1
              loop
                rin.lane(i).head_index <= r.lane(i).head_index + 1;
              end loop;
            end if;
          end if;

          if r.timeout = 0 then
            rin.restart <= '1';
          else
            rin.timeout <= r.timeout - 1;
          end if;

        when LINK_READY =>
          if all_ready then
            rin.state <= LINK_STARTUP;
          end if;

        when LINK_STARTUP =>
          rin.state <= LINK_RUNNING;

        when LINK_RUNNING =>
          if not all_ready then
            rin.restart <= '1';
          end if;
      end case;

      if r.restart = '1' then
        rin.state <= LINK_LANE_ALIGN;
        for i in 0 to lane_count_c - 1
        loop
          rin.lane(i).head_index <= 0;
        end loop;
      end if;
    end process;

    moore: process(r) is
    begin
      align_restart_o <= r.restart;
      state_o <= r.state;
      case r.state is
        when LINK_RUNNING =>
          for i in data_o'range
          loop
            data_o(i) <= r.lane(i).head.data;
          end loop;
        when others =>
          data_o <= (others => cuff_data_idle_c);
      end case;
    end process;
  end generate;

  one_lane: if lane_count_c = 1
  generate

    type regs_t is
    record
      state: link_state_t;
    end record;

    signal r, rin: regs_t;

  begin

    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;
    end process;

    transition: process(r, state_s, lane_restart_s) is
    begin
      rin <= r;

      if lane_restart_s(0) = '1' then
        rin.state <= LINK_LANE_ALIGN;
      else
        case r.state is
          when LINK_LANE_ALIGN =>
            if state_s(0) = LANE_BUS_ALIGN then
              rin.state <= LINK_BUS_ALIGN;
            end if;

          when LINK_BUS_ALIGN =>
            if state_s(0) = LANE_BUS_ALIGN then
              rin.state <= LINK_READY;
            end if;

          when LINK_READY =>
            if state_s(0) = LANE_BUS_ALIGN_READY then
              rin.state <= LINK_STARTUP;
            end if;

          when LINK_STARTUP =>
            rin.state <= LINK_RUNNING;

          when LINK_RUNNING =>
            null;
        end case;
      end if;
    end process;

    data_o(0) <= data_s(0);

    align_restart_o <= lane_restart_s(0);

    state_o <= r.state;
  end generate;

  lanes: for i in 0 to lane_count_c-1
  generate
    lane: nsl_cuff.lane.lane_receiver
      generic map(
        lane_count_c => lane_count_c,
        lane_index_c => i,
        mtu_l2_c => mtu_l2_c,
        ibm_8b10b_implementation_c => ibm_8b10b_implementation_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        lane_i => lane_i(i),
        data_o => data_s(i),

        align_restart_o => lane_restart_s(i),
        align_valid_o => align_valid_o(i),
        align_ready_i => align_ready_i(i),

        sync_sof_o => sync_sof_s(i),
        sync_eof_o => sync_eof_s(i),

        state_o => state_s(i)
        );
  end generate;

end architecture;
