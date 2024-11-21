library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_data, nsl_bnoc, nsl_math, nsl_memory;
use nsl_bnoc.framed.all;
use nsl_bnoc.pipe.all;
use nsl_data.bytestream.all;

entity spi_pipe_source is
  generic(
    timeout_c : positive;
    buffer_size_c: integer range 1 to 64
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    pipe_i  : in nsl_bnoc.pipe.pipe_req_t;
    pipe_o  : out nsl_bnoc.pipe.pipe_ack_t;
    
    cpol_i : in std_ulogic := '0';
    cpha_i : in std_ulogic := '0';
    slave_i : in unsigned(2 downto 0) := "000";
    div_i : in unsigned(6 downto 0) := "0000000";

    spi_cmd_o  : out nsl_bnoc.framed.framed_req_t;
    spi_cmd_i  : in nsl_bnoc.framed.framed_ack_t;

    spi_rsp_i  : in nsl_bnoc.framed.framed_req_t;
    spi_rsp_o  : out nsl_bnoc.framed.framed_ack_t
    );
end entity;

architecture rtl of spi_pipe_source is

  type cmd_st_t is (
    CMD_RESET,
    CMD_IDLE,
    CMD_PUT_DIVH,
    CMD_PUT_DIVL,
    CMD_PUT_SELECT,
    CMD_FILL,
    CMD_PUT_SHIFT,
    CMD_PUT_DATA_PIPE,
    CMD_PUT_DATA_SEEK,
    CMD_PUT_DATA_LAST,
    CMD_PUT_UNSELECT
    );

  type rsp_st_t is (
    RSP_RESET,
    RSP_IDLE,
    RSP_GET_DONE
    );
  
  constant ram_address_w: natural := nsl_math.arith.log2(buffer_size_c);

  type regs_t is
  record
    cmd_state : cmd_st_t;

    size_m1: unsigned(5 downto 0);
    address: unsigned(ram_address_w-1 downto 0);
    done: boolean;
    timeout: natural range 0 to timeout_c-1;

    rsp_state : rsp_st_t;
  end record;

  signal r, rin: regs_t;

  signal ram_rdata_s: byte;
  signal ram_en_s: std_ulogic;
  signal ram_write_s: std_ulogic;

begin

  ram: nsl_memory.ram.ram_1p
    generic map(
      addr_size_c => ram_address_w,
      data_size_c => 8
      )
    port map(
      clock_i => clock_i,

      address_i => r.address,
      enable_i => ram_en_s,

      write_en_i => ram_write_s,
      write_data_i => pipe_i.data,

      read_data_o => ram_rdata_s
      );

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.cmd_state <= CMD_RESET;
      r.rsp_state <= RSP_RESET;
    end if;
  end process;
  
  transition: process(r, pipe_i, spi_cmd_i, spi_rsp_i, ram_rdata_s) is
  begin
    rin <= r;
    
    case r.cmd_state is
      when CMD_RESET =>
        rin.cmd_state <= CMD_IDLE;

      when CMD_IDLE =>
        if pipe_i.valid = '1' and r.rsp_state = RSP_IDLE then
          rin.cmd_state <= CMD_PUT_DIVH;
        end if;

      when CMD_PUT_DIVH =>
        if spi_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_DIVL;
        end if;

      when CMD_PUT_DIVL =>
        if spi_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_SELECT;
        end if;

      when CMD_PUT_SELECT =>
        if spi_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_FILL;
          rin.timeout <= timeout_c - 1;
          rin.address <= (others => '0');
          rin.done <= false;
        end if;

      when CMD_FILL =>
        if pipe_i.valid = '1' then
          rin.address <= r.address + 1;
          rin.timeout <= timeout_c - 1;

          if r.address = buffer_size_c-1 then
            rin.cmd_state <= CMD_PUT_SHIFT;
            rin.size_m1 <= resize(r.address, r.size_m1'length);
          end if;
        elsif r.timeout /= 0 then
          rin.timeout <= r.timeout - 1;
        else
          rin.done <= true;
          rin.address <= (others => '0');
          if r.address = 0 then
            rin.cmd_state <= CMD_PUT_UNSELECT;
          else
            rin.cmd_state <= CMD_PUT_SHIFT;
            rin.size_m1 <= resize(r.address - 1, r.size_m1'length);
          end if;
        end if;

      when CMD_PUT_SHIFT =>
        if spi_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_DATA_PIPE;
          rin.address <= r.address + 1;
        end if;

      when CMD_PUT_DATA_SEEK =>
        rin.cmd_state <= CMD_PUT_DATA_PIPE;
        rin.address <= r.address + 1;

      when CMD_PUT_DATA_PIPE =>
        if spi_cmd_i.ready = '1' then
          if resize(r.address, r.size_m1'length) = r.size_m1 then
            rin.cmd_state <= CMD_PUT_DATA_LAST;
          else
            rin.address <= r.address + 1;
          end if;
        else
          rin.cmd_state <= CMD_PUT_DATA_SEEK;
          rin.address <= r.address - 1;
        end if;

      when CMD_PUT_DATA_LAST =>
        if spi_cmd_i.ready = '1' then
          if r.done then
            rin.cmd_state <= CMD_PUT_UNSELECT;
          else
            rin.cmd_state <= CMD_FILL;
            rin.timeout <= timeout_c - 1;
            rin.address <= (others => '0');
            rin.done <= false;
          end if;
        end if;
        
      when CMD_PUT_UNSELECT =>
        if spi_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_IDLE;
        end if;
    end case;

    case r.rsp_state is
      when RSP_RESET =>
        rin.rsp_state <= RSP_IDLE;

      when RSP_IDLE =>
        if r.cmd_state = CMD_PUT_DIVH then
          rin.rsp_state <= RSP_GET_DONE;
        end if;

      when RSP_GET_DONE =>
        if spi_rsp_i.valid = '1' and spi_rsp_i.last = '1' then
          rin.rsp_state <= RSP_IDLE;
        end if;
    end case;
  end process;

  outputs: process(r, div_i, slave_i, cpha_i, cpol_i, ram_rdata_s) is
  begin
    spi_cmd_o <= framed_req_idle_c;
    spi_rsp_o <= framed_ack_idle_c;
    pipe_o <= pipe_ack_idle_c;
    ram_en_s <= '0';
    ram_write_s <= '0';

    case r.cmd_state is
      when CMD_RESET | CMD_IDLE =>
        null;

      when CMD_PUT_DIVH =>
        spi_cmd_o <= framed_flit(data => "0010" & std_ulogic_vector(div_i(6 downto 3)));

      when CMD_PUT_DIVL =>
        spi_cmd_o <= framed_flit(data => "00110" & std_ulogic_vector(div_i(2 downto 0)));

      when CMD_PUT_SELECT =>
        spi_cmd_o <= framed_flit(data => "000" & cpol_i & cpha_i & std_ulogic_vector(slave_i));

      when CMD_FILL =>
        ram_en_s <= '1';
        ram_write_s <= '1';
        pipe_o <= pipe_accept(true);

      when CMD_PUT_SHIFT =>
        spi_cmd_o <= framed_flit(data => "10" & std_ulogic_vector(r.size_m1));
        ram_en_s <= '1';

      when CMD_PUT_DATA_SEEK =>
        ram_en_s <= '1';

      when CMD_PUT_DATA_PIPE =>
        spi_cmd_o <= framed_flit(data => ram_rdata_s);
        ram_en_s <= '1';

      when CMD_PUT_DATA_LAST =>
        spi_cmd_o <= framed_flit(data => ram_rdata_s);
        ram_en_s <= '1';
        
      when CMD_PUT_UNSELECT =>
        spi_cmd_o <= framed_flit(data => "000" & cpol_i & cpha_i & "111", last => true);
    end case;

    case r.rsp_state is
      when RSP_RESET | RSP_IDLE =>
        null;

      when RSP_GET_DONE =>
        spi_rsp_o <= framed_accept(true);
    end case;
  end process;

end architecture rtl;
