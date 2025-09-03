library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_amba, nsl_math, nsl_logic;
use nsl_data.bytestream.all;
use nsl_amba.axi4_stream.all;
use nsl_amba.random_pkt_checker.all;
use nsl_data.crc.all;
use nsl_data.prbs.all;
use nsl_logic.bool.all;

entity random_pkt_validator is
  generic (
    mtu_c: integer := 1500;
    config_c: config_t;
    data_prbs_init: prbs_state := x"deadbee"&"111";
    data_prbs_poly: prbs_state := prbs31;
    header_crc_params_c: crc_params_t
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    --
    in_i : in master_t;
    in_o : out slave_t;
    --
    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of random_pkt_validator is

    constant header_config_c : buffer_config_t := buffer_config(config_c, HEADER_SIZE);
    constant max_nbr_data_cycle_l2 : integer := nsl_math.arith.log2(mtu_c/config_c.data_width);
    constant data_width_l2 : integer := nsl_math.arith.log2(config_c.data_width);
    constant stats_buf_config : buffer_config_t := buffer_config(config_c, STATS_SIZE);
    constant header_size_m1 : integer := HEADER_SIZE - 1;
    constant header_size_m_data_width : integer := HEADER_SIZE - config_c.data_width;


    type state_t is (
        ST_RESET,
        ST_HEADER_DEC,
        ST_REALIGN_BUF,
        ST_HEADER_STATS,
        ST_DATA,
        ST_DATA_STATS,
        ST_SEND_STATS,
        ST_BUFFER_BUILD        
        );

    type txer_stats_t is (
        TXER_IDLE,
        TXER_SEND_STATS
        ); 

    type regs_t is
        record
            state : state_t;
            txer : txer_stats_t;
            state_pkt_gen :  prbs_state(30 downto 0);
            pkt_size : unsigned(15 downto 0);
            rx_bytes : unsigned(15 downto 0);
            header_buf : buffer_t;
            stats : stats_t;
            stats_buf : buffer_t;
            needed_data_cycles : unsigned(15 downto 0);
            header : header_t;
            seq_num : unsigned(15 downto 0);
            realign_cnt : integer range 0 to header_config_c.data_width;
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
        r.txer <= TXER_IDLE;
        r.state_pkt_gen <= data_prbs_init;
        r.pkt_size <= (others => '0');
        r.header_buf <= reset(header_config_c);
        r.stats_buf <= reset(stats_buf_config);
        r.needed_data_cycles <= (others => '0');
        r.rx_bytes <= (others => '0');
        r.seq_num <= (others => '0');
        r.stats.stats_seqnum <= (others => '0');
        r.stats.stats_pkt_size <= (others => '0');
        r.stats.stats_header_valid <= true;
        r.stats.stats_payload_valid <= true;
        r.stats.stats_index_data_ko <= (others => '0');
        r.realign_cnt <= 0;
      end if;
    end process;

    rx_process: process(r, rin, in_i)
        variable header, next_header : header_t;
        variable next_header_byte_string,header_byte_string : byte_string(0 to HEADER_SIZE-1);
        variable header_valid_v : boolean;
        variable payload_byte_ref_v : byte_string(0 to config_c.data_width -1);
        variable header_valid_vector_v : std_ulogic_vector(3 downto 0);
    begin
        rin <= r;

        header := header_unpack(bytes(header_config_c,r.header_buf), to_integer(r.rx_bytes));

        next_header_byte_string := bytes(header_config_c,shift(header_config_c, r.header_buf, in_i));
        header_byte_string := bytes(header_config_c,r.header_buf);

        payload_byte_ref_v := prbs_byte_string(r.state_pkt_gen, 
                                           data_prbs_poly,
                                           config_c.data_width);


        case r.state is

            when ST_RESET =>
                rin.state <= ST_HEADER_DEC;

            when ST_HEADER_DEC =>
                if is_valid(config_c, in_i) then
                    rin.header_buf <= shift(header_config_c, r.header_buf, in_i);
                    rin.rx_bytes <= r.rx_bytes + count_valid_bytes(keep(config_c, in_i));
                    if is_last(header_config_c, r.header_buf) or is_last(config_c, in_i) then
                        rin.seq_num <= r.seq_num + 1;
                        if should_align(header_config_c, r.header_buf,in_i) then
                            rin.realign_cnt <= header_config_c.beat_count - beat_count(header_config_c, rin.header_buf);
                            rin.state <= ST_REALIGN_BUF;
                        else
                            rin.state <= ST_HEADER_STATS;
                        end if;
                    end if;
                end if;

                when ST_REALIGN_BUF => 
                    if r.realign_cnt /= 0 then
                        rin.header_buf <= realign(header_config_c, r.header_buf);
                        rin.realign_cnt <= r.realign_cnt - 1;
                    else
                        rin.state <= ST_HEADER_STATS;
                    end if;

                when ST_HEADER_STATS =>
                    if r.rx_bytes <= header_size_m_data_width then
                        rin.state <= ST_BUFFER_BUILD;
                    else
                        rin.needed_data_cycles <= resize((header.pkt_size srl data_width_l2), r.needed_data_cycles'length);
                        rin.state <= ST_DATA;
                    end if;
                    rin.header <= header;
                    rin.stats.stats_seqnum <= header.seq_num;
                    rin.stats.stats_pkt_size <= header.pkt_size;
                    rin.stats.stats_header_valid <= is_header_valid(r.rx_bytes,
                                                                    header,
                                                                    r.seq_num,
                                                                    header_crc_params_c);

                when ST_DATA => 
                    if is_valid(config_c, in_i) then
                        rin.stats.stats_payload_valid <= true;
                        rin.rx_bytes <= r.rx_bytes + count_valid_bytes(keep(config_c, in_i));
                        rin.state_pkt_gen <= prbs_forward(r.state_pkt_gen, 
                                                        data_prbs_poly,
                                                        config_c.data_width);
                        --
                        if payload_byte_ref_v /= bytes(config_c, in_i) then
                            rin.stats.stats_payload_valid <= false;
                            rin.stats.stats_index_data_ko <= r.rx_bytes + count_valid_bytes(keep(config_c, in_i));
                        end if;
                        --
                        if is_last(config_c, in_i) then
                            rin.state <= ST_DATA_STATS;
                        end if;
                    end if;


                when ST_DATA_STATS =>
                    rin.state <= ST_BUFFER_BUILD;
                    --
                    if r.rx_bytes /= header.pkt_size then
                        rin.stats.stats_payload_valid <= false;
                    end if;
     
                when ST_BUFFER_BUILD => 
                    rin.stats_buf <= reset(stats_buf_config,stats_pack(r.stats));
                    if r.txer = TXER_IDLE then
                        rin.state <= ST_SEND_STATS;
                    end if;
                
                when ST_SEND_STATS =>
                    if r.txer = TXER_IDLE then
                        rin.header_buf <= reset(header_config_c);
                        rin.rx_bytes <= (others => '0');
                        rin.state <= ST_HEADER_DEC;
                    end if;

            when others => 
        end case;

        case r.txer is 
            when TXER_IDLE =>
                if r.state = ST_SEND_STATS then
                    rin.txer <= TXER_SEND_STATS;
                end if;

            when TXER_SEND_STATS =>
                if is_ready(config_c, out_i) then
                    rin.stats_buf <= shift(stats_buf_config, r.stats_buf);
                    if is_last(stats_buf_config, r.stats_buf) then
                        rin.txer <= TXER_IDLE;
                    end if;
                end if;

        end case;
    end process;

    in_o <= accept(config_c, r.state /= ST_SEND_STATS and 
                             r.state /= ST_BUFFER_BUILD and 
                             r.state /= ST_REALIGN_BUF and 
                             r.state /= ST_HEADER_STATS and 
                             r.state /= ST_DATA_STATS);

    proc_txer: process(r, in_i)
    begin
        out_o <= transfer_defaults(config_c);
        case r.txer is 
            when TXER_SEND_STATS => 
                out_o <= transfer(config_c,
                                  src => next_beat(stats_buf_config, r.stats_buf, last => false),
                                  force_last => true,
                                  last => is_last(stats_buf_config, r.stats_buf));  
            when others => 
        end case;
    end process;

    assert_proc: process(r,in_i, clock_i)
        variable header_buf, next_header : header_t;
        variable next_header_byte_string,header_byte_sring : byte_string(0 to HEADER_SIZE-1);
    begin 

        header_buf := header_unpack(bytes(header_config_c,r.header_buf), to_integer(r.rx_bytes));

        next_header_byte_string := bytes(header_config_c,shift(header_config_c, r.header_buf, in_i));
        header_byte_sring := bytes(header_config_c,r.header_buf);

        case r.state is
            when ST_HEADER_DEC => 

            when ST_DATA =>


            when ST_SEND_STATS => 
                assert r.stats.stats_header_valid and r.stats.stats_payload_valid
                report "MUST BE VALID"
                severity failure;

            when others =>

        end case;
    end process;

end architecture;
