library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_data, nsl_math, nsl_logic, nsl_amba;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;
use nsl_amba.axi4_stream.all;
use nsl_amba.stream_fifo.all;
use nsl_logic.logic.all;

entity axi4_stream_fifo_clean is
    generic (
        fifo_word_count_l2 : natural  := 10;
        config_c : config_t
    );
    port (
        clock_i   : in std_ulogic;
        reset_n_i : in std_ulogic;

        in_i : in  master_t;
        in_error_i : in std_ulogic;
        in_o : out slave_t;
        in_free_o : out unsigned(fifo_word_count_l2 downto 0);

        out_o : out master_t;
        out_i : in  slave_t;
        out_available_o : out unsigned(fifo_word_count_l2 downto 0)
    );
end entity;

architecture beh of axi4_stream_fifo_clean is

    type state_t is (
        IN_RESET,
        IN_DATA
    );

    type regs_t is record
        state : state_t;
        in_error : std_ulogic;
    end record;

    signal r, rin : regs_t;
    signal fifo_o : slave_t;
    signal do_commit_s, do_rollback_s : std_ulogic;

begin

    regs : process (clock_i, reset_n_i) is
    begin
        if rising_edge(clock_i) then
            r <= rin;
        end if;

        if reset_n_i = '0' then
            r.state <= IN_RESET;
        end if;
    end process;

    transition : process (r, in_i, fifo_o, in_error_i) is
    begin
        rin <= r;

        case r.state is
            when IN_RESET =>
                rin.in_error <= '0';
                rin.state <= IN_DATA;

            when IN_DATA =>
                if is_valid(config_c, in_i) and is_ready(config_c, fifo_o) then
                    if is_last(config_c, in_i) then
                        rin.in_error <= '0';
                    elsif in_error_i = '1' then
                        rin.in_error <= '1';
                    end if;
                end if;
        end case;
    end process;

    -- Commit and rollback take the beat of their own cycle in, so the
    -- last beat of a packet is the one that publishes it, or the one
    -- that takes the whole packet back.
    mealy : process (r, in_i, fifo_o, in_error_i) is
        variable packet_done, packet_error : boolean;
    begin
        packet_done := r.state = IN_DATA
                       and is_valid(config_c, in_i)
                       and is_ready(config_c, fifo_o)
                       and is_last(config_c, in_i);
        packet_error := r.in_error = '1' or in_error_i = '1';

        do_commit_s <= to_logic(packet_done and not packet_error);
        do_rollback_s <= to_logic(packet_done and packet_error);
    end process;

    out_fifo : nsl_amba.stream_fifo.axi4_stream_fifo_cancellable
    generic map(
        config_c        => config_c,
        word_count_l2_c => fifo_word_count_l2
    )
    port map(
        clock_i   => clock_i,
        reset_n_i => reset_n_i,

        in_i          => in_i,
        in_o          => fifo_o,
        in_commit_i   => do_commit_s,
        in_rollback_i => do_rollback_s,
        in_free_o     => in_free_o,

        out_o           => out_o,
        out_i           => out_i,
        out_available_o => out_available_o
    );

    in_o <= accept(config_c, r.state = IN_DATA and is_ready(config_c, fifo_o));

end architecture;
