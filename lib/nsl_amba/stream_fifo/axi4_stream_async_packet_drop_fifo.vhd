library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_memory, nsl_amba, nsl_clocking, nsl_math, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity axi4_stream_async_packet_drop_fifo is
    generic (
        config_c        : config_t;
        word_count_l2_c : integer;
        clock_count_c   : natural range 1 to 2
    );
    port (
        reset_n_i : in std_ulogic;
        clock_i   : in std_ulogic_vector(0 to clock_count_c - 1);

        error_i : in std_ulogic := '0';

        in_i : in  master_t;
        in_o : out slave_t;

        out_i : in  slave_t;
        out_o : out master_t;

        -- Validation port
        overrun_o : out std_ulogic

    );
end entity;

architecture beh of axi4_stream_async_packet_drop_fifo is

    constant word_count_data_width_l2_c : integer := nsl_math.arith.log2(2**word_count_l2_c/config_c.data_width);
    subtype ptr_t is unsigned(word_count_data_width_l2_c - 1 downto 0);
    subtype mem_ptr_t is unsigned(word_count_data_width_l2_c - 1 downto 0);

    constant fifo_elements_c : string := "idskoul";
    constant data_fifo_width_c: positive := vector_length(config_c, fifo_elements_c);
    subtype data_fifo_word_t is std_ulogic_vector(0 to data_fifo_width_c-1);
  
    function to_ptr(i : integer) return ptr_t is
    begin
        return to_unsigned(i, ptr_t'length);
    end function;

    type write_ram_t is record
        data : data_fifo_word_t;
        ptr : ptr_t;
        enable : std_ulogic;
    end record;

    type read_ram_t is record
        read_data : data_fifo_word_t;
        read_ptr : ptr_t;
        read_enable : std_ulogic;
    end record;

    signal right_wrap_and_rptr_bin_s : unsigned(ptr_t'length downto 0);
    signal right_rptr_wrap_s : std_ulogic;

    signal right_rptr_s, right_rptr_gray_s :  unsigned(ptr_t'length downto 0);

    signal left_resync_wrap_and_wptr_s  : std_ulogic_vector(ptr_t'length downto 0);
    signal left_resync_wrap_and_wptr_ready_s : std_ulogic;

    signal write_ram_s : write_ram_t;
    signal read_ram_s : read_ram_t;
    signal right_rptr_resync_s : ptr_t;

    signal left_wrap_and_wptr_s : std_ulogic_vector(ptr_t'length downto 0);
    signal left_wrap_and_wptr_valid_s, left_wrap_and_wptr_ready_s, left_resync_wrap_and_wptr_valid_s : std_ulogic;

    signal in_streamer_valid_s, out_streamer_valid_s : std_ulogic;
    signal in_streamer_ready_s, out_streamer_ready_s : std_ulogic;
    signal out_stream_data_s : data_fifo_word_t;

    signal reset_n_s: std_ulogic_vector(0 to clock_count_c-1);

    signal in_same_wrap_s, in_fifo_full_s, do_write_s : boolean;
    signal out_fifo_full_s, do_read_s, out_same_wrap_s : boolean;

begin

    write_block : block
        type in_left_data_t is (
            IN_RESET,
            IN_DATA_STORE
        );

        type out_left_data_t is (
            OUT_WRITE_POINTER_IDLE,
            OUT_WRITE_POINTER
        );

        type regs_t is record
            in_state : in_left_data_t;
            out_state : out_left_data_t;
            -- Committed write pointer
            wptr : ptr_t;
            -- Speculative write pointer
            wptr_sp : ptr_t;
            do_commit : std_ulogic;
            -- Speculative gray wrap
            wptr_sp_wrap : std_ulogic;
            wptr_wrap : std_ulogic;
            write_overrun : std_ulogic;
    
        end record;
    
        signal r, rin : regs_t;
    begin
        regs : process (reset_n_s, clock_i) is
        begin
            if rising_edge(clock_i(0)) then
                r <= rin;
            end if;
            if reset_n_s(0) = '0' then
                r.wptr <= to_ptr(0);
                r.wptr_sp <= to_ptr(0);
                r.in_state <= IN_RESET;
                r.out_state <= OUT_WRITE_POINTER_IDLE;
                r.write_overrun <= '0';
                r.wptr_wrap <= '0';
                r.wptr_sp_wrap <= '0';
                r.do_commit <= '0';
            end if;
        end process;

        write_transition : process (r, in_i, error_i, right_rptr_resync_s, left_resync_wrap_and_wptr_valid_s, do_write_s) is
        begin

            rin <= r;

            case r.in_state is
                when IN_RESET =>
                    rin.in_state <= IN_DATA_STORE;

                when IN_DATA_STORE =>
                    if is_valid(config_c, in_i) then
                        if do_write_s then
                            rin.wptr_sp <= r.wptr_sp + 1;
                            rin.wptr_sp_wrap <= not r.wptr_sp_wrap;
                        else
                            rin.write_overrun <= '1';
                        end if;

                        if is_last(config_c, in_i) then
                            if do_write_s and r.write_overrun = '0' and error_i = '0' and r.out_state = OUT_WRITE_POINTER_IDLE then
                                rin.do_commit <= '1';
                                rin.wptr <= r.wptr_sp + 1;
                                rin.wptr_wrap <= not r.wptr_sp_wrap;
                            else
                                -- ROLLBACK
                                rin.wptr_sp <= r.wptr;
                                rin.wptr_sp_wrap <= r.wptr_wrap;
                                rin.write_overrun <= '0';
                            end if;
                        end if;
                    end if;

                when others =>
                    null;

            end case;

            case r.out_state is
                when OUT_WRITE_POINTER_IDLE =>
                    if r.do_commit = '1' then
                        rin.out_state <= OUT_WRITE_POINTER;
                    end if;

                when OUT_WRITE_POINTER =>
                    if left_wrap_and_wptr_ready_s = '1' then
                        rin.do_commit <= '0';
                        rin.out_state <= OUT_WRITE_POINTER_IDLE;
                    end if;

                when others =>
                    null;

            end case;
        end process;

        -- Check if we're in the same wrap cycle as remote read pointer
        in_same_wrap_s <= r.wptr_wrap = right_rptr_wrap_s;
        -- FIFO is full when:
        -- - Pointers are equal AND we're one wrap ahead (different wrap bits)
        -- FIFO has space when:
        -- - Pointers are different in same wrap cycle, OR
        -- - Pointers are equal in same wrap cycle (empty)
        in_fifo_full_s <= (r.wptr_sp = right_rptr_resync_s) and not in_same_wrap_s; 
        do_write_s <= not in_fifo_full_s and is_valid(config_c, in_i);

        ram_writer_proc : process (r, in_i, do_write_s) is
        begin
            write_ram_s.data <= (others => '-');
            write_ram_s.ptr <= r.wptr_sp;
            write_ram_s.enable <= '0';

            case r.in_state is
                when IN_DATA_STORE =>
                    write_ram_s.data <= vector_pack(config_c, fifo_elements_c, in_i);
                    write_ram_s.enable <= to_logic(do_write_s);

                when others =>
                    null;

            end case;
        end process;

        remote_wptr_txer_proc : process (r) is
        begin

            left_wrap_and_wptr_s <= r.wptr_wrap & std_ulogic_vector(r.wptr);
            left_wrap_and_wptr_valid_s <= '0';

            case r.out_state is
                when OUT_WRITE_POINTER =>
                    left_wrap_and_wptr_valid_s <= '1';

                when others =>
                    null;
            end case;
        end process;

        overrun_o <= r.write_overrun;
        in_o <= accept(config_c, true); -- No back pressure, if overrun packet is dropped.
    end block;

    inter_domain_ptr_resync : block 
        constant is_synchronous: boolean := clock_count_c = 1;
    begin 

        async: if not is_synchronous generate
            reset_sync: nsl_clocking.async.async_multi_reset
            generic map(
              debounce_count_c => 4,
              domain_count_c => 2
              )
            port map(
              clock_i => clock_i,
              master_i => reset_n_i,
              slave_o => reset_n_s
              );

            resync_wptr: nsl_clocking.interdomain.interdomain_fifo_slice
            generic map(
                data_width_c => ptr_t'length + 1
            )
            port map(
                reset_n_i => reset_n_i,
                clock_i   => clock_i,
    
                out_data_o  => left_resync_wrap_and_wptr_s,
                out_ready_i => left_resync_wrap_and_wptr_ready_s,
                out_valid_o => left_resync_wrap_and_wptr_valid_s,
    
                in_data_i  => left_wrap_and_wptr_s,
                in_valid_i => left_wrap_and_wptr_valid_s,
                in_ready_o => left_wrap_and_wptr_ready_s
            );

            gray_rptr_encoding: nsl_clocking.interdomain.interdomain_counter
            generic map(
              data_width_c => right_rptr_s'length,
              input_is_gray_c => false,
              output_is_gray_c => true
              )
            port map(
              clock_in_i => clock_i(1),
              clock_out_i => clock_i(0),
              data_i => right_rptr_s,
              data_o => right_rptr_gray_s
              );

            resync_rptr : nsl_math.gray.gray_decoder_pipelined
            generic map(
                data_width_c  => ptr_t'length + 1,
                cycle_count_c => (ptr_t'length + 3) / 4
            )
            port map(
                clock_i  => clock_i(0),
                gray_i   => std_ulogic_vector(right_rptr_gray_s),
                binary_o => right_wrap_and_rptr_bin_s
            );
    
            right_rptr_wrap_s <= right_wrap_and_rptr_bin_s(right_wrap_and_rptr_bin_s'left);
            right_rptr_resync_s <= right_wrap_and_rptr_bin_s(right_wrap_and_rptr_bin_s'left - 1 downto 0);

        end generate;

        sync: if is_synchronous generate
        begin
            reset_n_s(0) <= reset_n_i;

            wptr: nsl_clocking.intradomain.intradomain_multi_reg
            generic map(
              data_width_c => ptr_t'length + 1
              )
            port map(
              clock_i => clock_i(0),
              data_i => std_ulogic_vector(right_rptr_s),
              unsigned(data_o) => right_rptr_gray_s
              );
      
          rptr: nsl_clocking.intradomain.intradomain_multi_reg
            generic map(
              data_width_c => ptr_t'length + 1
              )
            port map(
              clock_i => clock_i(0),
              data_i => std_ulogic_vector(right_rptr_gray_s),
              unsigned(data_o) => right_wrap_and_rptr_bin_s
              );
        end generate;
    
    end block;

    ram : nsl_memory.ram.ram_2p_r_w
    generic map(
        addr_size_c   => mem_ptr_t'length,
        data_size_c   => data_fifo_word_t'length,
        clock_count_c => clock_count_c
    )
    port map(
        clock_i => clock_i,

        write_address_i => write_ram_s.ptr,
        write_en_i      => write_ram_s.enable,
        write_data_i    => write_ram_s.data,

        read_address_i => read_ram_s.read_ptr,
        read_en_i      => read_ram_s.read_enable,
        read_data_o    => read_ram_s.read_data
    );

    read_block : block
        type out_left_data_t is (
            OUT_RESET,
            OUT_READ_DATA
        );

        type regs_t is record
            out_state : out_left_data_t;
            -- read pointer
            rptr : ptr_t;
            -- remote committed wptr
            remote_wptr : ptr_t;
            remote_wrap : std_ulogic;

            wptr_wrap : std_ulogic;
        end record;
        
        signal r, rin : regs_t;

    begin
        streamer: nsl_memory.streamer.memory_streamer
        generic map(
            addr_width_c => mem_ptr_t'length,
            data_width_c => data_fifo_word_t'length,
            memory_latency_c => 1
            )
        port map(
            clock_i => clock_i(1),
            reset_n_i => reset_n_s(1),

            addr_valid_i => in_streamer_valid_s,
            addr_ready_o => out_streamer_ready_s,
            addr_i => unsigned(r.rptr),
            sideband_i => (others => '0'),

            data_valid_o => out_streamer_valid_s,
            data_ready_i => in_streamer_ready_s,
            data_o => out_stream_data_s,

            mem_enable_o => read_ram_s.read_enable,
            mem_address_o => read_ram_s.read_ptr,
            mem_data_i => read_ram_s.read_data
            );

        regs : process (reset_n_s, clock_i) is
        begin
            if rising_edge(clock_i(1)) then
                r <= rin;
            end if;
            if reset_n_s(1) = '0' then
                r.rptr <= to_ptr(0);
                r.remote_wptr <= to_ptr(0);
                r.out_state <= OUT_RESET;
                r.wptr_wrap <= '0';
                r.remote_wrap <= '0';
            end if;
        end process;

        left_resync_wrap_and_wptr_ready_s <= '1';

        read_transition : process (r, out_i, left_resync_wrap_and_wptr_valid_s, left_resync_wrap_and_wptr_ready_s, left_resync_wrap_and_wptr_s, out_streamer_ready_s, do_read_s) is
        begin
            rin <= r;

            case r.out_state is
                when OUT_RESET =>
                    rin.out_state <= OUT_READ_DATA;

                when OUT_READ_DATA =>
                    if do_read_s then
                        rin.rptr <= r.rptr + 1;
                        rin.wptr_wrap <= not r.wptr_wrap;
                    end if;

                when others =>
                    null;
            end case;

            if left_resync_wrap_and_wptr_valid_s = '1' and left_resync_wrap_and_wptr_ready_s ='1' then
                rin.remote_wptr <= unsigned(left_resync_wrap_and_wptr_s(left_resync_wrap_and_wptr_s'left - 1 downto 0));
                rin.remote_wrap <= std_ulogic(left_resync_wrap_and_wptr_s(left_resync_wrap_and_wptr_s'left));
            end if;
        end process;

        out_same_wrap_s <= r.wptr_wrap = r.remote_wrap;
        out_fifo_full_s <= (r.rptr = r.remote_wptr) and out_same_wrap_s;
        do_read_s <= not out_fifo_full_s and is_ready(config_c, out_i) and out_streamer_ready_s = '1';

        ram_reader_proc : process (r,do_read_s) is
        begin
            in_streamer_valid_s <= '0';
            right_rptr_s <= r.wptr_wrap & r.rptr;

            case r.out_state is
                when OUT_READ_DATA =>
                    in_streamer_valid_s <= to_logic(do_read_s);

                when others =>
                    null;

            end case;
        end process;

      end block;

      in_streamer_ready_s <= to_logic(is_ready(config_c, out_i));
      out_o <= transfer(cfg => config_c,
                        src => vector_unpack(config_c, fifo_elements_c, out_stream_data_s),
                        force_valid => true,
                        valid => (out_streamer_valid_s = '1')) when out_streamer_valid_s = '1' else transfer_defaults(config_c);

end architecture;
