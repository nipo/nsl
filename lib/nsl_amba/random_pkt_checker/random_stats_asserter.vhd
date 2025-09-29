    library ieee, nsl_data, nsl_logic, nsl_amba, nsl_math;
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
        config_c: config_t
        );
        port (
        clock_i : in std_ulogic;
        reset_n_i : in std_ulogic;
        --
        in_i : in master_t;
        in_o : out slave_t;
        --
        toggle_i : in std_ulogic;
        --
        feedback_i : in error_feedback_t;
        assert_error_o : out std_ulogic
        );
    end entity;

    architecture beh of random_stats_asserter is
        type state_t is (
            ST_RESET,
            ST_STATUS_DEC,
            ST_ASSERT,
            ST_ASSERT_ERROR
            );

        type unsigned_array_t is array (natural range <>) of unsigned(15 downto 0);

        constant stats_config_c : buffer_config_t := buffer_config(config_c, STATS_SIZE);
        constant nbr_of_fb_err : integer := 64; -- must be a power of 2
        constant nbr_of_fb_err_l2 : integer := nsl_math.arith.log2(nbr_of_fb_err);

        type regs_t is
            record
                state : state_t;
                stats_buf : buffer_t;
                seq_num : unsigned(15 downto 0);
                payload_integrity_ko : boolean;
                pkt_size_corrupted, header_error : boolean;
                --
                feedback_pkt_toggle : std_ulogic;
                feedback_array : unsigned_array_t(0 to nbr_of_fb_err - 1);
                feedback_read_ptr, feedback_write_ptr : unsigned(nbr_of_fb_err_l2- 1 downto 0);
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
            r.stats_buf <= reset(stats_config_c);
            r.seq_num <= (others => '0');
            r.payload_integrity_ko <= false;
            r.pkt_size_corrupted <= false;
            r.header_error <= false;
            --
            r.feedback_pkt_toggle <= '0';
            r.feedback_array <= (others => (others => '0'));
            r.feedback_read_ptr <= (others => '0');
            r.feedback_write_ptr <= (others => '0');
        end if;
        end process;

        status_process: process(r, in_i, feedback_i, toggle_i)
            variable stats : stats_t;
        begin

            rin <= r;
            stats := stats_unpack(bytes(stats_config_c, r.stats_buf));

            case r.state is
                when ST_RESET =>
                    rin.state <= ST_STATUS_DEC;

                when ST_STATUS_DEC =>
                    if is_valid(config_c, in_i) then
                        rin.stats_buf <= shift(stats_config_c, r.stats_buf, in_i);
                        if is_last(stats_config_c, r.stats_buf) then
                            rin.state <= ST_ASSERT;
                        end if;
                    end if;

                when ST_ASSERT =>                
                    rin.state <= ST_STATUS_DEC;
                    if r.pkt_size_corrupted then
                        rin.feedback_read_ptr <= r.feedback_read_ptr + 1;
                        if not is_size_corrupted(r.feedback_array(to_integer(r.feedback_read_ptr))) and
                           (not is_rand_data_corrupted(stats.stats_index_data_ko) or
                            not is_size_corrupted(stats.stats_index_data_ko)) then
                                rin.state <= ST_ASSERT_ERROR;
                        end if;
                    -- A Seqnum error may result from either a packet drop or a bit swap;
                    -- these two cases cannot be distinguished here.
                    elsif not is_seqnum_corrupted(stats.stats_index_data_ko) then
                        rin.feedback_read_ptr <= r.feedback_read_ptr + 1;
                        if stats.stats_index_data_ko /= r.feedback_array(to_integer(r.feedback_read_ptr)) then
                            rin.state <= ST_ASSERT_ERROR;
                        end if;
                    end if;

                when ST_ASSERT_ERROR => 
                    rin.state <= ST_STATUS_DEC;

                when others => 
                    null;

            end case;
            -- Feedback data is stored only when the seqnum and/or size fields are valid.
            -- In that case, storage resumes once the toggle signal changes state.
            if feedback_i.error = '1' then 
                if not r.payload_integrity_ko then
                    rin.pkt_size_corrupted <= is_size_corrupted(feedback_i.pkt_index_ko);
                    rin.payload_integrity_ko <= is_seqnum_corrupted(feedback_i.pkt_index_ko) or is_size_corrupted(feedback_i.pkt_index_ko) or is_rand_data_corrupted(feedback_i.pkt_index_ko);
                    rin.header_error <= is_header_corrupted(feedback_i.pkt_index_ko);
                    -- 
                    if is_header_corrupted(feedback_i.pkt_index_ko) then
                        if not r.header_error then
                            rin.feedback_array(to_integer(r.feedback_write_ptr)) <= feedback_i.pkt_index_ko;
                            rin.feedback_write_ptr <= unsigned(r.feedback_write_ptr + 1);
                        end if;
                    else
                        rin.feedback_array(to_integer(r.feedback_write_ptr)) <= feedback_i.pkt_index_ko;
                        rin.feedback_write_ptr <= unsigned(r.feedback_write_ptr + 1);
                    end if;
                else
                    if toggle_i = '1' then
                        rin.pkt_size_corrupted <= is_size_corrupted(feedback_i.pkt_index_ko);
                        rin.payload_integrity_ko <= is_seqnum_corrupted(feedback_i.pkt_index_ko) or is_size_corrupted(feedback_i.pkt_index_ko) or is_rand_data_corrupted(feedback_i.pkt_index_ko);
                        rin.header_error <= is_header_corrupted(feedback_i.pkt_index_ko);
                        -- 
                        if is_header_corrupted(feedback_i.pkt_index_ko) then
                            if not r.header_error then
                                rin.feedback_array(to_integer(r.feedback_write_ptr)) <= feedback_i.pkt_index_ko;
                                rin.feedback_write_ptr <= unsigned(r.feedback_write_ptr + 1);
                            end if;
                        else
                            rin.feedback_array(to_integer(r.feedback_write_ptr)) <= feedback_i.pkt_index_ko;
                            rin.feedback_write_ptr <= unsigned(r.feedback_write_ptr + 1);
                        end if;
                    end if;
                end if;
            end if;
            -- Need to check valid to be sure a stats pkt is not
            -- Being sent
            if toggle_i = '1' then
                rin.header_error <= false;
                rin.pkt_size_corrupted <= false;
                rin.payload_integrity_ko <= false;
                rin.feedback_pkt_toggle <= not r.feedback_pkt_toggle;
            end if;
        end process;

        assert_error_o <= to_logic(r.state = ST_ASSERT_ERROR);

        in_o <= accept(config_c, r.state /= ST_ASSERT or
                                r.state /= ST_ASSERT_ERROR);

    end architecture;
