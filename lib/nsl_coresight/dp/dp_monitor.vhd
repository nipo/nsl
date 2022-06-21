library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swd.all;
use work.dp.all;

entity dp_monitor is
  port(
    reset_n_i: in std_ulogic := '1';

    dp_i : in work.swd.swd_slave_i;

    tech_o: out dp_tech_t;
    state_o: out dp_state_t
    );
end entity;

architecture beh of dp_monitor is

  constant ds_act_c : std_ulogic_vector(0 to 0) := (others => '0');
  constant swd_act_c : std_ulogic_vector(0 to 1) := (others => '0');
  constant jtag_act_c : std_ulogic_vector(0 to 0) := (others => '0');
  constant swd_to_jtag_c : std_ulogic_vector := "0011110011100111";
  constant swd_to_ds_c   : std_ulogic_vector := "0011110111000111";

  constant jtag_to_swd_c : std_ulogic_vector := "0111100111100111";
  constant jtag_to_ds_c  : std_ulogic_vector := "0101110111011101110111011100110";

  constant ds_alert0_c : std_ulogic_vector := x"49CF9046";
  constant ds_alert1_c : std_ulogic_vector := x"A9B4A161";
  constant ds_alert2_c : std_ulogic_vector := x"97F5BBC7";
  constant ds_alert3_c : std_ulogic_vector := x"45703D98";
  constant ds_jtag_serial_c : std_ulogic_vector := "0000000000000000";
  constant ds_arm_sw_dp_c : std_ulogic_vector := "000001011000";
  constant ds_arm_jtag_dp_c : std_ulogic_vector := "000001010000";

  type regs_t is
  record
    backlog: std_ulogic_vector(31 downto 0);
    tech: dp_tech_t;
    state: dp_state_t;
    post_reset: boolean;
    count: unsigned(4 downto 0);
    subseq_no: integer range 0 to 3;
    one50_run: integer range 0 to 49;
    one8_run: integer range 0 to 7;
    one4_run: integer range 0 to 3;
  end record;

  function backlog_matches(r: regs_t;
                           pattern: std_ulogic_vector;
                           aligned: boolean := false) return boolean
  is
    alias ap: std_ulogic_vector(pattern'length-1 downto 0) is pattern;
  begin
    if ap'length > r.backlog'length then
      return false;
    end if;

    if aligned and r.count /= pattern'length then
      return false;
    end if;

    return r.backlog(ap'range) = ap;
  end function;

  signal r, rin: regs_t;
  
begin

  regs: process(dp_i.clk, reset_n_i) is
  begin
    if rising_edge(dp_i.clk) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.tech <= DP_TECH_SWD;
      r.backlog <= (others => '0');
      r.state <= DP_UNSYNC;
      r.one50_run <= 49;
      r.one8_run <= 7;
      r.one4_run <= 3;
    end if;
  end process;

  transition: process(dp_i.dio, r) is
    variable dio : std_ulogic;
    variable count_reset: boolean;
  begin
    rin <= r;

    dio := to_x01(dp_i.dio);
    count_reset := false;

    if r.one50_run /= 0 then
      rin.one50_run <= r.one50_run - 1;
    end if;

    if r.one4_run /= 0 then
      rin.one4_run <= r.one4_run - 1;
    end if;

    if r.one8_run /= 0 then
      rin.one8_run <= r.one8_run - 1;
    end if;

    if dio = '0' then
      rin.one50_run <= 49;
      rin.one8_run <= 7;
      rin.one4_run <= 3;
    end if;

    rin.backlog <= r.backlog(r.backlog'left-1 downto 0) & dio;
    rin.count <= r.count + 1;

    case r.tech is
      when DP_TECH_SWD =>
        if r.one50_run = 0 and dio = '1' then
          rin.state <= DP_RESET;
          rin.post_reset <= false;
          count_reset := true;
        end if;

        if r.state = DP_RESET then
          if dio = '0' then
            rin.post_reset <= true;
            rin.state <= DP_ACTIVE;
          end if;
        end if;
        
        if r.state = DP_ACTIVE and r.post_reset then
          if r.count = 16 then
            rin.post_reset <= false;

            if backlog_matches(r, swd_to_jtag_c) then
              rin.state <= DP_UNSYNC;
              rin.tech <= DP_TECH_JTAG;
            end if;

            if backlog_matches(r, swd_to_ds_c) then
              rin.state <= DP_UNSYNC;
              rin.tech <= DP_TECH_DORMANT;
            end if;
          end if;
        end if;
        
      when DP_TECH_JTAG | DP_TECH_JTAG_SERIAL =>
        if r.one50_run = 0 and dio = '1' then
          rin.state <= DP_RESET;
          rin.post_reset <= false;
          count_reset := true;
        end if;

        if r.state = DP_RESET then
          if dio = '0' then
            rin.post_reset <= true;
            rin.state <= DP_ACTIVE;
          end if;
        end if;
        
        if r.state = DP_ACTIVE and r.post_reset then
          if r.count = 16 then
            if backlog_matches(r, jtag_to_swd_c) and r.tech = DP_TECH_JTAG then
              rin.state <= DP_UNSYNC;
              rin.tech <= DP_TECH_SWD;
            end if;
          elsif r.count = 31 then
            rin.post_reset <= false;
            if backlog_matches(r, jtag_to_ds_c) then
              rin.state <= DP_UNSYNC;
              rin.tech <= DP_TECH_DORMANT;
            end if;
          end if;
        end if;

      when DP_TECH_DORMANT =>
        if r.one8_run = 0 and dio = '1' then
          rin.state <= DP_RESET;
          count_reset := true;
          rin.post_reset <= false;
          rin.subseq_no <= 0;
        end if;

        if r.state = DP_RESET then
          if dio = '0' then
            rin.post_reset <= true;
            rin.state <= DP_ACTIVE;
          end if;
        end if;
        
        if r.state = DP_ACTIVE then
          if r.post_reset then
            if r.count = 0 then
              rin.post_reset <= false;
              rin.state <= DP_UNSYNC;

              case r.subseq_no is
                when 0 =>
                  if backlog_matches(r, ds_alert0_c) then
                    rin.subseq_no <= 1;
                    rin.post_reset <= true;
                    rin.state <= DP_ACTIVE;
                  end if;

                when 1 =>
                  if backlog_matches(r, ds_alert1_c) then
                    rin.subseq_no <= 2;
                    rin.post_reset <= true;
                    rin.state <= DP_ACTIVE;
                  end if;

                when 2 =>
                  if backlog_matches(r, ds_alert2_c) then
                    rin.subseq_no <= 3;
                    rin.post_reset <= true;
                    rin.state <= DP_ACTIVE;
                  end if;

                when 3 =>
                  if backlog_matches(r, ds_alert3_c) then
                    rin.state <= DP_ACTIVE;
                    rin.post_reset <= false;
                  end if;
              end case;
            end if;
          else
            if r.count >= 16 then
              rin.state <= DP_UNSYNC;
            end if;

            if backlog_matches(r, ds_jtag_serial_c, true) then
              rin.tech <= DP_TECH_JTAG_SERIAL;
              rin.state <= DP_UNSYNC;
            end if;

            if backlog_matches(r, ds_arm_jtag_dp_c, true) then
              rin.tech <= DP_TECH_JTAG;
              rin.state <= DP_UNSYNC;
            end if;

            if backlog_matches(r, ds_arm_sw_dp_c, true) then
              rin.tech <= DP_TECH_SWD;
              rin.state <= DP_UNSYNC;
            end if;
          end if;
        end if;
    end case;

    if count_reset then
      rin.count <= to_unsigned(0, rin.count'length);
    end if;
  end process;

  tech_o <= r.tech;
  state_o <= r.state;

end architecture;
