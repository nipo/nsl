library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, work, nsl_data, nsl_math, nsl_logic, nsl_amba, nsl_logic;
use nsl_logic.bool.all;
use work.flit.all;
use nsl_data.bytestream.all;
use nsl_amba.axi4_stream.all;
use nsl_logic.logic.all;

entity mii_flit_from_axi4_stream is
    generic (
        ipg_c             : natural  := 96; -- bits
        pre_count_c       : natural  := 8; -- flits, not including SFD
        handle_underrun_c : boolean  := true
    );
    port (
        clock_i   : in std_ulogic;
        reset_n_i : in std_ulogic;

        in_i : in  master_t;
        in_o : out slave_t;

        underrun_o : out std_ulogic;
        packet_o   : out std_ulogic;
        flit_o     : out mii_flit_t;
        ready_i    : in  std_ulogic
    );
end entity;

architecture beh of mii_flit_from_axi4_stream is

    type in_state_t is (
        IN_RESET,
        IN_IDLE,
        IN_DATA,
        IN_COMMIT
    );

    type out_state_t is (
        OUT_RESET,
        OUT_IPG,
        OUT_IDLE,
        OUT_PRE,
        OUT_SFD,
        OUT_DATA
    );

    constant out_ctr_max_c : integer := nsl_math.arith.max(ipg_c/8, pre_count_c);
    constant fifo_depth_c : integer := 2;

    type regs_t is record
        in_state : in_state_t;

        fifo : byte_string(0 to fifo_depth_c - 1);
        fifo_fillness : integer range 0 to fifo_depth_c;
        fifo_underrun : boolean;

        tx_err : std_ulogic;

        out_counter : natural range 0 to out_ctr_max_c - 1;
        out_state : out_state_t;
    end record;

    signal r, rin : regs_t;

begin

    regs : process (reset_n_i, clock_i)
    begin
        if rising_edge(clock_i) then
            r <= rin;
        end if;

        if reset_n_i = '0' then
            r.in_state <= IN_RESET;
            r.out_state <= OUT_RESET;
            r.fifo_fillness <= 0;
            r.tx_err <= '0';
        end if;
    end process;

    transition : process (r, in_i, ready_i)
        variable fifo_push, fifo_pop : boolean;
    begin
        rin <= r;

        fifo_pop := false;
        fifo_push := false;

        case r.in_state is
            when IN_RESET =>
                rin.in_state <= IN_IDLE;

            when IN_IDLE =>
                if is_valid(axi4_flit_cfg, in_i) then
                    if and_reduce(user(axi4_flit_cfg, in_i)) = '1' then
                        rin.tx_err <= '1';
                    end if;
                    if is_last(axi4_flit_cfg, in_i) then
                        rin.in_state <= IN_COMMIT;
                    else
                        rin.in_state <= IN_DATA;
                    end if;
                    rin.fifo_underrun <= false;
                    fifo_push := true;
                end if;

            when IN_DATA =>
                if r.fifo_fillness < fifo_depth_c and is_valid(axi4_flit_cfg, in_i) then
                    fifo_push := true;
                    if and_reduce(user(axi4_flit_cfg, in_i)) = '1' then
                        rin.tx_err <= '1';
                    end if;
                    if is_last(axi4_flit_cfg, in_i) then
                        rin.in_state <= IN_COMMIT;
                    end if;
                end if;

            when IN_COMMIT =>
                if r.out_state = OUT_IPG then
                    rin.tx_err <= '0';
                    rin.in_state <= IN_IDLE;
                end if;
        end case;

        case r.out_state is
            when OUT_RESET =>
                rin.out_state <= OUT_IPG;
                rin.out_counter <= ipg_c / 8 - 1;

            when OUT_IPG =>
                if r.out_counter = 0 then
                    rin.out_state <= OUT_IDLE;
                else
                    rin.out_counter <= r.out_counter - 1;
                end if;

            when OUT_IDLE =>
                if r.fifo_fillness > 0 then
                    rin.out_state <= OUT_PRE;
                    rin.out_counter <= pre_count_c - 1;
                end if;

            when OUT_PRE =>
                if ready_i = '1' then
                    if r.out_counter = 0 then
                        rin.out_state <= OUT_SFD;
                    else
                        rin.out_counter <= r.out_counter - 1;
                    end if;
                end if;

            when OUT_SFD =>
                if ready_i = '1' then
                    rin.out_state <= OUT_DATA;
                end if;

            when OUT_DATA =>
                if r.fifo_fillness > 0 and ready_i = '1' then
                    fifo_pop := true;
                end if;

                if (r.fifo_fillness = 1 and ready_i = '1')
                    or r.fifo_fillness = 0 then
                    if r.in_state = IN_COMMIT then
                        rin.out_state <= OUT_IPG;
                        rin.out_counter <= ipg_c / 8 - 1;
                    end if;
                end if;
        end case;

        if fifo_push and fifo_pop then
            rin.fifo <= shift_left(r.fifo);
            rin.fifo(r.fifo_fillness - 1) <= bytes(axi4_flit_cfg, in_i)(0);
        elsif fifo_push then
            rin.fifo(r.fifo_fillness) <= bytes(axi4_flit_cfg, in_i)(0);
            rin.fifo_fillness <= r.fifo_fillness + 1;
        elsif fifo_pop then
            if r.fifo_fillness = 0 then
                rin.fifo_underrun <= true;
            else
                rin.fifo <= shift_left(r.fifo);
                rin.fifo_fillness <= r.fifo_fillness - 1;
            end if;
        end if;
    end process;

    moore : process (r)
        variable last_v : boolean;
    begin
        underrun_o <= '0';
        last_v := ((r.fifo_fillness = 1 and ready_i = '1') or r.fifo_fillness = 0) and r.in_state = IN_COMMIT;

        case r.in_state is
            when IN_RESET | IN_COMMIT =>
                in_o <= accept(axi4_flit_cfg, false);

            when IN_IDLE | IN_DATA =>
                in_o <= accept(axi4_flit_cfg, r.fifo_fillness < fifo_depth_c);
        end case;

        case r.out_state is
            when OUT_RESET | OUT_IPG | OUT_IDLE =>
                flit_o.valid <= '0';
                flit_o.error <= '0';
                flit_o.data <= x"00";
                packet_o <= '0';

            when OUT_DATA =>
                if r.fifo_underrun and handle_underrun_c then
                    flit_o.error <= '1';
                    flit_o.data <= x"1f";
                    flit_o.valid <= '0';
                else
                    flit_o.error <= r.tx_err;
                    flit_o.data <= r.fifo(0);
                    flit_o.valid <= to_logic(r.fifo_fillness /= 0);
                end if;
                packet_o <= to_logic(not last_v);

            when OUT_PRE =>
                flit_o.valid <= '1';
                flit_o.error <= '0';
                flit_o.data <= x"55";
                packet_o <= '1';

            when OUT_SFD =>
                flit_o.valid <= '1';
                flit_o.error <= '0';
                flit_o.data <= x"d5";
                packet_o <= '1';

        end case;
    end process;
end architecture;
