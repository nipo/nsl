library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_io, nsl_data, nsl_math, nsl_logic;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_io.io.all;
use nsl_math.int_ext.all;
use nsl_math.timing.all;
use nsl_logic.bool.all;

entity sspi_loader is
  generic(
    clock_i_hz_c : natural;
    slave_no_c : natural range 0 to 6;
    init_b_ignore_c : boolean := false;

    spi_master_clock_i_hz_c: natural := 0;
    
    cclk_rate_c : natural := 70e6;
    tprogram_c: time := 250 ns;
    tpl_c: time := 5 ms;
    ticck_c: time := 150 ns;
    config_timeout_c : time := 5 ms
    );
  port(
    reset_n_i    : in std_ulogic;
    clock_i      : in std_ulogic;

    bitstream_i : in framed_req;
    bitstream_o : out framed_ack;

    done_i : in std_ulogic;
    init_b_i : in std_ulogic := '1';
    program_b_o : out opendrain;
    
    -- Framed interface to a SPI controller
    cmd_o : out framed_req;
    cmd_i : in  framed_ack;
    rsp_i : in  framed_req;
    rsp_o : out framed_ack
    );
end entity;

architecture beh of sspi_loader is

  constant spi_burst_length_c: natural := 64;
  constant tprogram_reload_c : natural := to_cycles(tprogram_c, clock_i_hz_c) - 1;
  constant tpl_reload_c : natural := to_cycles(tpl_c, clock_i_hz_c) - 1;
  constant ticck_reload_c : natural := to_cycles(ticck_c, clock_i_hz_c) - 1;
  constant config_timeout_reload_c : natural := to_cycles(config_timeout_c, clock_i_hz_c) - 1;

  constant spi_ref_clock_s : natural := if_else(spi_master_clock_i_hz_c = 0, clock_i_hz_c, spi_master_clock_i_hz_c);
  constant div_value_c : integer := nsl_math.arith.min(31, to_cycles(1.0 / real(cclk_rate_c) / 2.0, spi_ref_clock_s) - 1);
  constant div_c : unsigned(4 downto 0) := to_unsigned(div_value_c, 5);
  constant spi_burst_length_m1_c : unsigned(5 downto 0) := to_unsigned(spi_burst_length_c - 1, 6);
  constant select_c : unsigned(2 downto 0) := to_unsigned(slave_no_c, 3);
  constant unselect_c : unsigned(2 downto 0) := (others => '1');

  constant st_left_maxs_c: integer_vector := (
    tprogram_reload_c,
    tpl_reload_c,
    ticck_reload_c,
    config_timeout_reload_c,
    spi_burst_length_c - 1);

  constant st_left_max_c: natural := max(st_left_maxs_c);
  
  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_TPROGRAM,
    ST_INITB_WAIT,
    ST_TPL,
    ST_TICCK,
    ST_PUT_FRAME,
    ST_PUT_PAD,
    ST_WAIT_START
    );

  type cmd_state_t is (
    CMD_IDLE,
    CMD_PUT_DIV,
    CMD_PUT_SELECT,
    CMD_PUT_SHIFT,
    CMD_PUT_DATA,
    CMD_PUT_UNSELECT
    );

  type rsp_state_t is (
    RSP_IDLE,
    RSP_WAIT
    );

  constant fifo_depth_c : natural := 2;
  
  type regs_t is
  record
    state: state_t;
    left : integer range 0 to st_left_max_c;

    cmd_state: cmd_state_t;
    cmd_left : integer range 0 to spi_burst_length_c - 1;
    rsp_state: rsp_state_t;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: natural range 0 to fifo_depth_c;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.cmd_state <= CMD_IDLE;
      r.rsp_state <= RSP_IDLE;
    end if;
  end process;

  transition: process(r, rsp_i, cmd_i, bitstream_i, done_i, init_b_i) is
    variable fifo_push, fifo_pop: boolean;
    variable fifo_data: byte;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;
    fifo_data := "--------";

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if bitstream_i.valid = '1' then
          rin.state <= ST_TPROGRAM;
          rin.left <= tprogram_reload_c;
        end if;

      when ST_TPROGRAM =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        elsif init_b_ignore_c then
          rin.state <= ST_TPL;
          rin.left <= tpl_reload_c;
        else
          rin.state <= ST_INITB_WAIT;
        end if;
        
      when ST_INITB_WAIT =>
        if init_b_i = '0' then
          rin.state <= ST_TPL;
          rin.left <= tpl_reload_c;
        end if;

      when ST_TPL =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.state <= ST_TICCK;
          rin.left <= ticck_reload_c;
        end if;

      when ST_TICCK =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.state <= ST_PUT_FRAME;
          rin.left <= spi_burst_length_c - 1;
        end if;

      when ST_PUT_FRAME =>
        if bitstream_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
          fifo_push := true;
          fifo_data := bitstream_i.data;
          if bitstream_i.last = '1' then
            if r.left = 0 then
              rin.state <= ST_WAIT_START;
              rin.left <= config_timeout_reload_c;
            else
              rin.state <= ST_PUT_PAD;
            end if;
          else
            if r.left = 0 then
              rin.left <= spi_burst_length_c - 1;
            else
              rin.left <= r.left - 1;
            end if;
          end if;
        end if;

      when ST_PUT_PAD =>
        if r.fifo_fillness < fifo_depth_c then
          fifo_push := true;
          fifo_data := x"00";
          if r.left = 0 then
            rin.state <= ST_WAIT_START;
            rin.left <= config_timeout_reload_c;
          else
            rin.left <= r.left - 1;
          end if;
        end if;

      when ST_WAIT_START =>
        if done_i = '1' or r.left = 0 then
          rin.state <= ST_IDLE;
        else
          rin.left <= r.left - 1;
        end if;
    end case;

    case r.cmd_state is
      when CMD_IDLE =>
        if r.state = ST_PUT_FRAME or r.state = ST_PUT_PAD then
          rin.cmd_state <= CMD_PUT_DIV;
        end if;

      when CMD_PUT_DIV =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_SELECT;
        end if;

      when CMD_PUT_SELECT =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_SHIFT;
        end if;

      when CMD_PUT_SHIFT =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_DATA;
          rin.cmd_left <= spi_burst_length_c - 1;
        end if;

      when CMD_PUT_DATA =>
        if cmd_i.ready = '1' and r.fifo_fillness /= 0 then
          fifo_pop := true;
          if r.cmd_left /= 0 then
            rin.cmd_left <= r.cmd_left - 1;
          else
            rin.cmd_state <= CMD_PUT_UNSELECT;
          end if;
        end if;

      when CMD_PUT_UNSELECT =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_IDLE;
        end if;
    end case;

    case r.rsp_state is
      when RSP_IDLE =>
        if r.cmd_state /= CMD_IDLE then
          rin.rsp_state <= RSP_WAIT;
        end if;

      when RSP_WAIT =>
        if rsp_i.valid = '1' and rsp_i.last = '1' then
          rin.rsp_state <= RSP_IDLE;
        end if;
    end case;
    
    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= fifo_data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= fifo_data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    bitstream_o <= framed_accept(false);
    program_b_o.drain_n <= '1';

    case r.state is
      when ST_RESET | ST_IDLE | ST_TPL | ST_TICCK | ST_PUT_PAD | ST_WAIT_START =>
        null;

      when ST_TPROGRAM | ST_INITB_WAIT =>
        program_b_o.drain_n <= '0';

      when ST_PUT_FRAME =>
        bitstream_o <= framed_accept(r.fifo_fillness < fifo_depth_c);
    end case;

    cmd_o <= framed_req_idle_c;
    case r.cmd_state is
      when CMD_IDLE =>
        null;

      when CMD_PUT_DIV =>
        cmd_o <= framed_flit("001" & std_ulogic_vector(div_c));

      when CMD_PUT_SELECT =>
        cmd_o <= framed_flit("000" & "00" & std_ulogic_vector(select_c));

      when CMD_PUT_SHIFT =>
        cmd_o <= framed_flit("10" & std_ulogic_vector(spi_burst_length_m1_c));

      when CMD_PUT_DATA =>
        cmd_o <= framed_flit(r.fifo(0), valid => r.fifo_fillness /= 0);

      when CMD_PUT_UNSELECT =>
        cmd_o <= framed_flit("000" & "00" & std_ulogic_vector(unselect_c), last => true);
    end case;

    case r.rsp_state is
      when RSP_IDLE =>
        rsp_o <= framed_accept(false);

      when RSP_WAIT =>
        rsp_o <= framed_accept(true);
    end case;
  end process;

end architecture;
