library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, work, nsl_data, nsl_math, nsl_logic, nsl_amba;
use nsl_logic.bool.all;
use work.flit.all;
use nsl_data.bytestream.all;
use nsl_amba.axi4_stream.all;

entity mii_flit_to_axi4_stream is
    port (
        clock_i   : in std_ulogic;
        reset_n_i : in std_ulogic;

        flit_i  : in mii_flit_t;
        valid_i : in std_ulogic;

        out_o : out master_t;
        out_i : in  slave_t
    );
end entity;

architecture beh of mii_flit_to_axi4_stream is

    type in_state_t is (
        IN_RESET,
        IN_IDLE,
        IN_PRE,
        IN_DATA,
        IN_COMMIT
    );

    type out_state_t is (
        OUT_RESET,
        OUT_IDLE,
        OUT_DATA
    );

    constant fifo_depth_c : integer := 3;

    type regs_t is record
        in_state : in_state_t;
        in_overflow : boolean;
        in_error_seen : boolean;

        fifo : byte_string(0 to fifo_depth_c - 1);
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
            r.in_state <= IN_RESET;
            r.out_state <= OUT_RESET;
        end if;
    end process;

    transition : process (r, flit_i, valid_i, out_i) is
        variable fifo_push, fifo_pop : boolean;
    begin
        rin <= r;

        fifo_pop := false;
        fifo_push := false;

        case r.in_state is
            when IN_RESET =>
                rin.in_state <= IN_IDLE;

            when IN_IDLE =>
                if valid_i = '1' and flit_i.valid = '1' then
                    rin.in_state <= IN_PRE;
                    rin.in_overflow <= false;
                    rin.in_error_seen <= false;
                end if;

            when IN_PRE =>
                if valid_i = '1' then
                    if flit_i.valid = '1' and flit_i.error = '0' then
                        if flit_i.data = x"55" then
                            rin.in_state <= IN_PRE;
                        elsif flit_i.data = x"d5" then
                            rin.in_state <= IN_DATA;
                        else
                            rin.in_state <= IN_IDLE;
                        end if;
                    else
                        rin.in_state <= IN_IDLE;
                    end if;
                end if;

            when IN_DATA =>
                if valid_i = '1' then
                    if flit_i.valid = '1' and flit_i.error = '0' then
                        fifo_push := true;
                    elsif flit_i.valid = '0' and flit_i.error = '1' then
                        -- GMII / RGMII:
                        -- - 00-0d, 10-1e, 20-fe: reserved
                        -- - 0e: false carrier (should not happen here)
                        -- - 0f: carrier extend
                        -- - 1f: carrier error extend
                        -- - ff: carrier sense
                        if flit_i.data = x"0f" then
                            -- Carrier extension
                            null;
                        elsif flit_i.data = x"1f" then
                            -- Carrier extension w/ error
                            rin.in_error_seen <= true;
                        end if;
                    elsif flit_i.valid = '1' and flit_i.error = '1' then
                        rin.in_error_seen <= true;
                    else -- valid = '0', error = '0'
                        rin.in_state <= IN_COMMIT;
                    end if;
                end if;

            when IN_COMMIT =>
                if r.out_state = OUT_IDLE and r.fifo_fillness = 0 then
                    rin.in_state <= IN_IDLE;
                end if;

        end case;

        case r.out_state is
            when OUT_RESET =>
                rin.out_state <= OUT_IDLE;

            when OUT_IDLE =>
                if r.in_state = IN_DATA and r.fifo_fillness > 1 then
                    rin.out_state <= OUT_DATA;
                    if is_ready(axi4_flit_cfg, out_i) then
                        fifo_pop := true;
                    end if;
                end if;

            when OUT_DATA =>
                if is_ready(axi4_flit_cfg, out_i) and r.fifo_fillness > 1 then
                    fifo_pop := true;
                end if;

                if (is_ready(axi4_flit_cfg, out_i) and r.fifo_fillness = 1) then
                    if r.in_state = IN_COMMIT then
                        fifo_pop := true;
                        rin.out_state <= OUT_IDLE;
                        rin.fifo_fillness <= 0;
                    end if;
                end if;
        end case;

        if fifo_push and fifo_pop then
            rin.fifo <= shift_left(r.fifo);
            rin.fifo(r.fifo_fillness - 1) <= flit_i.data;
        elsif fifo_push then
            if r.fifo_fillness = fifo_depth_c then
                rin.in_overflow <= true;
            else
                rin.fifo(r.fifo_fillness) <= flit_i.data;
                rin.fifo_fillness <= r.fifo_fillness + 1;
            end if;
        elsif fifo_pop then
            rin.fifo <= shift_left(r.fifo);
            rin.fifo_fillness <= r.fifo_fillness - 1;
        end if;
    end process;

    moore : process (r) is
        variable last_v : boolean;
    begin

        last_v := (((is_ready(axi4_flit_cfg, out_i)) and r.fifo_fillness = 1)) and
                  r.in_state = IN_COMMIT;
        out_o <= transfer_defaults(axi4_flit_cfg);

        case r.out_state is
            when OUT_IDLE =>
                out_o <= transfer(cfg => axi4_flit_cfg,
                         bytes => from_suv(r.fifo(0)),
                         user => (0 => to_logic(r.in_error_seen or r.in_overflow)),
                         valid => r.fifo_fillness > 1,
                         last => last_v);

            when OUT_DATA =>
                out_o <= transfer(cfg => axi4_flit_cfg,
                         bytes => from_suv(r.fifo(0)),
                         user => (0 => to_logic(r.in_error_seen or r.in_overflow)),
                         valid => r.fifo_fillness > 1 or
                         (r.fifo_fillness /= 0 and r.in_state = IN_COMMIT),
                         last => last_v);

            when others =>
                null;
        end case;
    end process;

end architecture;
