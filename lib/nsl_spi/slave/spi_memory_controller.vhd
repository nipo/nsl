library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_data, nsl_logic;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;

entity spi_memory_controller is
  generic(
    addr_bytes_c   : natural range 1 to 4 := 1;
    data_bytes_c   : natural range 1 to 4 := 1;
    write_opcode_c : byte := x"0b"
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    spi_i          : in nsl_spi.spi.spi_slave_i;
    spi_o          : out nsl_spi.spi.spi_slave_o;
    
    cpol_i : in std_ulogic := '0';
    cpha_i : in std_ulogic := '0';

    selected_o     : out std_ulogic;

    addr_o  : out unsigned(addr_bytes_c*8-1 downto 0);

    rdata_i  : in  byte_string(0 to data_bytes_c-1);
    rready_o : out std_ulogic;
    rvalid_i : in  std_ulogic := '1';

    wdata_o  : out byte_string(0 to data_bytes_c-1);
    wvalid_o : out std_ulogic;
    wready_i : in  std_ulogic := '1'
    );
end entity;

architecture rtl of spi_memory_controller is

  type st_t is (
    ST_IDLE,
    ST_CMD,
    ST_ADDR,
    ST_WRITE,
    ST_READ
    );

  type regs_t is
  record
    state : st_t;
    addr_left : natural range 0 to addr_bytes_c-1;
    data_left : natural range 0 to data_bytes_c-1;
    addr : byte_string(0 to addr_bytes_c-1);
    data : byte_string(0 to data_bytes_c-1);

    writing: boolean;

    mem_read_pending, mem_write_pending : boolean;
  end record;

  signal r, rin: regs_t;
  signal to_spi_ready_s, from_spi_valid_s, active_s : std_ulogic;
  signal to_spi_data_s, from_spi_data_s : std_ulogic_vector(7 downto 0);

begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_IDLE;
      r.mem_write_pending <= false;
      r.mem_read_pending <= false;
    end if;
  end process;

  transition: process(r, to_spi_ready_s, from_spi_valid_s, active_s, to_spi_data_s, from_spi_data_s,
                      rvalid_i, rdata_i, wready_i)
  begin
    rin <= r;

    case r.state is
      when ST_IDLE =>
        if active_s = '1' then
          rin.state <= ST_CMD;
        end if;

      when ST_CMD =>
        if from_spi_valid_s = '1' then
          rin.writing <= from_spi_data_s = write_opcode_c;
          rin.state <= ST_ADDR;
          rin.addr_left <= addr_bytes_c - 1;
        end if;

      when ST_ADDR =>
        if from_spi_valid_s = '1' then
          rin.state <= ST_ADDR;
          if r.addr_left = 0 then
            if r.writing then
              rin.data_left <= data_bytes_c - 1;
              rin.state <= ST_WRITE;
            else
              rin.data_left <= data_bytes_c - 1;
              rin.state <= ST_READ;
              rin.mem_read_pending <= true;
            end if;
          else
            rin.addr_left <= r.addr_left - 1;
          end if;
          rin.addr <= shift_left(r.addr, from_spi_data_s);
        end if;
        
      when ST_READ =>
        if to_spi_ready_s = '1' then
          if r.data_left = 0 then
            rin.data_left <= data_bytes_c - 1;
            rin.mem_read_pending <= true;
            rin.addr <= to_be(from_be(r.addr) + 1);
          else
            rin.data <= shift_left(r.data);
            rin.data_left <= r.data_left - 1;
          end if;
        end if;

      when ST_WRITE =>
        if from_spi_valid_s = '1' then
          rin.data <= shift_left(r.data, from_spi_data_s);
          if r.data_left = 0 then
            rin.mem_write_pending <= true;
            rin.data_left <= data_bytes_c - 1;
          else
            rin.data_left <= r.data_left - 1;
          end if;
        end if;

    end case;

    if r.mem_read_pending and rvalid_i = '1' then
      rin.data <= rdata_i;
      rin.mem_read_pending <= false;
    end if;

    if r.mem_write_pending and wready_i = '1' then
      rin.addr <= to_be(from_be(r.addr) + 1);
      rin.mem_write_pending <= false;
    end if;

    if active_s = '0' then
      rin.state <= ST_IDLE;
      rin.addr <= (others => dontcare_byte_c);
      rin.data <= (others => dontcare_byte_c);
    end if;
    
  end process;

  addr_o <= from_be(r.addr);
  rready_o <= to_logic(r.mem_read_pending);
  wvalid_o <= to_logic(r.mem_write_pending);
  wdata_o <= r.data;
  selected_o <= to_logic(r.state /= ST_IDLE);
  to_spi_data_s <= first_left(r.data) when r.state = ST_READ else dontcare_byte_c;

  shreg: nsl_spi.shift_register.slave_shift_register_oversampled
    generic map(
      width_c => 8,
      msb_first_c => true,
      cs_n_active_c => '0'
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      spi_i => spi_i,
      spi_o => spi_o,

      cpol_i => cpol_i,
      cpha_i => cpha_i,

      active_o => active_s,
      tx_data_i => to_spi_data_s,
      tx_ready_o => to_spi_ready_s,
      rx_data_o => from_spi_data_s,
      rx_valid_o => from_spi_valid_s
      );

end architecture rtl;
