library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_memory, nsl_math;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;

entity framed_transactor_once is
  generic(
    config_c : byte_string;
    inter_transaction_cycle_count_c : integer := 0
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;
    done_o      : out std_ulogic;
    enable_i    : in std_ulogic := '1';

    cmd_o  : out framed_req;
    cmd_i  : in framed_ack;
    rsp_i  : in framed_req;
    rsp_o  : out framed_ack
    );
end entity;

architecture beh of framed_transactor_once is

  function rom_init_val(contents: byte_string) return byte_string
  is
    constant rom_size_l2: integer := nsl_math.arith.log2(config_c'length+1);
    variable ret : byte_string(1 to 2**rom_size_l2);
    variable nul: byte := x"00";
  begin
    ret := (others => nul);
    ret(1 to contents'length) := contents;
    return ret;
  end function;
  constant rom_contents: byte_string := rom_init_val(config_c);
  constant rom_addr_size: integer := nsl_math.arith.log2(rom_contents'length);

  subtype addr_t is unsigned(rom_addr_size-1 downto 0);
  signal s_rdata : std_ulogic_vector(7 downto 0);
  signal s_read: std_ulogic;

  type state_t is (
    ST_RESET,
    ST_WAIT_START,
    ST_START,
    ST_SIZE_GET,
    ST_CMD_PUT,
    ST_RSP_WAIT,
    ST_RSP_BACKOFF,
    ST_DONE
    );
  
  type regs_t is
  record
    state: state_t;
    addr : addr_t;
    left : unsigned(7 downto 0);
    timeout: integer range 0 to inter_transaction_cycle_count_c-1;
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
    end if;
  end process;

  transition: process(r, cmd_i, rsp_i, s_rdata, enable_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_WAIT_START;
        
      when ST_WAIT_START =>
        rin.addr <= (others => '0');
        if enable_i = '1' then
          rin.state <= ST_START;
        end if;

      when ST_START =>
        rin.state <= ST_SIZE_GET;
        rin.addr <= r.addr + 1;

      when ST_SIZE_GET =>
        rin.addr <= r.addr + 1;
        rin.left <= unsigned(s_rdata);
        if s_rdata = (s_rdata'range => '0') then
          rin.state <= ST_DONE;
        else
          rin.state <= ST_CMD_PUT;
        end if;

      when ST_CMD_PUT =>
        if cmd_i.ready = '1' then
          rin.left <= r.left - 1;
          if r.left = 0 then
            rin.state <= ST_RSP_WAIT;
          else
            rin.addr <= r.addr + 1;
            rin.state <= ST_CMD_PUT;
          end if;
        end if;

      when ST_RSP_WAIT =>
        if rsp_i.valid = '1' and rsp_i.last = '1' then
          if inter_transaction_cycle_count_c /= 0 then
            rin.state <= ST_RSP_BACKOFF;
            rin.timeout <= inter_transaction_cycle_count_c -  1;
          else
            rin.state <= ST_START;
          end if;
        end if;

      when ST_RSP_BACKOFF =>
        if r.timeout /= 0 then
          rin.timeout <= r.timeout - 1;
        else
          rin.state <= ST_START;
        end if;

      when ST_DONE =>
        if enable_i = '0' then
          rin.state <= ST_WAIT_START;
        end if;

    end case;
  end process;

  done_o <= '1' when r.state = ST_DONE else '0';
  cmd_o.data <= std_ulogic_vector(s_rdata);

  mealy: process(r, cmd_i) is
  begin
    s_read <= '0';

    case r.state is
      when ST_START | ST_SIZE_GET =>
        s_read <= '1';

      when ST_CMD_PUT =>
        if r.left /= 0 then
          s_read <= cmd_i.ready;
        end if;

      when others =>
        null;
    end case;
  end process;
  
  moore: process(r) is
  begin
    cmd_o.valid <= '0';
    cmd_o.last <= '-';
    rsp_o.ready <= '0';

    case r.state is
      when ST_RESET | ST_START | ST_SIZE_GET | ST_DONE | ST_WAIT_START =>
        null;
        
      when ST_CMD_PUT =>
        cmd_o.valid <= '1';
        cmd_o.last <= '0';
        if r.left = 0 then
          cmd_o.last <= '1';
        end if;
        rsp_o.ready <= '1';

      when ST_RSP_WAIT =>
        rsp_o.ready <= '1';
    end case;
  end process;
  
  rom: nsl_memory.rom.rom_bytes
    generic map(
      word_addr_size_c => r.addr'length,
      word_byte_count_c => 1,
      contents_c => rom_contents
      )
    port map(
      clock_i => clock_i,

      read_i => s_read,
      address_i => r.addr,
      data_o => s_rdata
      );
  
end architecture;
