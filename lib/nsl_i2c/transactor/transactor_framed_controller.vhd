library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_i2c;
use nsl_i2c.transactor.all;

entity transactor_framed_controller is
  port(
    clock_i    : in std_ulogic;
    reset_n_i : in std_ulogic;

    i2c_o  : out nsl_i2c.i2c.i2c_o;
    i2c_i  : in  nsl_i2c.i2c.i2c_i;

    cmd_i  : in nsl_bnoc.framed.framed_req;
    cmd_o  : out nsl_bnoc.framed.framed_ack;
    rsp_o  : out nsl_bnoc.framed.framed_req;
    rsp_i  : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of transactor_framed_controller is
  
  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_RSP_PUT,
    ST_ACK_PUT,
    ST_DATA_PUT,
    ST_DATA_GET,
    ST_READ,
    ST_WRITE,
    ST_START,
    ST_STOP
    );
  
  type regs_t is record
    state                : state_t;
    last                 : std_ulogic;
    ack                  : std_ulogic;
    data                 : std_ulogic_vector(7 downto 0);
    word_count           : natural range 0 to 63;
    divisor              : std_ulogic_vector(7 downto 0);
  end record;

  signal r, rin : regs_t;

  signal s_wack     :  std_ulogic;
  signal s_rack     :  std_ulogic;
  signal s_rdata    :  std_ulogic_vector(7 downto 0);
  signal s_cmd      :  i2c_cmd_t;
  signal s_busy     :  std_ulogic;
  signal s_done     :  std_ulogic;

begin

  ck : process (clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition : process (r, cmd_i, rsp_i, s_busy, s_done, s_rdata, s_wack)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.divisor <= (others => '1');
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if cmd_i.valid = '1' then
          rin.ack <= '-';
          rin.last <= cmd_i.last;

          if std_match(cmd_i.data, I2C_CMD_READ) then
            rin.state <= ST_READ;
            rin.word_count <= to_integer(unsigned(cmd_i.data(5 downto 0)));
            rin.ack <= cmd_i.data(6);

          elsif std_match(cmd_i.data, I2C_CMD_WRITE) then
            rin.state <= ST_DATA_GET;
            rin.word_count <= to_integer(unsigned(cmd_i.data(5 downto 0)));

          elsif std_match(cmd_i.data, I2C_CMD_DIV) then
            rin.state <= ST_RSP_PUT;
            rin.divisor <= cmd_i.data(5 downto 0) & "11";

          elsif std_match(cmd_i.data, I2C_CMD_START) then
            rin.state <= ST_START;

          elsif std_match(cmd_i.data, I2C_CMD_STOP) then
            rin.state <= ST_STOP;
          end if;
        end if;

      when ST_RSP_PUT =>
        if rsp_i.ready = '1' then
          rin.state <= ST_IDLE;
        end if;

      when ST_ACK_PUT =>
        if rsp_i.ready = '1' then
          if r.word_count = 0 then
            rin.state <= ST_IDLE;
          else
            rin.state <= ST_DATA_GET;
            rin.word_count <= r.word_count - 1;
          end if;
        end if;

      when ST_DATA_PUT =>
        if rsp_i.ready = '1' then
          if r.word_count = 0 then
            rin.state <= ST_IDLE;
          else
            rin.state <= ST_READ;
            rin.word_count <= r.word_count - 1;
          end if;
        end if;

      when ST_START | ST_STOP =>
        if s_done = '1' then
          rin.state <= ST_RSP_PUT;
        end if;

      when ST_READ =>
        if s_done = '1' then
          rin.state <= ST_DATA_PUT;
          rin.data <= s_rdata;
        end if;

      when ST_WRITE =>
        if s_done = '1' then
          rin.state <= ST_ACK_PUT;
          rin.ack <= s_wack;
        end if;

      when ST_DATA_GET =>
        if cmd_i.valid = '1' then
          rin.state <= ST_WRITE;
          rin.data <= cmd_i.data;
          rin.last <= cmd_i.last;
        end if;

    end case;
  end process;

  moore : process (r)
  begin
    case r.state is
      when ST_START =>
        s_cmd <= I2C_START;

      when ST_STOP =>
        s_cmd <= I2C_STOP;

      when ST_READ =>
        s_cmd <= I2C_READ;

      when ST_WRITE =>
        s_cmd <= I2C_WRITE;

      when others =>
        s_cmd <= I2C_NOOP;
    end case;

    case r.state is
      when ST_DATA_PUT =>
        rsp_o.valid <= '1';
        rsp_o.data <= r.data;
        if r.word_count = 0 then
          rsp_o.last <= r.last;
        else
          rsp_o.last <= '0';
        end if;

      when ST_RSP_PUT =>
        rsp_o.valid <= '1';
        rsp_o.data <= (others => '0');
        rsp_o.last <= r.last;

      when ST_ACK_PUT =>
        rsp_o.valid <= '1';
        rsp_o.data <= "0000000" & r.ack;
        if r.word_count = 0 then
          rsp_o.last <= r.last;
        else
          rsp_o.last <= '0';
        end if;

      when others =>
        rsp_o.valid <= '0';
        rsp_o.data <= (others => '-');
        rsp_o.last <= '-';
    end case;

    case r.state is
      when ST_DATA_GET | ST_IDLE =>
        cmd_o.ready <= '1';

      when others =>
        cmd_o.ready <= '0';
    end case;
  end process;

  s_rack <= r.ack when r.word_count = 0 else '1';
  
  master: nsl_i2c.transactor.transactor_master
    generic map(
      divisor_width => r.divisor'length
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      divisor_i => r.divisor,

      i2c_o => i2c_o,
      i2c_i => i2c_i,

      rack_i => s_rack,
      rdata_o => s_rdata,
      wack_o => s_wack,
      wdata_i => r.data,

      cmd_i => s_cmd,
      busy_o => s_busy,
      done_o => s_done
      );
  
end architecture;
