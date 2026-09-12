library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_sdio;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;
use nsl_sdio.host.all;
use nsl_sdio.card.all;

entity card_initializer is
  generic(
    clock_i_hz_c: natural;
    lane_count_c: lane_count_t := 4;
    bus_init_hz_c: natural := 400000;
    power_up_us_c: natural := 5000;
    bus_run_hz_c: natural := 25000000
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    restart_i: in std_ulogic := '0';

    half_cycle_m1_o: out unsigned(15 downto 0);
    sample_phase_o: out unsigned(15 downto 0);
    width_o: out bus_width_t;

    info_o: out card_info_t;
    ready_o: out std_ulogic;

    req_i: in txn_req_t := txn_idle;
    req_o: out txn_ack_t;
    rsp_o: out txn_rsp_t;

    host_req_o: out txn_req_t;
    host_req_i: in txn_ack_t;
    host_rsp_i: in txn_rsp_t
    );
end entity;

architecture beh of card_initializer is

  constant init_half_cycle_c: natural
    := half_cycle_m1(clock_i_hz_c, bus_init_hz_c);
  constant init_phase_c: natural
    := default_sample_phase(clock_i_hz_c, init_half_cycle_c);
  constant run_half_cycle_c: natural
    := half_cycle_m1(clock_i_hz_c, bus_run_hz_c);
  constant run_phase_c: natural
    := default_sample_phase(clock_i_hz_c, run_half_cycle_c);

  -- A card wants its supply settled and a while of clock before it
  -- answers anything, and the same wait does for a retry.
  constant delay_cycle_c: natural := clock_i_hz_c / 1000000 * power_up_us_c;

  -- Times a card may answer that it is still powering up.  It is
  -- given a second, whatever the bus runs at.
  constant poll_max_c: natural := 1000;

  -- Voltage window a host fed at 3.3 V works with, and the bit that
  -- asks a card whether it addresses blocks rather than bytes.
  constant voltage_window_c: unsigned(31 downto 0) := x"00ff8000";
  constant high_capacity_c: unsigned(31 downto 0) := x"40000000";

  type step_t is (
    STEP_GO_IDLE,
    STEP_IF_COND,
    STEP_OP_COND_APP,
    STEP_OP_COND,
    STEP_ALL_CID,
    STEP_REL_ADDR,
    STEP_CSD,
    STEP_SELECT,
    STEP_BLOCK_LEN,
    STEP_WIDTH_APP,
    STEP_WIDTH
    );

  type state_t is (
    ST_DELAY,
    ST_ISSUE,
    ST_WAIT,
    ST_HANDLE,
    ST_READY
    );

  type regs_t is
  record
    state: state_t;
    step: step_t;
    delay: unsigned(31 downto 0);
    poll: natural range 0 to poll_max_c;
    -- Whether the card answered the command only a card that
    -- addresses blocks knows about
    high_capacity_asked: boolean;
    -- Whether the bus settings moved on from the ones identification
    -- runs with
    fast: boolean;
    info: card_info_t;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_DELAY;
      r.step <= STEP_GO_IDLE;
      r.delay <= to_unsigned(delay_cycle_c, 32);
      r.fast <= false;
      r.info <= card_info_none;
    end if;
  end process;

  transition: process(r, restart_i, host_req_i, host_rsp_i, req_i) is

    -- Puts the sequence back to the start, keeping nothing of what a
    -- card may have said before.
    procedure restart is
    begin
      rin.state <= ST_DELAY;
      rin.step <= STEP_GO_IDLE;
      rin.delay <= to_unsigned(delay_cycle_c, 32);
      rin.poll <= 0;
      rin.fast <= false;
      rin.info <= card_info_none;
    end procedure;

    procedure next_step(step: step_t) is
    begin
      rin.state <= ST_ISSUE;
      rin.step <= step;
    end procedure;

  begin
    rin <= r;

    case r.state is
      when ST_DELAY =>
        if r.delay = 0 then
          rin.state <= ST_ISSUE;
        else
          rin.delay <= r.delay - 1;
        end if;

      when ST_ISSUE =>
        if host_req_i.ready = '1' then
          rin.state <= ST_WAIT;
        end if;

      when ST_WAIT =>
        if host_rsp_i.valid = '1' then
          rin.state <= ST_HANDLE;
        end if;

      when ST_HANDLE =>
        -- Anything a card was supposed to answer and did not puts the
        -- whole sequence back to the start.  A card that is not there
        -- yet is then picked up whenever it does answer.
        if host_rsp_i.cmd_status /= CMD_OK
          and r.step /= STEP_GO_IDLE
          and r.step /= STEP_IF_COND
        then
          restart;
        else
          case r.step is
            when STEP_GO_IDLE =>
              next_step(STEP_IF_COND);

            when STEP_IF_COND =>
              -- A card that knows this command echoes what it was
              -- asked, and one that does not is a card from before
              -- block addressing existed.
              if host_rsp_i.cmd_status = CMD_TIMEOUT then
                rin.high_capacity_asked <= false;
                next_step(STEP_OP_COND_APP);
              elsif host_rsp_i.cmd_status /= CMD_OK
                or host_rsp_i.payload(7 downto 0) /= x"aa"
              then
                restart;
              else
                rin.high_capacity_asked <= true;
                next_step(STEP_OP_COND_APP);
              end if;

            when STEP_OP_COND_APP =>
              next_step(STEP_OP_COND);

            when STEP_OP_COND =>
              if host_rsp_i.payload(31) = '0' then
                if r.poll = poll_max_c then
                  restart;
                else
                  rin.poll <= r.poll + 1;
                  next_step(STEP_OP_COND_APP);
                end if;
              else
                if host_rsp_i.payload(30) = '1' then
                  rin.info.kind <= CARD_SDHC;
                  rin.info.block_addressed <= true;
                else
                  rin.info.kind <= CARD_SD;
                  rin.info.block_addressed <= false;
                end if;

                next_step(STEP_ALL_CID);
              end if;

            when STEP_ALL_CID =>
              rin.info.cid <= host_rsp_i.payload;
              next_step(STEP_REL_ADDR);

            when STEP_REL_ADDR =>
              rin.info.rca <= unsigned(host_rsp_i.payload(31 downto 16));
              next_step(STEP_CSD);

            when STEP_CSD =>
              rin.info.csd <= host_rsp_i.payload;
              rin.info.block_count <= csd_block_count(host_rsp_i.payload);
              next_step(STEP_SELECT);

            when STEP_SELECT =>
              -- A selected card is done being identified, so the bus
              -- has no reason to crawl any more.
              rin.fast <= true;
              next_step(STEP_BLOCK_LEN);

            when STEP_BLOCK_LEN =>
              if lane_count_c >= 4 then
                next_step(STEP_WIDTH_APP);
              else
                rin.state <= ST_READY;
              end if;

            when STEP_WIDTH_APP =>
              next_step(STEP_WIDTH);

            when STEP_WIDTH =>
              rin.info.width <= SDIO_WIDTH_4;
              rin.state <= ST_READY;
          end case;
        end if;

      when ST_READY =>
        null;
    end case;

    if restart_i = '1' then
      restart;
    end if;
  end process;

  moore: process(r) is
  begin
    info_o <= r.info;
    width_o <= r.info.width;

    if r.fast then
      half_cycle_m1_o <= to_unsigned(run_half_cycle_c, 16);
      sample_phase_o <= to_unsigned(run_phase_c, 16);
    else
      half_cycle_m1_o <= to_unsigned(init_half_cycle_c, 16);
      sample_phase_o <= to_unsigned(init_phase_c, 16);
    end if;

    case r.state is
      when ST_READY =>
        ready_o <= '1';

      when others =>
        ready_o <= '0';
    end case;
  end process;

  -- Requests of its own until a card is ready, then out of the way.
  mealy: process(r, req_i, host_req_i, host_rsp_i) is
    variable own: txn_req_t;
  begin
    case r.step is
      when STEP_GO_IDLE =>
        own := txn_command(0, x"00000000", RESP_NONE);

      when STEP_IF_COND =>
        -- Voltage the host feeds, and a pattern the card sends back
        own := txn_command(8, x"000001aa", RESP_SHORT);

      when STEP_OP_COND_APP =>
        own := txn_command(55, x"00000000", RESP_SHORT);

      when STEP_OP_COND =>
        -- The answer to this one has ones where a checksum would be
        if r.high_capacity_asked then
          own := txn_command(41, voltage_window_c or high_capacity_c,
                             RESP_SHORT, false);
        else
          own := txn_command(41, voltage_window_c, RESP_SHORT, false);
        end if;

      when STEP_ALL_CID =>
        own := txn_command(2, x"00000000", RESP_LONG);

      when STEP_REL_ADDR =>
        own := txn_command(3, x"00000000", RESP_SHORT);

      when STEP_CSD =>
        own := txn_command(9, r.info.rca & x"0000", RESP_LONG);

      when STEP_SELECT =>
        own := txn_command(7, r.info.rca & x"0000", RESP_SHORT_BUSY);

      when STEP_BLOCK_LEN =>
        own := txn_command(16, x"00000200", RESP_SHORT);

      when STEP_WIDTH_APP =>
        own := txn_command(55, r.info.rca & x"0000", RESP_SHORT);

      when STEP_WIDTH =>
        -- Four data lines
        own := txn_command(6, x"00000002", RESP_SHORT);
    end case;

    case r.state is
      when ST_READY =>
        host_req_o <= req_i;
        req_o <= host_req_i;
        rsp_o <= host_rsp_i;

      when ST_ISSUE =>
        host_req_o <= own;
        req_o <= accept(false);
        rsp_o <= host_rsp_i;
        rsp_o.cmd_valid <= '0';
        rsp_o.valid <= '0';

      when others =>
        host_req_o <= txn_idle;
        req_o <= accept(false);
        rsp_o <= host_rsp_i;
        rsp_o.cmd_valid <= '0';
        rsp_o.valid <= '0';
    end case;
  end process;

end architecture;
