library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_amba, nsl_math, nsl_logic;
use nsl_data.bytestream.all;
use nsl_amba.axi4_stream.all;
use nsl_amba.stream_traffic.all;
use nsl_data.crc.all;
use nsl_data.prbs.all;
use nsl_logic.bool.all;
use nsl_data.endian.all;

entity random_pkt_validator is
  generic (
    mtu_c: integer := 1500;
    config_c: config_t;
    data_prbs_init_c: prbs_state := x"deadbee"&"111";
    data_prbs_poly_c: prbs_state := prbs31
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    packet_i : in master_t;
    packet_o : out slave_t;

    stats_o : out master_t;
    stats_i : in slave_t    
    );
end entity;

architecture beh of random_pkt_validator is

    constant header_config_c : buffer_config_t := buffer_config(config_c, header_packed_t'length);
    constant stats_buf_config : buffer_config_t := buffer_config(config_c, STATS_SIZE);
    constant mtu_l2 : integer := nsl_math.arith.log2(mtu_c) + 1;
    constant stats_reset : stats_t := (
                                        stats_seqnum        => to_unsigned(0, 16),
                                        stats_pkt_size      => to_unsigned(0, 16),
                                        stats_header_valid  => true,
                                        stats_payload_valid => true,
                                        stats_index_data_ko => to_unsigned(0, 16)
                                    );
      
    type state_t is (
        ST_RESET,
        ST_HEADER_DEC,
        ST_REALIGN_BUF,
        ST_HEADER_STATS,
        ST_DATA,
        ST_SEND_STATS,      
        ST_IGNORE
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
            rx_bytes : unsigned(mtu_l2 - 1 downto 0);
            header_buf : buffer_t;
            stats : stats_t;
            stats_buf : buffer_t;
            cmd : cmd_t;
            rx_cmd : cmd_t;
            was_last_beat : boolean;
            header_crc : crc_state_t;
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
        r.state_pkt_gen <= data_prbs_init_c;
        r.header_buf <= reset(header_config_c);
        r.stats_buf <= reset(stats_buf_config);
        r.rx_bytes <= (others => '0');
        r.stats.stats_seqnum <= (others => '0');
        r.stats.stats_pkt_size <= (others => '0');
        r.stats.stats_header_valid <= true;
        r.stats.stats_payload_valid <= true;
        r.stats.stats_index_data_ko <= (others => '0');
        r.was_last_beat <= false;
        r.cmd.seq_num <= (others => '0');
        r.header_crc <= crc_init(header_crc_params_c);
      end if;
    end process;

    rx_process: process(r, packet_i, stats_i, rin)
        variable header_v : header_t;
        variable payload_byte_ref_v : byte_string(0 to config_c.data_width -1);
        variable header_byte_ref_v : header_packed_t;
    begin
        rin <= r;
       
        header_v := header_unpack(bytes(header_config_c,r.header_buf), to_integer(r.rx_bytes));
        header_byte_ref_v := header_pack(header_from_cmd(r.cmd));

        payload_byte_ref_v := prbs_byte_string(r.state_pkt_gen, 
                                           data_prbs_poly_c,
                                           config_c.data_width);

        case r.state is

            when ST_RESET =>
                rin.state <= ST_HEADER_DEC;

            when ST_HEADER_DEC =>
                if is_valid(config_c, packet_i) then
                    rin.header_buf <= shift(header_config_c, r.header_buf, packet_i);
                    rin.rx_bytes <= r.rx_bytes + count_valid_bytes(keep(config_c, packet_i));
                    rin.stats.stats_payload_valid <= true;
                    rin.stats.stats_header_valid <= true;
                    rin.header_crc <= crc_update(header_crc_params_c, 
                                        r.header_crc, 
                                        bytes(config_c, packet_i));
                    if is_last(header_config_c, r.header_buf) or is_last(config_c, packet_i) then
                        rin.was_last_beat <= is_last(config_c, packet_i);
                        rin.cmd.pkt_size <= resize(r.rx_bytes + count_valid_bytes(keep(config_c, packet_i)),r.cmd.pkt_size'length);
                        if should_align(header_config_c, r.header_buf,packet_i) then
                            rin.state <= ST_REALIGN_BUF;
                        else
                            rin.state <= ST_HEADER_STATS;
                        end if;
                    end if;
                end if;

                when ST_REALIGN_BUF => 
                    rin.header_buf <= realign(header_config_c, r.header_buf);
                    if is_last(header_config_c, r.header_buf) then
                        rin.state <= ST_HEADER_STATS;
                    end if;

                when ST_HEADER_STATS =>
                    rin.rx_cmd <= header_v.cmd;
                    if not r.was_last_beat then
                        if crc_is_valid(header_crc_params_c, r.header_crc) then
                            rin.state <= ST_DATA;
                            rin.state_pkt_gen <= prbs_forward(data_prbs_init_c, data_prbs_poly_c,
                                                    std_ulogic_vector(from_le(cmd_pack(header_unpack(bytes(header_config_c, r.header_buf),
                                                                                                           header_packed_t'length).cmd))));
                        else
                            rin.stats.stats_header_valid <= false;
                            rin.stats.stats_index_data_ko <= to_unsigned(0,r.stats.stats_index_data_ko'length);
                            rin.state <= ST_IGNORE;
                        end if;
                        --
                        if header_v.cmd.seq_num /= r.cmd.seq_num then
                            rin.stats.stats_header_valid <= false;
                            rin.stats.stats_index_data_ko <= to_unsigned(0,r.stats.stats_index_data_ko'length);
                            rin.state <= ST_IGNORE;
                        end if;
                    else
                        for i in 0 to header_packed_t'length - 1 loop
                            if i < to_integer(r.rx_bytes) then
                                if header_byte_ref_v(i) /= bytes(header_config_c,r.header_buf)(i) then
                                    rin.stats.stats_header_valid <= false;
                                    rin.stats.stats_index_data_ko <= to_unsigned(0,r.stats.stats_index_data_ko'length);
                                    --
                                    exit;
                                end if;
                            else
                                exit;
                            end if;
                        end loop;
                        rin.state <= ST_SEND_STATS;
                    end if;
                    --
                    rin.header_crc <= crc_init(header_crc_params_c);
                    rin.cmd.seq_num <= header_v.cmd.seq_num;
                    rin.stats.stats_seqnum <= header_v.cmd.seq_num;
                    rin.stats.stats_pkt_size <= header_v.cmd.pkt_size;

                when ST_DATA => 
                    if is_valid(config_c, packet_i) then
                        rin.stats.stats_seqnum <= r.cmd.seq_num;
                        rin.rx_bytes <= r.rx_bytes + count_valid_bytes(keep(config_c, packet_i));
                        rin.state_pkt_gen <= prbs_forward(r.state_pkt_gen, 
                                                          data_prbs_poly_c,
                                                          config_c.data_width * 8);
                        --
                        if r.stats.stats_payload_valid then
                            for i in payload_byte_ref_v'range loop
                                if keep(config_c, packet_i)(i) = '1' then
                                    if payload_byte_ref_v(i) /= bytes(config_c, packet_i)(i) then
                                        rin.stats.stats_payload_valid <= false;
                                        rin.stats.stats_index_data_ko <= resize(r.rx_bytes + i, r.stats.stats_index_data_ko'length);   
                                    end if;
                                end if;
                            end loop;
                        end if;
                        --
                        if is_last(config_c, packet_i) then
                            rin.state <= ST_SEND_STATS;
                            if r.stats.stats_payload_valid then
                                if r.rx_cmd.pkt_size /= r.rx_bytes + count_valid_bytes(keep(config_c, packet_i)) then
                                    rin.stats.stats_payload_valid <= false;
                                    rin.stats.stats_index_data_ko <= to_unsigned(10, r.stats.stats_index_data_ko'length); -- size header field
                                end if;
                            end if;
                        end if;
                    end if;    

                when ST_SEND_STATS => 
                    if r.txer = TXER_IDLE then
                        rin.cmd.seq_num <= r.cmd.seq_num + 1;
                        rin.stats_buf <= reset(stats_buf_config,stats_pack(r.stats));
                        rin.header_buf <= reset(header_config_c);
                        rin.rx_bytes <= (others => '0');
                        rin.stats <= stats_reset;
                        rin.state <= ST_HEADER_DEC;
                    end if;      
                    
                when ST_IGNORE => 
                    if is_valid(config_c, packet_i) then
                        if is_last(config_c, packet_i) then
                            rin.state <= ST_SEND_STATS;
                        end if;
                    end if;

            when others => 
        end case;

        case r.txer is 
            when TXER_IDLE =>
                if r.state = ST_SEND_STATS then
                    rin.txer <= TXER_SEND_STATS;
                end if;

            when TXER_SEND_STATS =>
                if is_ready(config_c, stats_i) then
                    rin.stats_buf <= shift(stats_buf_config, r.stats_buf);
                    if is_last(stats_buf_config, r.stats_buf) then
                        rin.txer <= TXER_IDLE;
                    end if;
                end if;

        end case;
    end process;

    packet_o <= accept(config_c, r.state /= ST_SEND_STATS and 
                             r.state /= ST_REALIGN_BUF and 
                             r.state /= ST_HEADER_STATS);

    proc_txer: process(r, packet_i)
    begin
        stats_o <= transfer_defaults(config_c);
        case r.txer is 
            when TXER_SEND_STATS => 
              stats_o <= transfer(config_c,
                                  src => next_beat(stats_buf_config, r.stats_buf, last => false),
                                  force_last => true,
                                  last => is_last(stats_buf_config, r.stats_buf));  
          when others => 
        end case;
    end process;
end architecture;
