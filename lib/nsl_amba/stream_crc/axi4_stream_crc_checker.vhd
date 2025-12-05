library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_data, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_data.crc.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity axi4_stream_crc_checker is
    generic (
        config_c : config_t;
        crc_c    : crc_params_t
    );
    port (
        clock_i   : in std_ulogic;
        reset_n_i : in std_ulogic;

        in_i : in  master_t;
        in_o : out slave_t;
        in_error_i : in std_ulogic := '0';

        out_o : out master_t;
        out_i : in  slave_t;

        crc_valid_o : out std_ulogic
    );
begin

    assert not (config_c.data_width > 1 and (config_c.has_keep or config_c.has_strobe))
        report "This module does not handle sparse input stream"
        severity failure;

    assert (crc_byte_length(crc_c) mod config_c.data_width) = 0
    report "CRC should be an integer count of beats"
        severity failure;

end entity;

architecture beh of axi4_stream_crc_checker is

    constant fifo_depth_c : integer := 3;

    type state_t is (
        ST_RESET,
        ST_FORWARD,
        ST_CRC_COMMIT
    );

    type out_state_t is (
        OUT_RESET,
        OUT_DATA,
        OUT_CRC_COMMIT
    );

    type regs_t is record
        state : state_t;
        out_state : out_state_t;
        crc_valid : std_ulogic;

        fifo : master_vector(0 to fifo_depth_c - 1);
        fifo_fillness : integer range 0 to fifo_depth_c;
        data_crc : crc_state_t;
        in_error : std_ulogic;
    end record;

    signal r, rin : regs_t;

begin

    regs : process (clock_i, reset_n_i) is
    begin
        if rising_edge(clock_i) then
            r <= rin;
        end if;

        if reset_n_i = '0' then
            r.state <= ST_RESET;
            r.out_state <= OUT_RESET;
        end if;
    end process;

    transition : process (r, in_i, out_i, in_error_i) is
        variable cur_crc, next_crc : crc_state_t;
        variable fifo_push, fifo_pop : boolean;
    begin
        rin <= r;

        fifo_pop := false;
        fifo_push := false;

        next_crc := crc_update(crc_c, cur_crc, bytes(config_c, r.fifo(0)));

        case r.state is
            when ST_RESET =>
                rin.state <= ST_FORWARD;
                rin.fifo_fillness <= 0;
                rin.in_error <= '0';

            when ST_FORWARD =>
                if r.fifo_fillness < fifo_depth_c and is_valid(config_c, in_i) then
                    fifo_push := true;
                    rin.in_error <= in_error_i;
                    if is_last(config_c, in_i) then
                        rin.state <= ST_CRC_COMMIT;
                    end if;
                end if;

            when ST_CRC_COMMIT =>
                if r.out_state = OUT_CRC_COMMIT and is_ready(config_c, out_i) then
                    rin.in_error <= '0';
                    rin.state <= ST_FORWARD;
                end if;
        end case;

        case r.out_state is
            when OUT_RESET =>
                rin.out_state <= OUT_DATA;
                rin.crc_valid <= '0';
                rin.data_crc <= crc_init(crc_c);

            when OUT_DATA =>

                if r.fifo_fillness > 1 and is_ready(config_c, out_i) then
                    fifo_pop := true;
                    rin.data_crc <= crc_update(crc_c, r.data_crc, bytes(config_c, r.fifo(0)));
                end if;
                
                if is_valid(config_c, r.fifo(0)) and (is_ready(config_c, out_i) or (r.fifo_fillness <= 1)) then
                    rin.crc_valid <= to_logic(crc_is_valid(crc_c, 
                        crc_update(crc_c, r.data_crc, bytes(config_c, r.fifo(0)))));
                    if is_last(config_c, r.fifo(0)) then
                        rin.out_state <= OUT_CRC_COMMIT;
                    end if;
                end if;

            when OUT_CRC_COMMIT =>

                fifo_pop := r.fifo_fillness /= 0 and is_ready(config_c, out_i);

                if is_ready(config_c, out_i) then
                    if r.fifo_fillness = 0 or r.fifo_fillness = 1 then
                        rin.crc_valid <= '0';
                        rin.data_crc <= crc_init(crc_c);
                        rin.out_state <= OUT_DATA;
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

    mealy : process (r, in_i, out_i) is
    begin
        case r.state is
            when ST_RESET =>
                in_o <= accept(config_c, false);

            when ST_FORWARD =>
                in_o <= accept(config_c, (r.fifo_fillness < fifo_depth_c));

            when ST_CRC_COMMIT =>
                in_o <= accept(config_c, false);

        end case;

        case r.out_state is
            when OUT_RESET =>
                crc_valid_o <= '0';
                out_o <= transfer_defaults(config_c);

            when OUT_DATA =>
                crc_valid_o <= '0'; 
                out_o <= transfer(config_c, r.fifo(0), force_valid => true, valid => r.fifo_fillness > 1);

            when OUT_CRC_COMMIT =>
                crc_valid_o <= r.crc_valid and (not r.in_error); 
                out_o <= transfer(config_c, r.fifo(0));

        end case;
    end process;

end architecture;
