library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_amba.stream_fifo.all;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;

entity axi4_stream_padder is
    generic (
        config_c       : config_t;
        min_size_c     : positive;
        padding_byte_c : byte := x"00"
    );
    port (
        reset_n_i : in std_ulogic;
        clock_i   : in std_ulogic;

        in_i : in  master_t;
        in_o : out slave_t;

        out_o : out master_t;
        out_i : in  slave_t
    );
end entity;

architecture beh of axi4_stream_padder is

    type in_state_t is (
        IN_RESET,
        IN_DATA,
        IN_COMMIT
    );

    type out_state_t is (
        OUT_RESET,
        OUT_DATA,
        OUT_PAD
    );

    constant fifo_depth_c : integer := 2;

    constant byte_string_padding : byte_string(0 to config_c.data_width - 1) := (others => padding_byte_c);

    type regs_t is record
        in_state : in_state_t;
        out_state : out_state_t;

        fifo : master_vector(0 to fifo_depth_c - 1);
        fifo_fillness : integer range 0 to fifo_depth_c;

        out_left : integer range 0 to min_size_c;
    end record;

    signal r, rin : regs_t;

begin

    assert not config_c.has_keep and not config_c.has_strobe
    report "This module does not handle sparse input stream"
        severity failure;

    regs : process (clock_i, reset_n_i) is
    begin
        if rising_edge(clock_i) then
            r <= rin;
        end if;

        if reset_n_i = '0' then
            r.out_state <= OUT_RESET;
        end if;
    end process;

    transition : process (r, in_i, out_i) is
        variable fifo_push, fifo_pop : boolean;
    begin
        rin <= r;

        fifo_pop := false;
        fifo_push := false;

        case r.in_state is
            when IN_RESET =>
                rin.in_state <= IN_DATA;
                rin.fifo_fillness <= 0;
                rin.fifo <= (others => transfer_defaults(config_c));

            when IN_DATA =>
                if r.fifo_fillness < fifo_depth_c and is_valid(config_c, in_i) then
                    fifo_push := true;
                    if is_last(config_c, in_i) then
                        rin.in_state <= IN_COMMIT;
                    end if;
                end if;

            when IN_COMMIT =>
                if (r.out_state = OUT_RESET) then
                    rin.in_state <= IN_DATA;
                end if;

        end case;

        case r.out_state is
            when OUT_RESET =>
                rin.out_state <= OUT_DATA;
                rin.out_left <= min_size_c;

            when OUT_DATA =>

                fifo_pop := r.fifo_fillness > 0 and is_ready(config_c, out_i);

                if fifo_pop and r.out_left > 0 then
                    rin.out_left <= r.out_left - config_c.data_width;
                end if;

                if r.fifo_fillness = 0 or (r.fifo_fillness = 1 and out_i.ready = '1') then
                    if r.in_state = IN_COMMIT then
                        -- Check if padding is needed for committed frames
                        if r.out_left = 0 or (r.out_left = config_c.data_width and fifo_pop) then
                            rin.out_left <= min_size_c - 1;
                            rin.out_state <= OUT_RESET;
                        else
                            rin.out_state <= OUT_PAD;
                        end if;
                    end if;
                end if;

            when OUT_PAD =>
                if is_ready(config_c, out_i) then
                    if r.out_left <= config_c.data_width then
                        rin.out_state <= OUT_RESET;
                    else
                        rin.out_left <= r.out_left - config_c.data_width;
                    end if;
                end if;

        end case;

        if fifo_push and fifo_pop then
            rin.fifo <= shift_left(config_c, r.fifo);
            rin.fifo(r.fifo_fillness - 1) <= in_i;
        elsif fifo_push then
            rin.fifo(r.fifo_fillness) <= in_i;
            rin.fifo_fillness <= r.fifo_fillness + 1;
        elsif fifo_pop then
            rin.fifo <= shift_left(config_c, r.fifo);
            rin.fifo_fillness <= r.fifo_fillness - 1;
        end if;
    end process;

    moore : process (r) is
    begin

        in_o <= accept(config_c, false);
        out_o <= transfer_defaults(config_c);

        case r.out_state is
            when OUT_RESET =>
                null;

            when OUT_DATA =>
                out_o <= transfer(config_c,
                         src => r.fifo(0),
                         force_last => true,
                         last => is_last(config_c, r.fifo(0)) and
                         r.out_left <= config_c.data_width);

            when OUT_PAD =>
                out_o <= transfer(config_c,
                         bytes => byte_string_padding,
                         valid => true,
                         last => r.out_left <= config_c.data_width);

        end case;

        case r.in_state is
            when IN_RESET | IN_COMMIT =>
                null;

            when IN_DATA =>
                in_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);
        end case;
    end process;

end architecture;
