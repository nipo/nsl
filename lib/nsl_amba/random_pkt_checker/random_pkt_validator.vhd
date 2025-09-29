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
    out_i : in slave_t;
    -- 
    toggle_o : out std_ulogic
    );
end entity;

architecture beh of random_pkt_validator is

    constant header_config_c : buffer_config_t := buffer_config(config_c, HEADER_SIZE);
    constant stats_buf_config : buffer_config_t := buffer_config(config_c, STATS_SIZE);
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
        ST_SEND_STATS_NO_EOP,
        ST_SEND_STATS_EOP,        
        ST_RESET_STATS,
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
            rx_bytes : unsigned(15 downto 0);
            header_buf : buffer_t;
            stats : stats_t;
            stats_buf : buffer_t;
            header : header_t;
            seq_num : unsigned(15 downto 0);
            realign_cnt : integer range 0 to header_config_c.data_width;
            was_last_beat : boolean;
            last_was_seq_num_err : boolean;
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
        r.header_buf <= reset(header_config_c);
        r.stats_buf <= reset(stats_buf_config);
        r.rx_bytes <= (others => '0');
        r.seq_num <= (others => '0');
        r.stats.stats_seqnum <= (others => '0');
        r.stats.stats_pkt_size <= (others => '0');
        r.stats.stats_header_valid <= true;
        r.stats.stats_payload_valid <= true;
        r.stats.stats_index_data_ko <= (others => '0');
        r.realign_cnt <= 0;
        r.was_last_beat <= false;
        r.last_was_seq_num_err <= false;
      end if;
    end process;

    rx_process: process(r, in_i, out_i, rin)
        variable header : header_t;
        variable payload_byte_ref_v : byte_string(0 to config_c.data_width -1);
        variable header_byte_ref_v, rx_header_v : byte_string(0 to HEADER_SIZE-1);
        variable send_stats_trigger_v : boolean;
    begin
        rin <= r;

        header := header_unpack(bytes(header_config_c,r.header_buf), to_integer(r.rx_bytes));
        rx_header_v := bytes(header_config_c,r.header_buf);

        header_byte_ref_v := ref_header(if_else(r.was_last_beat, r.rx_bytes, header.pkt_size),
                                        header,
                                        r.seq_num,
                                        header_crc_params_c);

        payload_byte_ref_v := prbs_byte_string(r.state_pkt_gen, 
                                           data_prbs_poly,
                                           config_c.data_width);

        send_stats_trigger_v := false;

        case r.state is

            when ST_RESET =>
                rin.state <= ST_HEADER_DEC;

            when ST_HEADER_DEC =>
                if is_valid(config_c, in_i) then
                    rin.header_buf <= shift(header_config_c, r.header_buf, in_i);
                    rin.rx_bytes <= r.rx_bytes + count_valid_bytes(keep(config_c, in_i));
                    rin.stats.stats_payload_valid <= true;
                    if is_last(header_config_c, r.header_buf) or is_last(config_c, in_i) then
                        rin.seq_num <= r.seq_num + 1;
                        rin.was_last_beat <= is_last(config_c, in_i);
                        if should_align(header_config_c, r.header_buf,in_i) then
                            rin.realign_cnt <= header_config_c.beat_count - beat_count(header_config_c, shift(header_config_c, r.header_buf, in_i));
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
                    if r.was_last_beat then
                        rin.state <= ST_RESET_STATS;
                    else
                        rin.state <= ST_DATA;
                        rin.state_pkt_gen <= prbs_state(to_slv(header_byte_ref_v)(r.state_pkt_gen'length - 1 downto 0));
                    end if;
                    --
                    for i in 0 to HEADER_SIZE - 1 loop
                            if i < to_integer(r.rx_bytes) then
                                if header_byte_ref_v(i) /= rx_header_v(i) then
                                    send_stats_trigger_v := true;
                                    rin.stats.stats_index_data_ko <= to_unsigned(i,r.stats.stats_index_data_ko'length);
                                    --
                                    exit;
                                end if;
                            else
                                exit;
                            end if;
                    end loop;
                    -- 
                    if send_stats_trigger_v then
                        rin.stats.stats_header_valid <= false;
                        if r.was_last_beat then
                            rin.state <= ST_SEND_STATS_EOP;
                        else
                            rin.state <= ST_SEND_STATS_NO_EOP;
                        end if;
                    end if;
                    --
                    if r.last_was_seq_num_err then
                        if not (rin.stats.stats_index_data_ko = 0 or rin.stats.stats_index_data_ko = 1) then
                            rin.last_was_seq_num_err <= false;
                            if r.seq_num /= header.seq_num then
                                rin.seq_num <= header.seq_num;
                            end if;
                        end if;
                    end if;
                    rin.was_last_beat <= false;
                    rin.header <= header;
                    rin.stats.stats_seqnum <= header.seq_num;
                    rin.stats.stats_pkt_size <= header.pkt_size;
                    
                when ST_DATA => 
                    if is_valid(config_c, in_i) then
                        rin.rx_bytes <= r.rx_bytes + count_valid_bytes(keep(config_c, in_i));
                        rin.state_pkt_gen <= prbs_forward(r.state_pkt_gen, 
                                                        data_prbs_poly,
                                                        config_c.data_width * 8);
                        --
                        for i in payload_byte_ref_v'range loop
                            if keep(config_c, in_i)(i) = '1' then
                                if payload_byte_ref_v(i) /= bytes(config_c, in_i)(i) then
                                    rin.stats.stats_payload_valid <= false;
                                    rin.stats.stats_index_data_ko <= r.rx_bytes + i;   
                                    send_stats_trigger_v := true;                           
                                  end if;
                            end if;
                          end loop;
                        --
                        if is_last(config_c, in_i) then
                            rin.state <= ST_RESET_STATS;
                            if header.pkt_size /= r.rx_bytes + count_valid_bytes(keep(config_c, in_i)) then
                                rin.stats.stats_payload_valid <= false;
                                rin.stats.stats_index_data_ko <= to_unsigned(10, r.stats.stats_index_data_ko'length); -- size header field
                                send_stats_trigger_v := true;                           
                            end if;
                        end if;
                        --
                        if send_stats_trigger_v then
                            rin.state <= ST_SEND_STATS_NO_EOP;
                            if is_last(config_c, in_i) then
                                rin.state <= ST_SEND_STATS_EOP;
                            end if;
                        end if;
                    end if;

                when ST_RESET_STATS => 
                    if r.txer = TXER_IDLE then
                        rin.stats_buf <= reset(stats_buf_config);
                        rin.header_buf <= reset(header_config_c);
                        rin.rx_bytes <= (others => '0');
                        rin.stats <= stats_reset;
                        rin.state <= ST_HEADER_DEC;
                    end if;

                when ST_SEND_STATS_NO_EOP => 
                    if r.txer = TXER_IDLE then
                        rin.stats_buf <= reset(stats_buf_config,stats_pack(r.stats));
                        rin.stats.stats_payload_valid <= true;
                        rin.state <= ST_DATA;
                        -- error in seqnum: could be a bitswap or pkt loss
                        if is_seqnum_corrupted(r.stats.stats_index_data_ko) then 
                            rin.last_was_seq_num_err <= true;
                        end if;
                        --
                        if is_seqnum_corrupted(r.stats.stats_index_data_ko) or is_rand_data_corrupted(r.stats.stats_index_data_ko) then
                            rin.state <= ST_IGNORE;
                        end if;
                    end if;         
     
                when ST_SEND_STATS_EOP => 
                    if r.txer = TXER_IDLE then
                        rin.stats_buf <= reset(stats_buf_config,stats_pack(r.stats));
                        rin.header_buf <= reset(header_config_c);
                        rin.rx_bytes <= (others => '0');
                        rin.stats <= stats_reset;
                        rin.state <= ST_HEADER_DEC;
                        -- error in seqnum: could be a bitswap or pkt loss
                        if r.stats.stats_index_data_ko = 0 or r.stats.stats_index_data_ko = 1 then 
                            rin.last_was_seq_num_err <= true;
                        end if;
                    end if;      
                    
                when ST_IGNORE => 
                    if is_valid(config_c, in_i) then
                        if is_last(config_c, in_i) then
                            rin.state <= ST_RESET_STATS;
                        end if;
                    end if;

            when others => 
        end case;

        case r.txer is 
            when TXER_IDLE =>
                if r.state = ST_SEND_STATS_EOP or r.state = ST_SEND_STATS_NO_EOP then
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

    in_o <= accept(config_c, r.state /= ST_SEND_STATS_NO_EOP and 
                             r.state /= ST_SEND_STATS_EOP and 
                             r.state /= ST_REALIGN_BUF and 
                             r.state /= ST_HEADER_STATS and 
                             r.state /= ST_RESET_STATS);

    toggle_o <= to_logic(r.state = ST_RESET_STATS and r.txer = TXER_IDLE and is_ready(config_c, out_i));

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
end architecture;
