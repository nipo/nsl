library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_memory, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_logic.bool.all;

entity axi4_stream_fifo_atomic is
    generic (
        config_c  : config_t;
        depth_c     : natural;
        txn_depth_c : natural := 4;
        clk_count_c : natural range 1 to 2
    );
    port (
        reset_n_i : in std_ulogic;
        clock_i   : in std_ulogic_vector(0 to clk_count_c - 1);

        in_i : in  master_t;
        in_o : out slave_t;

        out_o : out master_t;
        out_i : in  slave_t
    );
end entity;

architecture rtl of axi4_stream_fifo_atomic is

    signal in_storage_s, out_storage_s : bus_t;
    signal in_end_detected, out_end_detected,
    in_allow, out_allow : std_ulogic;

begin

    frame_fifo : nsl_memory.fifo.fifo_homogeneous
    generic map(
        word_count_c  => txn_depth_c,
        data_width_c  => 1,
        clock_count_c => clk_count_c
    )
    port map(
        reset_n_i   => reset_n_i,
        clock_i     => clock_i,
        out_data_o  => open,
        out_ready_i => out_end_detected,
        out_valid_o => out_allow,
        in_data_i   => "-",
        in_valid_i  => in_end_detected,
        in_ready_o  => in_allow
    );

    storage : nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
        config_c      => config_c,
        depth_c       => depth_c,
        clock_count_c => clk_count_c
    )
    port map(
        clock_i   => clock_i,
        reset_n_i => reset_n_i,

        in_i => in_storage_s.m,
        in_o => in_storage_s.s,

        out_o => out_storage_s.m,
        out_i => out_storage_s.s
    );

    in_end_detected <= to_logic(is_valid(config_c, in_i) and 
                       is_last(config_c, in_i) and 
                       is_ready(config_c, in_storage_s.s) and 
                       (in_allow = '1'));

    out_end_detected <= to_logic(is_valid(config_c, out_storage_s.m) and 
                        is_last(config_c, out_storage_s.m) and 
                        is_ready(config_c, out_i) and 
                        (out_allow = '1'));

    in_o <= accept(config_c, (in_allow = '1') and is_ready(config_c, in_storage_s.s));
    in_storage_s.m <= transfer(cfg => config_c,
                               src => in_i,
                               force_valid => true,
                               valid => is_valid(config_c, in_i) and
                                       (in_allow = '1'));

    out_o <= transfer(cfg => config_c,
                      src => out_storage_s.m,
                      force_valid => true,
                      valid => is_valid(config_c, out_storage_s.m) and
                               (out_allow = '1'));

    out_storage_s.s <= accept(config_c, is_ready(config_c, out_i) and (out_allow = '1'));

end architecture;
