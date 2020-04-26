library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_i2c;
use nsl_i2c.transactor.all;
use nsl_i2c.i2c."+";
use nsl_i2c.master.all;

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
    ST_CMD_GET,

    ST_EXEC,

    ST_START_RUN,
    ST_RESTART_RUN,
    ST_STOP_RUN,

    ST_READ_RUN,
    ST_READ_DATA,
    ST_READ_ACK,
    ST_READ_PUT,

    ST_WRITE_GET,
    ST_WRITE_RUN,
    ST_WRITE_DATA,
    ST_WRITE_ACK,
    ST_WRITE_PUT,

    ST_IO_FLUSH_GET,
    ST_IO_FLUSH_PUT,

    ST_RSP_PUT
    );  
  
  type regs_t is record
    state      : state_t;
    last       : std_ulogic;
    cmd        : std_ulogic_vector(7 downto 0);
    data       : std_ulogic_vector(7 downto 0);
    word_count : natural range 0 to 63;
    divisor    : unsigned(10 downto 0);
  end record;

  signal r, rin : regs_t;

  signal i2c_filt_i : nsl_i2c.i2c.i2c_i;
  signal i2c_clocker_o, i2c_shifter_o : nsl_i2c.i2c.i2c_o;
  signal start_i, stop_i : std_ulogic;
  signal clocker_owned_i, clocker_abort_o, clocker_ready_i, clocker_valid_o : std_ulogic;
  signal clocker_cmd_o : i2c_bus_cmd_t;
  signal shift_enable_o, shift_send_data_o, shift_arb_ok_i : std_ulogic;
  signal shift_w_valid_o, shift_w_ready_i : std_ulogic;
  signal shift_r_valid_i, shift_r_ready_o : std_ulogic;
  signal shift_w_data_o, shift_r_data_i : std_ulogic_vector(7 downto 0);
begin

  line_mon: nsl_i2c.i2c.i2c_line_monitor
    generic map(
      debounce_count_c => 2
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      raw_i => i2c_i,
      filtered_o => i2c_filt_i,
      start_o => start_i,
      stop_o => stop_i
      );

  clock_driver: nsl_i2c.master.master_clock_driver
    port map(
      clock_i   => clock_i,
      reset_n_i => reset_n_i,

      half_cycle_clock_count_i => r.divisor,

      i2c_i => i2c_filt_i,
      i2c_o => i2c_clocker_o,

      ready_o => clocker_ready_i,
      valid_i => clocker_valid_o,
      cmd_i => clocker_cmd_o,

      abort_i => clocker_abort_o,
      owned_o => clocker_owned_i
      );
  
  shifter: nsl_i2c.master.master_shift_register
    port map(
      clock_i  => clock_i,
      reset_n_i => reset_n_i,

      i2c_o => i2c_shifter_o,
      i2c_i => i2c_filt_i,

      start_i => start_i,
      arb_ok_o  => shift_arb_ok_i,

      enable_i => shift_enable_o,
      send_mode_i => shift_send_data_o,

      send_valid_i => shift_w_valid_o,
      send_ready_o => shift_w_ready_i,
      send_data_i => shift_w_data_o,

      recv_valid_o => shift_r_valid_i,
      recv_ready_i => shift_r_ready_o,
      recv_data_o => shift_r_data_i
      );

  ck : process (clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition : process (clocker_owned_i, clocker_ready_i,
                        cmd_i, r, rsp_i,
                        shift_r_data_i, shift_r_valid_i, shift_w_ready_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.divisor <= (others => '1');
        rin.state <= ST_CMD_GET;

      when ST_CMD_GET =>
        if cmd_i.valid = '1' then
          rin.cmd <= cmd_i.data;
          rin.last <= cmd_i.last;
          rin.state <= ST_EXEC;
        end if;

      when ST_EXEC =>
        if clocker_ready_i = '1' then
          if std_match(r.cmd, I2C_CMD_READ) then
            rin.word_count <= to_integer(unsigned(r.cmd(5 downto 0)));
            if clocker_owned_i = '1' then
              rin.state <= ST_READ_RUN;
            else
              rin.state <= ST_IO_FLUSH_PUT;
            end if;

          elsif std_match(r.cmd, I2C_CMD_WRITE) then
            rin.word_count <= to_integer(unsigned(r.cmd(5 downto 0)));
            if clocker_owned_i = '1' then
              rin.state <= ST_WRITE_GET;
            else
              rin.state <= ST_IO_FLUSH_GET;
            end if;

          elsif std_match(r.cmd, I2C_CMD_DIV) then
            rin.state <= ST_RSP_PUT;
            rin.divisor <= unsigned(r.cmd(5 downto 0)) & "00000";

          elsif std_match(r.cmd, I2C_CMD_START) then
            if clocker_owned_i = '1' then
              rin.state <= ST_RESTART_RUN;
            else
              rin.state <= ST_START_RUN;
            end if;

          elsif std_match(r.cmd, I2C_CMD_STOP) then
            if clocker_owned_i = '1' then
              rin.state <= ST_STOP_RUN;
            else
              rin.state <= ST_RSP_PUT;
            end if;
          end if;
        end if;

      when ST_START_RUN | ST_RESTART_RUN | ST_STOP_RUN =>
        if clocker_ready_i = '1' then
          rin.state <= ST_RSP_PUT;
        end if;
      
      when ST_READ_RUN =>
        if clocker_ready_i = '1' then
          rin.state <= ST_READ_DATA;
        end if;

      when ST_READ_DATA =>
        if shift_r_valid_i = '1' then
          rin.state <= ST_READ_ACK;
          rin.data <= shift_r_data_i;
        end if;

      when ST_READ_ACK =>
        if shift_w_ready_i = '1' then
          rin.state <= ST_READ_PUT;
        end if;

      when ST_READ_PUT =>
        if rsp_i.ready = '1' then
          rin.word_count <= (r.word_count - 1) mod 64;
          if r.word_count = 0 then
            rin.state <= ST_CMD_GET;
          else
            rin.state <= ST_READ_RUN;
          end if;
        end if;

      when ST_WRITE_GET =>
        if cmd_i.valid = '1' then
          rin.data <= cmd_i.data;
          rin.last <= cmd_i.last;
          rin.state <= ST_WRITE_RUN;
        end if;

      when ST_WRITE_RUN =>
        if clocker_ready_i = '1' then
          rin.state <= ST_WRITE_DATA;
        end if;

      when ST_WRITE_DATA =>
        if shift_w_ready_i = '1' then
          rin.state <= ST_WRITE_ACK;
        end if;

      when ST_WRITE_ACK =>
        if shift_r_valid_i = '1' then
          rin.state <= ST_WRITE_PUT;
          rin.data <= (0 => not shift_r_data_i(0), others => '0');
        end if;

      when ST_WRITE_PUT =>
        if rsp_i.ready = '1' then
          rin.word_count <= (r.word_count - 1) mod 64;
          if r.word_count = 0 then
            rin.state <= ST_CMD_GET;
          else
            rin.state <= ST_WRITE_GET;
          end if;
        end if;

      when ST_IO_FLUSH_GET =>
        if cmd_i.valid = '1' then
          rin.last <= cmd_i.last;
          rin.state <= ST_IO_FLUSH_PUT;
        end if;

      when ST_IO_FLUSH_PUT =>
        if cmd_i.valid = '1' then
          rin.word_count <= (r.word_count - 1) mod 64;
          if r.word_count = 0 then
            rin.state <= ST_CMD_GET;
          elsif std_match(r.cmd, I2C_CMD_WRITE) then
            rin.state <= ST_IO_FLUSH_GET;
          end if;
        end if;
        
      when ST_RSP_PUT =>
        if rsp_i.ready = '1' then
          rin.state <= ST_CMD_GET;
        end if;

    end case;
  end process;

  i2c_o <= i2c_clocker_o + i2c_shifter_o;
  clocker_abort_o <= not shift_arb_ok_i;

  moore : process (r)
  begin
    clocker_valid_o <= '0';
    clocker_cmd_o <= I2C_BUS_START;
    cmd_o.ready <= '0';
    rsp_o.valid <= '0';
    rsp_o.last <= '-';
    rsp_o.data <= (others => '-');
    shift_enable_o <= '0';
    shift_send_data_o <= '-';
    shift_w_valid_o <= '0';
    shift_r_ready_o <= '0';
    shift_w_data_o <= (others => '-');

    case r.state is
      when ST_RESET =>
        null;

      when ST_CMD_GET | ST_WRITE_GET | ST_IO_FLUSH_GET =>
        cmd_o.ready <= '1';

      when ST_EXEC =>
        null;

      when ST_START_RUN | ST_RESTART_RUN =>
        clocker_valid_o <= '1';
        clocker_cmd_o <= I2C_BUS_START;

      when ST_STOP_RUN =>
        clocker_valid_o <= '1';
        clocker_cmd_o <= I2C_BUS_STOP;

      when ST_READ_RUN | ST_WRITE_RUN =>
        clocker_valid_o <= '1';
        clocker_cmd_o <= I2C_BUS_BYTE;

      when ST_READ_DATA | ST_WRITE_ACK =>
        shift_r_ready_o <= '1';

      when ST_READ_ACK =>
        shift_w_valid_o <= '1';
        if std_match(r.cmd, I2C_CMD_READ_NACK) and r.word_count = 0 then
          shift_w_data_o <= (0 => '1', others => '-');
        else
          shift_w_data_o <= (0 => '0', others => '-');
        end if;

      when ST_WRITE_DATA =>
        shift_w_valid_o <= '1';
        shift_w_data_o <= r.data;

      when ST_READ_PUT | ST_WRITE_PUT | ST_IO_FLUSH_PUT =>
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
      
    end case;

    case r.state is

      when ST_WRITE_RUN | ST_WRITE_DATA | ST_WRITE_ACK =>
        shift_enable_o <= '1';
        shift_send_data_o <= '1';

      when ST_READ_RUN | ST_READ_DATA | ST_READ_ACK =>
        shift_enable_o <= '1';
        shift_send_data_o <= '0';

      when others =>
        null;
        
    end case;

  end process;

end architecture;
