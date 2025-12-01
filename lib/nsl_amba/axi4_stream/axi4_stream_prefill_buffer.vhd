library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_data, nsl_math, nsl_logic;
use nsl_logic.bool.all;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;

entity axi4_stream_prefill_buffer is
    generic (
        config_c    : config_t;
        prefill_count_c : natural
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

architecture beh of axi4_stream_prefill_buffer is

    type in_state_t is (
        IN_RESET,
        IN_DATA,
        IN_DONE
    );

    type out_state_t is (
        OUT_RESET,
        OUT_PREFILL,
        OUT_DATA,
        OUT_FLUSH,
        OUT_DONE
    );

    constant fifo_depth_c : integer := prefill_count_c + 2;

    type regs_t is record
        in_state : in_state_t;

        fifo : master_vector(0 to fifo_depth_c - 1);
        fifo_fillness : integer range 0 to fifo_depth_c;

        out_state : out_state_t;
    end record;

    signal r, rin : regs_t;

begin

    regs : process (clock_i, reset_n_i) is
    begin
        if rising_edge(clock_i) then
            r <= rin;
        end if;

        if reset_n_i = '0' then
            r.fifo <= (others => transfer_defaults(config_c));
            r.in_state <= IN_RESET;
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
                rin.fifo_fillness <= 0;
                rin.in_state <= IN_DATA;

            when IN_DATA =>
                if r.fifo_fillness < fifo_depth_c and is_valid(config_c, in_i) then
                    fifo_push := true;
                    if is_last(config_c, in_i) then
                        rin.in_state <= IN_DONE;
                    end if;
                end if;

            when IN_DONE =>
                if r.out_state = OUT_DONE then
                    rin.in_state <= IN_RESET;
                end if;
        end case;

        case r.out_state is
            when OUT_RESET =>
                rin.out_state <= OUT_PREFILL;

            when OUT_PREFILL =>
                if r.fifo_fillness >= prefill_count_c then
                    rin.out_state <= OUT_DATA;
                end if;
                if r.in_state = IN_DONE then
                    rin.out_state <= OUT_FLUSH;
                end if;

            when OUT_DATA =>
                if r.fifo_fillness > 1 and out_i.ready = '1' then
                    fifo_pop := true;
                end if;

                if r.in_state = IN_DONE then
                    rin.out_state <= OUT_FLUSH;
                end if;

            when OUT_FLUSH =>
                if r.fifo_fillness > 0 and out_i.ready = '1' then
                    fifo_pop := true;
                end if;

                if r.fifo_fillness = 0
                    or (r.fifo_fillness = 1 and out_i.ready = '1') then
                    rin.out_state <= OUT_DONE;
                end if;

            when OUT_DONE =>
                if r.in_state = IN_DONE then
                    rin.out_state <= OUT_RESET;
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
        out_o <= transfer_defaults(config_c);

        case r.out_state is

            when OUT_DATA =>
                out_o <= transfer(config_c,
                         src => r.fifo(0),
                         valid => r.fifo_fillness > 1,
                         last => false);
                        
            when OUT_FLUSH =>
                    out_o <= transfer(config_c,
                            src => r.fifo(0),
                            valid => r.fifo_fillness > 0,
                            last => r.fifo_fillness = 1);

            when others =>
                null;

        end case;

        case r.in_state is
            when IN_RESET | IN_DONE =>
                in_o.ready <= '0';

            when IN_DATA =>
                in_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);
        end case;
    end process;
end architecture;
