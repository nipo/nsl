library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_logic, nsl_math;
use nsl_bnoc.framed.all;
use nsl_math.timing.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity flash_reader is
  generic(
    clock_i_hz_c : natural;
    slave_no_c : natural range 0 to 6;

    spi_master_clock_i_hz_c: natural := 0;
    
    read_rate_c : natural := 100e6;
    address_byte_count_c: natural := 3;

    read_command_c: byte := x"0b";
    read_dummy_byte_count_c: natural := 1
    );
  port(
    reset_n_i    : in std_ulogic;
    clock_i      : in std_ulogic;

    address_i : in unsigned(8 * address_byte_count_c - 1 downto 0);
    length_m1_i : in unsigned;
    start_i : in std_ulogic;
    ready_o : out std_ulogic;

    data_o : out framed_req;
    data_i : in framed_ack;

    cmd_o : out framed_req;
    cmd_i : in  framed_ack;
    rsp_i : in  framed_req;
    rsp_o : out framed_ack
    );
end entity;

architecture beh of flash_reader is

  signal fifo_o, fifo_out_s : framed_req;
  signal fifo_i : framed_ack;
  signal next_i : std_ulogic;
  
  constant spi_max_burst_length_c: natural := 64;

  constant spi_ref_clock_s : natural := if_else(spi_master_clock_i_hz_c = 0, clock_i_hz_c, spi_master_clock_i_hz_c);

  constant div_value_c : integer := nsl_math.arith.min(31, to_cycles(1.0 / real(read_rate_c) / 2.0, spi_ref_clock_s) - 1);
  constant div_c : unsigned(4 downto 0) := to_unsigned(div_value_c, 5);
  constant select_c : unsigned(2 downto 0) := to_unsigned(slave_no_c, 3);
  constant unselect_c : unsigned(2 downto 0) := (others => '1');
  
  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_CHUNK_NEXT,
    ST_CHUNK_START,
    ST_CHUNK_WAIT,
    ST_DONE
    );

  type cmd_state_t is (
    CMD_IDLE,
    CMD_PUT_DIV,
    CMD_PUT_SELECT,
    CMD_PUT_SHIFT_CMD,
    CMD_PUT_READ_OP,
    CMD_PUT_ADDR,
    CMD_PUT_DUMMY,
    CMD_PUT_SHIFT_DATA,
    CMD_PUT_UNSELECT
    );

  type rsp_state_t is (
    RSP_IDLE,
    RSP_GET_DIV,
    RSP_GET_SELECT,
    RSP_GET_SHIFT_ADDR,
    RSP_GET_SHIFT_DATA,
    RSP_GET_DATA,
    RSP_GET_UNSELECT
    );

  constant fifo_depth_c : natural := 3;
  
  type regs_t is
  record
    state: state_t;
    left : integer range 0 to spi_max_burst_length_c - 1;

    address : unsigned(address_i'length-1 downto 0);
    length_m1 : unsigned(length_m1_i'length-1 downto 0);
    chunk_size_m1 : unsigned(5 downto 0);
    
    cmd_state: cmd_state_t;
    cmd_left: natural range 0 to address_byte_count_c - 1;
    rsp_state: rsp_state_t;
    rsp_left : unsigned(5 downto 0);

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

  transition: process(r, rsp_i, cmd_i, fifo_i, start_i, length_m1_i, address_i, next_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if start_i = '1' then
          rin.state <= ST_CHUNK_NEXT;
          rin.address <= address_i;
          rin.length_m1 <= length_m1_i;
        end if;

      when ST_CHUNK_NEXT =>
        if next_i = '1' then
          rin.state <= ST_CHUNK_START;
        end if;

      when ST_CHUNK_START =>
        rin.state <= ST_CHUNK_WAIT;
        if r.length_m1 < spi_max_burst_length_c then
          rin.chunk_size_m1 <= resize(r.length_m1, rin.chunk_size_m1'length);
        else
          rin.chunk_size_m1 <= to_unsigned(spi_max_burst_length_c-1, r.chunk_size_m1'length);
        end if;

      when ST_CHUNK_WAIT =>
        if r.rsp_state = RSP_IDLE then
          if resize(r.chunk_size_m1, r.length_m1'length) = r.length_m1 then
            rin.state <= ST_DONE;
          else
            rin.length_m1 <= r.length_m1 - resize(r.chunk_size_m1, r.length_m1'length) - 1;
            rin.address <= r.address + resize(r.chunk_size_m1, r.length_m1'length) + 1;
            rin.state <= ST_CHUNK_NEXT;
          end if;
        end if;

      when ST_DONE =>
        if r.fifo_fillness = 0 then
          rin.state <= ST_IDLE;
        end if;
    end case;

    case r.state is
      when ST_RESET =>
        null;

      when ST_IDLE | ST_CHUNK_START | ST_CHUNK_WAIT =>
        if r.fifo_fillness > 1 and fifo_i.ready = '1' then
          fifo_pop := true;
        end if;

      when ST_DONE | ST_CHUNK_NEXT =>
        if r.fifo_fillness > 0 and fifo_i.ready = '1' then
          fifo_pop := true;
        end if;
    end case;

    case r.cmd_state is
      when CMD_IDLE =>
        if r.state = ST_CHUNK_START then
          rin.cmd_state <= CMD_PUT_DIV;
        end if;

      when CMD_PUT_DIV =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_SELECT;
        end if;
        
      when CMD_PUT_SELECT =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_SHIFT_CMD;
        end if;
        
      when CMD_PUT_SHIFT_CMD =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_READ_OP;
        end if;
        
      when CMD_PUT_READ_OP =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_ADDR;
          rin.cmd_left <= address_byte_count_c-1;
        end if;
        
      when CMD_PUT_ADDR =>
        if cmd_i.ready = '1' then
          if r.cmd_left /= 0 then
            rin.cmd_left <= r.cmd_left - 1;
          elsif read_dummy_byte_count_c /= 0 then
            rin.cmd_left <= read_dummy_byte_count_c - 1;
            rin.cmd_state <= CMD_PUT_DUMMY;
          else
            rin.cmd_state <= CMD_PUT_SHIFT_DATA;
          end if;
        end if;
        
      when CMD_PUT_DUMMY =>
        if cmd_i.ready = '1' then
          if r.cmd_left /= 0 then
            rin.cmd_left <= r.cmd_left - 1;
          else
            rin.cmd_state <= CMD_PUT_SHIFT_DATA;
          end if;
        end if;
        
      when CMD_PUT_SHIFT_DATA =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_UNSELECT;
        end if;
        
      when CMD_PUT_UNSELECT =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_IDLE;
        end if;
    end case;

    case r.rsp_state is
      when RSP_IDLE =>
        if r.state = ST_CHUNK_START then
          rin.rsp_state <= RSP_GET_DIV;
        end if;

      when RSP_GET_DIV =>
        if rsp_i.valid = '1' then
          rin.rsp_state <= RSP_GET_SELECT;
        end if;

      when RSP_GET_SELECT =>
        if rsp_i.valid = '1' then
          rin.rsp_state <= RSP_GET_SHIFT_ADDR;
        end if;

      when RSP_GET_SHIFT_ADDR =>
        if rsp_i.valid = '1' then
          rin.rsp_state <= RSP_GET_SHIFT_DATA;
        end if;

      when RSP_GET_SHIFT_DATA =>
        if rsp_i.valid = '1' then
          rin.rsp_state <= RSP_GET_DATA;
          rin.rsp_left <= r.chunk_size_m1;
        end if;

      when RSP_GET_DATA =>
        if rsp_i.valid = '1' and r.fifo_fillness /= fifo_depth_c then
          fifo_push := true;

          rin.rsp_left <= r.rsp_left - 1;
          if r.rsp_left = 0 then
            rin.rsp_state <= RSP_GET_UNSELECT;
          end if;
        end if;

      when RSP_GET_UNSELECT =>
        if rsp_i.valid = '1' and rsp_i.last = '1' then
          rin.rsp_state <= RSP_IDLE;
        end if;
    end case;
    
    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= rsp_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= rsp_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    fifo_o <= framed_req_idle_c;
    ready_o <= to_logic(r.state = ST_IDLE);
    
    case r.state is
      when ST_RESET =>
        null;

      when ST_IDLE | ST_CHUNK_START | ST_CHUNK_WAIT =>
        fifo_o <= framed_flit(r.fifo(0), valid => r.fifo_fillness > 1, last => false);

      when ST_CHUNK_NEXT =>
        fifo_o <= framed_flit(r.fifo(0), valid => r.fifo_fillness > 0, last => false);

      when ST_DONE =>
        fifo_o <= framed_flit(r.fifo(0), valid => r.fifo_fillness > 0, last => r.fifo_fillness = 1);
    end case;

    cmd_o <= framed_req_idle_c;
    case r.cmd_state is
      when CMD_IDLE =>
        null;

      when CMD_PUT_DIV =>
        cmd_o <= framed_flit("001" & std_ulogic_vector(div_c));

      when CMD_PUT_SELECT =>
        cmd_o <= framed_flit("000" & "00" & std_ulogic_vector(select_c));

      when CMD_PUT_SHIFT_CMD =>
        cmd_o <= framed_flit("10" & std_ulogic_vector(to_unsigned(address_byte_count_c + read_dummy_byte_count_c + 1 - 1, 6)));

      when CMD_PUT_READ_OP =>
        cmd_o <= framed_flit(read_command_c);

      when CMD_PUT_ADDR =>
        cmd_o <= framed_flit(std_ulogic_vector(r.address(8 * r.cmd_left + 7 downto 8 * r.cmd_left)));

      when CMD_PUT_DUMMY =>
        cmd_o <= framed_flit(x"00");

      when CMD_PUT_SHIFT_DATA =>
        cmd_o <= framed_flit("01" & std_ulogic_vector(r.chunk_size_m1));

      when CMD_PUT_UNSELECT =>
        cmd_o <= framed_flit("000" & "00" & std_ulogic_vector(unselect_c), last => true);
    end case;

    case r.rsp_state is
      when RSP_IDLE =>
        rsp_o <= framed_accept(false);

      when RSP_GET_SELECT | RSP_GET_UNSELECT
        | RSP_GET_DIV | RSP_GET_SHIFT_DATA | RSP_GET_SHIFT_ADDR =>
        rsp_o <= framed_accept(true);

      when RSP_GET_DATA =>
        rsp_o <= framed_accept(r.fifo_fillness < fifo_depth_c);
    end case;
  end process;

  next_i <= not fifo_out_s.valid;
  
  fifo: nsl_bnoc.framed.framed_fifo
    generic map(
      depth => spi_max_burst_length_c,
      clk_count => 1
      )
    port map(
      p_resetn => reset_n_i,
      p_clk(0) => clock_i,

      p_in_val => fifo_o,
      p_in_ack => fifo_i,

      p_out_val => fifo_out_s,
      p_out_ack => data_i
      );

  data_o <= fifo_out_s;
    
end architecture;
