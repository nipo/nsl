library ieee, nsl_data, nsl_logic, nsl_amba;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use nsl_data.bytestream.all;
use nsl_amba.axi4_stream.all;
use nsl_logic.logic.xor_reduce;
use nsl_data.crc.all;
use nsl_data.prbs.all;
use nsl_logic.bool.all;
use nsl_data.endian.all;
use ieee.std_logic_misc.all;
use nsl_amba.random_pkt_checker.all;

entity random_stats_asserter is
    generic (
      mtu_c: integer := 1500;
      config_c: config_t
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      --
      in_i : in master_t;
      in_o : out slave_t;
      --
      out_o : out master_t;
      out_i : in slave_t;
      -- 
      status_available : out std_ulogic
      );
  end entity;

architecture beh of random_stats_asserter is
    type status_t is (
        ST_PKT_OK,
        ST_PKT_KO
        );

    type state_t is (
        ST_RESET,
        ST_STATUS_DEC,
        ST_FORWARD_STATUS
        );

    constant stats_config_c : buffer_config_t := buffer_config(config_c, 8);

    type regs_t is
        record
            state : state_t;
            status : status_t;
            stats_buf : buffer_t;
            seq_num : unsigned(15 downto 0);
        end record;
        
        signal r, rin: regs_t;
begin

    regs: process(reset_n_i, clock_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;
      if reset_n_i = '0' then
        r.state <= ST_RESET;
        r.status <= ST_PKT_OK;
        r.stats_buf <= reset(stats_config_c);
        r.seq_num <= (others => '0');
      end if;
    end process;

    status_process: process(r, in_i)
        variable stats : stats_t;
    begin

        rin <= r;

        stats := stats_unpack(bytes(stats_config_c,r.stats_buf));

        case r.state is
            when ST_RESET =>
                rin.state <= ST_STATUS_DEC;

            when ST_STATUS_DEC =>
                if is_valid(config_c, in_i) then
                    rin.stats_buf <= shift(stats_config_c, r.stats_buf, in_i);
                    if is_last(stats_config_c, r.stats_buf) then
                        rin.state <= ST_FORWARD_STATUS;
                    end if;
                end if;

            when ST_FORWARD_STATUS => 
                if is_ready(config_c, out_i) then
                    rin.stats_buf <= shift(stats_config_c, r.stats_buf);
                    if is_last(stats_config_c, r.stats_buf) then
                        rin.seq_num <= r.seq_num + 1;
                        rin.state <= ST_STATUS_DEC;
                    end if;
                end if;
                

            when others => 


        end case;
    end process;

    in_o <= accept(config_c, r.state /= ST_FORWARD_STATUS);

    proc_txer: process(r)
        variable stats : stats_t;
    begin
        stats := stats_unpack(bytes(stats_config_c,r.stats_buf));
        status_available <= '0'; --to_logic(status_generator(stats));

        out_o <= transfer_defaults(config_c);

        case r.state is
            when ST_FORWARD_STATUS => 
                status_available <= to_logic(status_generator(stats));
                out_o <= transfer(config_c,
                                  src => next_beat(stats_config_c, r.stats_buf, last => false));
            when others =>
        end case;
    end process;
end architecture;
