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

entity random_cmd_generator is
  generic (
    mtu_c: integer := 1500;
    header_prbs_init: prbs_state := x"d"&"111";
    header_prbs_poly: prbs_state := prbs7;
    config_c : config_t := config(2, last => true)
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    --
    enable_i : in std_ulogic;
    --
    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of random_cmd_generator is
    constant mtu_l2 : integer := nsl_math.arith.log2(mtu_c);
    constant cmd_buf_config : buffer_config_t := buffer_config(config_c, CMD_SIZE);

    type state_t is (
        ST_RESET,
        ST_GEN_CMD,
        ST_SEND_CMD
        );

    type regs_t is
        record
            state : state_t;
            pkt_size : unsigned(15 downto 0);
            state_size_gen : prbs_state(6 downto 0);
            cmd_buf : buffer_t;
            seq_num : unsigned(15 downto 0);
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
        r.pkt_size <= (others => '0');
        r.state_size_gen <= header_prbs_init;
        r.cmd_buf <= reset(cmd_buf_config);
        r.seq_num <= x"0001";
      end if;
    end process;

      gen_cmd_process: process(r, out_i, enable_i)
        variable pkt_size_v : unsigned(15 downto 0);
    begin

        rin <= r;

        --pkt_size_v:= to_unsigned(3, pkt_size_v'length);
        pkt_size_v := resize(max(to_unsigned(1,mtu_l2),
                        unsigned(prbs_bit_string(
                        r.state_size_gen, 
                        header_prbs_poly,
                        mtu_l2-1))),pkt_size_v'length); 

        case r.state is

            when ST_RESET =>
                rin.state <= ST_GEN_CMD;        
            
            when ST_GEN_CMD =>
                if to_boolean(enable_i) then
                    if is_ready(config_c, out_i) then
                        rin.seq_num <= r.seq_num + 1;
                        rin.pkt_size <= pkt_size_v;
                        rin.state <= ST_SEND_CMD;
                        rin.state_size_gen <= prbs_forward(r.state_size_gen,
                                                           header_prbs_poly,
                                                           config_c.data_width);
                        rin.cmd_buf <= reset(cmd_buf_config, 
                                             to_le(r.seq_num & pkt_size_v));
                    end if;
                end if;

            when ST_SEND_CMD => 
                if is_ready(config_c, out_i) then
                    rin.cmd_buf <= shift(cmd_buf_config, r.cmd_buf);
                    if is_last(cmd_buf_config, r.cmd_buf) then
                        rin.state <= ST_GEN_CMD;
                    end if;
                end if;
            when others =>
        end case;
    end process;
    
    txer_proc: process(r, out_i, enable_i) is
    begin
        out_o <= transfer_defaults(config_c);

        case r.state is
            when ST_SEND_CMD => 
                out_o <= transfer(config_c,
                                  src => next_beat(cmd_buf_config, r.cmd_buf));
            when others => 
        end case;
    end process;

end architecture;
