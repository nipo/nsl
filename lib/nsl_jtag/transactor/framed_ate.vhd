library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_bnoc, nsl_io;
use nsl_jtag.ate.all;
use nsl_jtag.transactor.all;
use nsl_bnoc.framed.all;

entity framed_ate is
  port (
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    cmd_i   : in nsl_bnoc.framed.framed_req;
    cmd_o   : out nsl_bnoc.framed.framed_ack;
    rsp_o   : out nsl_bnoc.framed.framed_req;
    rsp_i   : in nsl_bnoc.framed.framed_ack;

    jtag_o : out nsl_jtag.jtag.jtag_ate_o;
    jtag_i : in nsl_jtag.jtag.jtag_ate_i;

    system_reset_n_o : out nsl_io.io.opendrain
    );
end entity;

architecture rtl of framed_ate is

  type st_cmd_t is (
    ST_CMD_RESET,
    ST_CMD_IDLE,
    ST_CMD_ROUTE,
    ST_CMD_PUT,
    ST_CMD_DATA_GET,
    ST_CMD_DATA_PUT,
    ST_CMD_DIV_GET
    );

  type st_rsp_t is (
    ST_RSP_RESET,
    ST_RSP_IDLE,
    ST_RSP_ROUTE,
    ST_RSP_WAIT_CMD_IDLE,
    ST_RSP_PUT,
    ST_RSP_DATA_BLACKHOLE,
    ST_RSP_DATA_GET,
    ST_RSP_DATA_PUT
    );

  constant data_max_size : natural := 8;
  
  type regs_t is
  record
    cmd_st : st_cmd_t;
    cmd_pending : ate_op;
    cmd_last : boolean;
    cmd_data : std_ulogic_vector(7 downto 0);
    cmd_word_left : natural range 0 to 31;
    cmd_bit_count_m1 : natural range 0 to data_max_size-1;

    rsp_st : st_rsp_t;
    rsp_data : std_ulogic_vector(7 downto 0);
    rsp_word_left : natural range 0 to 31;

    divisor : natural range 0 to 255;

    srst_drive : std_ulogic;
  end record;

  signal r, rin: regs_t;
  
  signal s_cmd_ready : std_ulogic;
  signal s_cmd_valid : std_ulogic;
  signal s_cmd_op    : ate_op;
  signal s_cmd_data  : std_ulogic_vector(data_max_size-1 downto 0);

  signal s_rsp_ready : std_ulogic;
  signal s_rsp_valid : std_ulogic;
  signal s_rsp_data  : std_ulogic_vector(data_max_size-1 downto 0);

begin
  
  reg: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.rsp_st <= ST_RSP_RESET;
      r.cmd_st <= ST_CMD_RESET;
    end if;
  end process;

  transition: process(cmd_i, r, rsp_i,
                      s_cmd_ready, s_rsp_data, s_rsp_valid)
  begin
    rin <= r;
    
    case r.cmd_st is
      when ST_CMD_RESET =>
        rin.cmd_st <= ST_CMD_IDLE;
        rin.srst_drive <= '0';

      when ST_CMD_IDLE =>
        if r.rsp_st = ST_RSP_IDLE and cmd_i.valid = '1' then
          rin.cmd_data <= cmd_i.data;
          rin.cmd_last <= cmd_i.last = '1';
          rin.cmd_st <= ST_CMD_ROUTE;
        end if;

      when ST_CMD_ROUTE =>
        rin.cmd_word_left <= 0;
        if std_match(r.cmd_data, JTAG_SHIFT_BYTE) then
          rin.cmd_word_left <= to_integer(unsigned(r.cmd_data(4 downto 0)));
          rin.cmd_bit_count_m1 <= 7;
          rin.cmd_pending <= ATE_OP_SHIFT;
          if std_match(r.cmd_data, JTAG_SHIFT_BYTE_W) then
            rin.cmd_st <= ST_CMD_DATA_GET;
          else
            rin.cmd_data <= (others => '0');
            rin.cmd_st <= ST_CMD_PUT;
          end if;
        elsif std_match(r.cmd_data, JTAG_SHIFT_BIT) then
          rin.cmd_bit_count_m1 <= to_integer(unsigned(r.cmd_data(2 downto 0)));
          rin.cmd_pending <= ATE_OP_SHIFT;
          if std_match(r.cmd_data, JTAG_SHIFT_BIT_W) then
            rin.cmd_st <= ST_CMD_DATA_GET;
          else
            rin.cmd_data <= (others => '0');
            rin.cmd_st <= ST_CMD_PUT;
          end if;
        elsif std_match(r.cmd_data, JTAG_CMD_DR_CAPTURE) then
          rin.cmd_st <= ST_CMD_PUT;
          rin.cmd_pending <= ATE_OP_DR_CAPTURE;
        elsif std_match(r.cmd_data, JTAG_CMD_IR_CAPTURE) then
          rin.cmd_st <= ST_CMD_PUT;
          rin.cmd_pending <= ATE_OP_IR_CAPTURE;
        elsif std_match(r.cmd_data, JTAG_CMD_SWD_TO_JTAG) then
          rin.cmd_st <= ST_CMD_PUT;
          rin.cmd_pending <= ATE_OP_SWD_TO_JTAG;
        elsif std_match(r.cmd_data, JTAG_CMD_RESET_CYCLE) then
          rin.cmd_bit_count_m1 <= to_integer(unsigned(r.cmd_data(2 downto 0)));
          rin.cmd_st <= ST_CMD_PUT;
          rin.cmd_pending <= ATE_OP_RESET;
        elsif std_match(r.cmd_data, JTAG_CMD_RTI_CYCLE) then
          rin.cmd_bit_count_m1 <= to_integer(unsigned(r.cmd_data(2 downto 0)));
          rin.cmd_st <= ST_CMD_PUT;
          rin.cmd_pending <= ATE_OP_RTI;
        elsif std_match(r.cmd_data, JTAG_CMD_RESET) then
          rin.cmd_bit_count_m1 <= 7;
          rin.cmd_word_left <= to_integer(unsigned(r.cmd_data(3 downto 0)));
          rin.cmd_pending <= ATE_OP_RESET;
          rin.cmd_st <= ST_CMD_PUT;
        elsif std_match(r.cmd_data, JTAG_CMD_RTI) then
          rin.cmd_bit_count_m1 <= 7;
          rin.cmd_word_left <= to_integer(unsigned(r.cmd_data(3 downto 0)));
          rin.cmd_st <= ST_CMD_PUT;
          rin.cmd_pending <= ATE_OP_RTI;
        elsif std_match(r.cmd_data, JTAG_CMD_DIVISOR) then
          rin.cmd_st <= ST_CMD_DIV_GET;
        elsif std_match(r.cmd_data, JTAG_CMD_SYS_RESET) then
          rin.cmd_st <= ST_CMD_IDLE;
          rin.srst_drive <= r.cmd_data(0);
        else
          report "Unhandled Framed JTAG ATE command"
            severity warning;

          rin.cmd_st <= ST_CMD_IDLE;
        end if;

      when ST_CMD_PUT =>
        if s_cmd_ready = '1' then
          if r.cmd_word_left /= 0 then
            rin.cmd_word_left <= r.cmd_word_left - 1;
          else
            rin.cmd_st <= ST_CMD_IDLE;
          end if;
        end if;
        
      when ST_CMD_DATA_GET =>
        if cmd_i.valid = '1' then
          rin.cmd_data <= cmd_i.data;
          rin.cmd_last <= cmd_i.last = '1';
          rin.cmd_st <= ST_CMD_DATA_PUT;
        end if;
        
      when ST_CMD_DIV_GET =>
        if cmd_i.valid = '1' then
          rin.divisor <= to_integer(unsigned(cmd_i.data));
          rin.cmd_last <= cmd_i.last = '1';
          rin.cmd_st <= ST_CMD_IDLE;
        end if;

      when ST_CMD_DATA_PUT =>
        if s_cmd_ready = '1' then
          if r.cmd_word_left /= 0 then
            rin.cmd_word_left <= r.cmd_word_left - 1;
            rin.cmd_st <= ST_CMD_DATA_GET;
          else
            rin.cmd_st <= ST_CMD_IDLE;
          end if;
        end if;
    end case;

    case r.rsp_st is
      when ST_RSP_RESET =>
        rin.rsp_st <= ST_RSP_IDLE;

      when ST_RSP_IDLE =>
        if r.cmd_st = ST_CMD_ROUTE then
          rin.rsp_st <= ST_RSP_ROUTE;
          rin.rsp_data <= r.cmd_data;
        end if;

      when ST_RSP_ROUTE =>
        rin.rsp_data <= (others => '-');
        if std_match(r.rsp_data, JTAG_SHIFT_BYTE) then
          rin.rsp_word_left <= to_integer(unsigned(r.rsp_data(4 downto 0)));
          if std_match(r.rsp_data, JTAG_SHIFT_BYTE_R) then
            rin.rsp_st <= ST_RSP_DATA_GET;
          else
            rin.rsp_st <= ST_RSP_DATA_BLACKHOLE;
          end if;
        elsif std_match(r.rsp_data, JTAG_SHIFT_BIT) then
          rin.rsp_word_left <= 0;
          if std_match(r.rsp_data, JTAG_SHIFT_BIT_R) then
            rin.rsp_st <= ST_RSP_DATA_GET;
          else
            rin.rsp_st <= ST_RSP_DATA_BLACKHOLE;
          end if;
        elsif std_match(r.rsp_data, JTAG_CMD_DIVISOR) then
          rin.rsp_st <= ST_RSP_WAIT_CMD_IDLE;
        else
          rin.rsp_st <= ST_RSP_PUT;
        end if;

      when ST_RSP_WAIT_CMD_IDLE =>
        if r.cmd_st = ST_CMD_IDLE then
          rin.rsp_st <= ST_RSP_PUT;
        end if;

      when ST_RSP_PUT =>
        if rsp_i.ready = '1' then
          rin.rsp_st <= ST_RSP_IDLE;
        end if;

      when ST_RSP_DATA_GET =>
        rin.rsp_data <= (others => '-');
        if s_rsp_valid = '1' then
          rin.rsp_data <= s_rsp_data;
          rin.rsp_st <= ST_RSP_DATA_PUT;
        end if;

      when ST_RSP_DATA_PUT =>
        if rsp_i.ready = '1' then
          rin.rsp_data <= (others => '-');
          if r.rsp_word_left = 0 then
            rin.rsp_st <= ST_RSP_PUT;
          else
            rin.rsp_word_left <= r.rsp_word_left - 1;
            rin.rsp_st <= ST_RSP_DATA_GET;
          end if;
        end if;

      when ST_RSP_DATA_BLACKHOLE =>
        rin.rsp_data <= (others => '-');
        if s_rsp_valid = '1' then
          if r.rsp_word_left = 0 then
            rin.rsp_st <= ST_RSP_PUT;
          else
            rin.rsp_word_left <= r.rsp_word_left - 1;
          end if;
        end if;

    end case;

  end process;

  s_cmd_op <= r.cmd_pending;
  s_cmd_data <= r.cmd_data;

  moore: process(r)
  begin
    cmd_o <= framed_ack_idle_c;
    rsp_o <= framed_req_idle_c;

    s_rsp_ready <= '0';
    s_cmd_valid <= '0';
    system_reset_n_o.drain_n <= not r.srst_drive;

    case r.cmd_st is
      when ST_CMD_RESET | ST_CMD_ROUTE =>
        null;

      when ST_CMD_IDLE =>
        if r.rsp_st = ST_RSP_IDLE then
          cmd_o <= framed_accept(true);
        end if;
          
      when ST_CMD_DATA_GET | ST_CMD_DIV_GET =>
        cmd_o <= framed_accept(true);

      when ST_CMD_PUT | ST_CMD_DATA_PUT =>
        s_cmd_valid <= '1';
    end case;

    case r.rsp_st is
      when ST_RSP_RESET | ST_RSP_ROUTE | ST_RSP_IDLE | ST_RSP_WAIT_CMD_IDLE =>
        null;

      when ST_RSP_PUT =>
        rsp_o <= framed_flit(x"5a", last => r.cmd_last);

      when ST_RSP_DATA_PUT =>
        rsp_o <= framed_flit(r.rsp_data, last => false);
        
      when ST_RSP_DATA_GET | ST_RSP_DATA_BLACKHOLE =>
        s_rsp_ready <= '1';
    end case;
  end process;
  
  ate: jtag_ate
    generic map (
      prescaler_width => 8,
      data_max_size => data_max_size,
      allow_pipelining => false
      )
    port map (
      reset_n_i => reset_n_i,
      clock_i    => clock_i,
      divisor_i => r.divisor,

      cmd_ready_o => s_cmd_ready,
      cmd_valid_i => s_cmd_valid,
      cmd_op_i => s_cmd_op,
      cmd_data_i => s_cmd_data,
      cmd_size_m1_i => r.cmd_bit_count_m1,

      rsp_ready_i => s_rsp_ready,
      rsp_valid_o => s_rsp_valid,
      rsp_data_o => s_rsp_data,

      jtag_o => jtag_o,
      jtag_i => jtag_i
      );

end architecture;
