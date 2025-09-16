library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_amba, nsl_math, nsl_logic;
use nsl_data.bytestream.all;
use nsl_amba.axi4_stream.all;
use nsl_data.crc.all;
use nsl_data.prbs.all;
use nsl_logic.bool.all;
use nsl_amba.random_pkt_checker.all;
use nsl_data.endian.all;

entity random_pkt_generator is
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

architecture beh of random_pkt_generator is

    constant header_size : integer := 8;
    constant max_nbr_data_cycle_l2 : integer := nsl_math.arith.log2(mtu_c/config_c.data_width);
    constant header_config_s8_c : buffer_config_t := buffer_config(config_c, header_size);
    constant header_padding : integer := if_else(config_c.data_width > header_size,
                                                 config_c.data_width - header_size,
                                                 0);
    constant header_size_with_padding : integer := header_size + header_padding;
    constant padding_byte_string : byte_string(0 to config_c.data_width-1) := (others => (others =>'0'));
    constant cmd_buf_config : buffer_config_t := buffer_config(config_c, CMD_SIZE);
    constant data_width_l2 : integer := nsl_math.arith.log2(config_c.data_width);

    type state_t is (
        ST_RESET,
        ST_CMD_DEC,
        ST_BUILD_HEADER,
        ST_SEND_HEADER,
        ST_SEND_PAYLOAD,
        ST_IGNORE
        );

    function keep_generator(config_c: config_t; data_remainder : integer; is_last_word : boolean) return std_ulogic_vector is
        variable ret : std_ulogic_vector(0 to config_c.data_width-1) := (others => '1');
    begin 
        if is_last_word then
            if data_remainder /= 0 then
                ret(data_remainder to ret'right) := (others => '0');
            end if;
        end if;
        return ret;
    end function;

    type regs_t is
        record
            state : state_t;
            state_pkt_gen : prbs_state(30 downto 0);
            pkt_size : unsigned(15 downto 0);
            seq_num : unsigned(15 downto 0);
            header_config : buffer_config_t;
            header : buffer_t;
            cmd_buf : buffer_t;
            transaction_cycles_nbr : unsigned(max_nbr_data_cycle_l2-1 downto 0);
            filler_header_crc  : crc_state_t;
            data_remainder : integer range 0 to config_c.data_width;
            needed_data_cycles_m1 : unsigned(max_nbr_data_cycle_l2-1 downto 0);
            header_keep : std_ulogic_vector(config_c.data_width-1 downto 0);
            --
            byte_debug : byte_string(0 to 3);
            header_debug : header_t;
            crc_byte_debug : byte_string(0 to 1);
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
        r.state_pkt_gen <= data_prbs_init;
        r.pkt_size <= (others => '0');
        r.seq_num <= x"0001";
        r.header_config <= header_config_s8_c;
        r.header <= reset(header_config_s8_c);
        r.transaction_cycles_nbr <=(others => '0');
        r.filler_header_crc <= crc_init(header_crc_params_c);
        r.needed_data_cycles_m1 <= (others => '0');
        r.header_keep <= (others => '1');
        r.cmd_buf <= reset(cmd_buf_config);
        r.byte_debug <= (others => (others => '0'));
      end if;
    end process;

    gen_process: process(r, in_i, out_i)
        variable payload_byte_v : byte_string(0 to config_c.data_width -1);
        variable cmd_v : cmd_t;
    begin

        rin <= r;

        cmd_v := cmd_unpack(bytes(cmd_buf_config, shift(cmd_buf_config, r.cmd_buf, in_i)));

        payload_byte_v := prbs_byte_string(
                            r.state_pkt_gen, 
                            data_prbs_poly,
                            config_c.data_width);

        case r.state is
            when ST_RESET =>
                rin.state <= ST_CMD_DEC;

            when ST_CMD_DEC => 
                if is_valid(config_c, in_i) then
                    rin.cmd_buf <= shift(cmd_buf_config, r.cmd_buf, in_i);
                    if is_last(cmd_buf_config, r.cmd_buf) then
                        rin.byte_debug <= bytes(cmd_buf_config, shift(cmd_buf_config, r.cmd_buf, in_i));
                        rin.seq_num <= cmd_v.cmd_seqnum;
                        rin.pkt_size <= cmd_v.cmd_pkt_size;
                        rin.data_remainder <= to_integer(cmd_v.cmd_pkt_size(data_width_l2 -1 downto 0));
                        rin.header_config <= header_config_s8_c;
                        rin.transaction_cycles_nbr <= (others => '0');
                        rin.state <= ST_BUILD_HEADER;
                        rin.filler_header_crc <= crc_init(header_crc_params_c);
                    end if;
                end if;

            when ST_BUILD_HEADER => 
                rin.header <= reset(r.header_config, 
                                    header_pack(r.seq_num,
                                                r.pkt_size,
                                                crc_init(header_crc_params_c),
                                                header_crc_params_c));
                rin.header_debug <= header_unpack(
                                        header_pack(r.seq_num,
                                                  r.pkt_size,
                                                  crc_init(header_crc_params_c),
                                                  header_crc_params_c),
                                        HEADER_SIZE);

                if r.data_remainder /= 0 then
                    rin.needed_data_cycles_m1 <= resize((r.pkt_size srl data_width_l2), r.needed_data_cycles_m1'length);
                else
                    rin.needed_data_cycles_m1 <= resize((r.pkt_size srl data_width_l2) - 1, r.needed_data_cycles_m1'length);
                end if;
                rin.state <= ST_SEND_HEADER;
                                              
            when ST_SEND_HEADER =>   
                if is_ready(config_c, out_i) then
                    rin.header <= shift(r.header_config, r.header);
                    rin.transaction_cycles_nbr <= r.transaction_cycles_nbr + 1;
                    rin.filler_header_crc <= crc_update(header_crc_params_c, 
                                                        r.filler_header_crc, 
                                                        bytes(config_c,in_i));

                    if is_last(r.header_config, r.header) or (r.transaction_cycles_nbr >= r.needed_data_cycles_m1) then
                        -- pkt size if random beetween 1 and mtu including the header.
                        -- pkt_size < HEADER_SIZE means we only send parts of header and
                        -- no data payload
                        if r.pkt_size > HEADER_SIZE then 
                                rin.state <= ST_SEND_PAYLOAD;
                            else
                                rin.state <= ST_CMD_DEC;
                            end if;
                        end if;
                end if;

            when ST_SEND_PAYLOAD => 
                if is_ready(config_c, out_i) then
                    rin.transaction_cycles_nbr <= r.transaction_cycles_nbr + 1;

                    rin.state_pkt_gen <= prbs_forward(r.state_pkt_gen, 
                                                      data_prbs_poly,
                                                      config_c.data_width * 8);
                    if r.transaction_cycles_nbr = r.needed_data_cycles_m1 then

                        if  r.data_remainder /= 0 then
                            rin.state_pkt_gen <= prbs_forward(r.state_pkt_gen, 
                                                                data_prbs_poly,
                                                                r.data_remainder * 8);
                        end if;
                        rin.state <= ST_CMD_DEC;
                    end if;
                end if;

            when others => 
        end case;
    end process;

    proc_txer: process(r)
        variable payload_byte_v : byte_string(0 to config_c.data_width -1);
        variable is_last_word : boolean := false;
    begin

        is_last_word := (is_last(r.header_config, r.header) and
                        r.pkt_size <= HEADER_SIZE) or
                        (r.transaction_cycles_nbr >= r.needed_data_cycles_m1);

        out_o <= transfer_defaults(config_c);

        payload_byte_v :=   prbs_byte_string(
                                r.state_pkt_gen, 
                                data_prbs_poly, 
                                config_c.data_width);

        case r.state is
            when ST_SEND_HEADER => 
                out_o <=  transfer(config_c,
                                  bytes => r.header.data(0 to config_c.data_width-1),
                                  keep => keep_generator(config_c, r.data_remainder, is_last_word),
                                  valid => true,
                                  last => is_last_word);
                                
            when ST_SEND_PAYLOAD => 
                out_o <= transfer(config_c,
                                  bytes => payload_byte_v,
                                  keep => keep_generator(config_c, r.data_remainder, is_last_word),
                                  last => is_last_word);

            when others =>
        end case;
    end process;
    
    in_o <=  accept(config_c, r.state = ST_CMD_DEC);

    assert_proc: process(r)
    begin 

        case r.state is

            when ST_SEND_HEADER => 
                assert to_integer(r.pkt_size) <= mtu_c report "ERROR: Size cannot be supp to mtu" severity failure;


            when others =>

        end case;
    end process;

end architecture;
