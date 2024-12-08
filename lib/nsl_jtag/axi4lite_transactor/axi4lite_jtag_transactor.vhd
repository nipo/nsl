library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_jtag, nsl_data;
use nsl_jtag.ate.all;
use nsl_jtag.axi4lite_transactor.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

entity axi4lite_jtag_transactor is
  generic (
    prescaler_width_c : natural := 18;
    config_c : nsl_amba.axi4_mm.config_t
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic := '1';
    
    axi_i: in nsl_amba.axi4_mm.master_t;
    axi_o: out nsl_amba.axi4_mm.slave_t;

    jtag_o : out nsl_jtag.jtag.jtag_ate_o;
    jtag_i : in nsl_jtag.jtag.jtag_ate_i
    );
end entity;

architecture rtl of axi4lite_jtag_transactor is

  signal s_axi_write, s_axi_read, s_axi_read_done, s_axi_write_ready : std_ulogic;
  signal s_axi_addr : unsigned(config_c.address_width-1 downto config_c.data_bus_width_l2);
  signal s_axi_wdata : std_ulogic_vector(31 downto 0);
  signal s_axi_wbytes, s_axi_rbytes : byte_string(0 to 3);

  type state_e is (
    ST_RESET,
    ST_IDLE,
    ST_OP_CMD,
    ST_OP_DATA_OUT,
    ST_OP_DATA_IN,
    ST_READ_RSP
    );
  
  type regs_s is
  record
    state : state_e;
    data : std_ulogic_vector(31 downto 0);
    size_m1 : natural range 0 to 31;
    op : nsl_jtag.ate.ate_op;
    divisor : natural range 0 to 2 ** prescaler_width_c - 1;
  end record;

  signal r, rin : regs_s;

  signal s_ate_cmd_ready, s_ate_cmd_valid,
         s_ate_rsp_ready, s_ate_rsp_valid : std_ulogic;
  signal s_ate_rsp_data : std_ulogic_vector(31 downto 0);
  
begin

  axi_slave: nsl_amba.axi4_mm.axi4_mm_lite_slave
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      axi_i => axi_i,
      axi_o => axi_o,

      address_o => s_axi_addr,

      w_data_o => s_axi_wbytes,
      w_ready_i => s_axi_write_ready,
      w_valid_o => s_axi_write,

      r_data_i => s_axi_rbytes,
      r_ready_o => s_axi_read,
      r_valid_i => s_axi_read_done
      );

  s_axi_wdata <= std_ulogic_vector(from_le(s_axi_wbytes));
  s_axi_rbytes <= to_le(unsigned(r.data));

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r,
                      s_axi_write, s_axi_read, s_axi_addr, s_axi_wdata,
                      s_ate_cmd_ready, s_ate_rsp_valid, s_ate_rsp_data)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.divisor <= 2**prescaler_width_c-1;
 
      when ST_IDLE =>
        if s_axi_read = '1' then
          case to_integer(unsigned(s_axi_addr(7 downto 2))) is
            when JTAG_TRANSACTOR_REG_DIVISOR =>
              rin.data <= (others => '0');
              rin.data(prescaler_width_c-1 downto 0) <= std_ulogic_vector(to_unsigned(r.divisor, prescaler_width_c));
            when JTAG_TRANSACTOR_REG_SHIFT1 to JTAG_TRANSACTOR_REG_SHIFT32 =>
              null;
            when others =>
              null;
          end case;
          rin.state <= ST_READ_RSP;

        elsif s_axi_write = '1' then
          case to_integer(unsigned(s_axi_addr(7 downto 2))) is
            when JTAG_TRANSACTOR_REG_DIVISOR =>
              rin.divisor <= to_integer(unsigned(s_axi_wdata(prescaler_width_c-1 downto 0)));
              rin.data <= (others => '-');
            when JTAG_TRANSACTOR_REG_RESET =>
              rin.state <= ST_OP_CMD;
              rin.op <= ATE_OP_RESET;
              rin.size_m1 <= to_integer(unsigned(s_axi_wdata(4 downto 0)));
              rin.data <= (others => '-');
            when JTAG_TRANSACTOR_REG_RTI =>
              rin.state <= ST_OP_CMD;
              rin.op <= ATE_OP_RTI;
              rin.size_m1 <= to_integer(unsigned(s_axi_wdata(4 downto 0)));
              rin.data <= (others => '-');
            when JTAG_TRANSACTOR_REG_SWD_TO_JTAG =>
              rin.state <= ST_OP_CMD;
              rin.op <= ATE_OP_SWD_TO_JTAG;
              rin.data <= (others => '-');
            when JTAG_TRANSACTOR_REG_DR_CAPTURE =>
              rin.state <= ST_OP_CMD;
              rin.op <= ATE_OP_DR_CAPTURE;
              rin.data <= (others => '-');
            when JTAG_TRANSACTOR_REG_IR_CAPTURE =>
              rin.state <= ST_OP_CMD;
              rin.op <= ATE_OP_IR_CAPTURE;
              rin.data <= (others => '-');
            when JTAG_TRANSACTOR_REG_SHIFT1 to JTAG_TRANSACTOR_REG_SHIFT32 =>
              rin.state <= ST_OP_DATA_OUT;
              rin.op <= ATE_OP_SHIFT;
              rin.size_m1 <= to_integer(unsigned(s_axi_addr(6 downto 2)));
              rin.data <= s_axi_wdata;
            when others =>
              rin.data <= (others => '-');
          end case;
        end if;

      when ST_OP_CMD =>
        if s_ate_cmd_ready = '1' then
          rin.state <= ST_IDLE;
        end if;

      when ST_OP_DATA_OUT =>
        if s_ate_cmd_ready = '1' then
          rin.state <= ST_OP_DATA_IN;
        end if;

      when ST_OP_DATA_IN =>
        if s_ate_rsp_valid = '1' then
          rin.state <= ST_IDLE;
          rin.data <= s_ate_rsp_data;
        end if;

      when ST_READ_RSP =>
        rin.state <= ST_IDLE;
    end case;
  end process;

  moore: process(r)
  begin
    s_axi_write_ready <= '0';
    s_axi_read_done <= '0';
    s_ate_cmd_valid <= '0';
    s_ate_rsp_ready <= '0';

    case r.state is
      when ST_IDLE =>
        s_axi_write_ready <= '1';

      when ST_READ_RSP =>
        s_axi_read_done <= '1';

      when ST_OP_DATA_OUT | ST_OP_CMD =>
        s_ate_cmd_valid <= '1';

      when ST_OP_DATA_IN =>
        s_ate_rsp_ready <= '1';

      when others =>
        null;
    end case;
  end process;
  
  ate: nsl_jtag.ate.jtag_ate
    generic map(
      prescaler_width => prescaler_width_c,
      data_max_size => 32,
      allow_pipelining => false
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      divisor_i => r.divisor,

      cmd_ready_o => s_ate_cmd_ready,
      cmd_valid_i => s_ate_cmd_valid,
      cmd_op_i => r.op,
      cmd_data_i => r.data,
      cmd_size_m1_i => r.size_m1,

      rsp_ready_i => s_ate_rsp_ready,
      rsp_valid_o => s_ate_rsp_valid,
      rsp_data_o => s_ate_rsp_data,

      jtag_o => jtag_o,
      jtag_i => jtag_i
      );

end architecture;
