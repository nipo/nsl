library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_amba, nsl_math, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_data.prbs.all;
use nsl_amba.random_pkt_checker.all;

entity random_cmd_generator is
  generic (
    mtu_c: integer := 1500;
    header_prbs_init_c: prbs_state := x"d"&"111";
    header_prbs_poly_c: prbs_state := prbs7;
    config_c : config_t := config(2, last => true);
    min_pkt_size : integer := 1
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
    constant cmd_buf_config : buffer_config_t := buffer_config(config_c, cmd_packed_t'length);

    type state_t is (
        ST_RESET,
        ST_GEN_CMD,
        ST_SEND_CMD
        );

    type regs_t is
        record
            state : state_t;
            cmd: cmd_t;
            state_size_gen : prbs_state(header_prbs_init_c'range);
            cmd_buf : buffer_t;
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
        r.state_size_gen <= header_prbs_init_c;
        r.cmd.seq_num <= (others => '0');
        r.cmd.pkt_size <= (others => '0');
      end if;
    end process;

    gen_cmd_process: process(r, out_i, enable_i)
    begin

        rin <= r;

        case r.state is
            when ST_RESET =>
                rin.state <= ST_GEN_CMD;        
            
            when ST_GEN_CMD =>
                if enable_i = '1' then
                    rin.cmd.pkt_size <= resize(unsigned(prbs_bit_string(r.state_size_gen, header_prbs_poly_c, mtu_l2)), r.cmd.pkt_size'length);
                    rin.state_size_gen <= prbs_forward(r.state_size_gen, header_prbs_poly_c, mtu_l2);

                    if r.cmd.pkt_size >= min_pkt_size and r.cmd.pkt_size <= mtu_c then
                        rin.state <= ST_SEND_CMD;
                        rin.cmd_buf <= reset(cmd_buf_config, cmd_pack(r.cmd));
                        rin.cmd.seq_num <= r.cmd.seq_num + 1;
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
    
    txer_proc: process(r) is
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
