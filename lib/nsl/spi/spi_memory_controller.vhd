library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl, signalling, hwdep;

entity spi_memory_controller is
  generic(
    addr_bytes   : natural range 1 to 4          := 1;
    read_opcode  : std_ulogic_vector(7 downto 0) := x"F0";
    write_opcode : std_ulogic_vector(7 downto 0) := x"F8"
    );
  port(
    spi_i          : in signalling.spi.spi_slave_i;
    spi_o          : out signalling.spi.spi_slave_o;
    selected_o     : out std_ulogic;
    mem_addr_o     : out unsigned(addr_bytes*8-1 downto 0);
    mem_r_data_i   : in  std_ulogic_vector(7 downto 0);
    mem_r_strobe_o : out std_ulogic;
    mem_r_done_i   : in  std_ulogic := '1';
    mem_w_data_o   : out std_ulogic_vector(7 downto 0);
    mem_w_strobe_o : out std_ulogic;
    mem_w_done_i   : in  std_ulogic := '1'
    );
end entity;

architecture rtl of spi_memory_controller is

  type st_t is (
    ST_CMD,
    ST_ADDR,
    ST_DATA_INIT,
    ST_DATA
    );

  type regs_t is
  record
    state : st_t;
    addr_bytes_left : natural range 0 to addr_bytes-1;
    addr : unsigned(mem_addr_o'range);
    wdata : std_ulogic_vector(7 downto 0);
    writing, write_pending, read_pending: boolean;
  end record;

  signal r, rin: regs_t;
  signal tx_strobe, rx_strobe : std_ulogic;
  signal tx_data, rx_data : std_ulogic_vector(7 downto 0);

begin

  regs: process(mem_r_done_i, mem_w_done_i, spi_i)
  begin
    if spi_i.cs_n = '1' then
      r.state <= ST_CMD;
      r.writing <= false;
    elsif hwdep.clock.is_rising(spi_i.sck) then
      r <= rin;
    end if;

    if mem_w_done_i = '1' or spi_i.cs_n = '1' then
      r.write_pending <= false;
    end if;

    if mem_r_done_i = '1' or spi_i.cs_n = '1' then
      r.read_pending <= false;
    end if;
  end process;

  transition: process(r, rx_data, rx_strobe, tx_strobe)
  begin
    rin <= r;

    case r.state is
      when ST_CMD =>
        if rx_strobe = '1' then
          rin.addr_bytes_left <= addr_bytes-1;
          rin.addr <= (others => '-');
          if std_match(rx_data, write_opcode) then
            rin.writing <= true;
          end if;
          rin.state <= ST_ADDR;
        end if;

      when ST_ADDR =>
        if rx_strobe = '1' then
          if r.addr_bytes_left = 0 then
            rin.state <= ST_DATA_INIT;
          else
            rin.addr_bytes_left <= r.addr_bytes_left-1;
          end if;
          rin.addr <= r.addr(r.addr'left-8 downto 0) & unsigned(rx_data);
        end if;

      when ST_DATA_INIT =>
        if tx_strobe = '1' then
          rin.state <= ST_DATA;
        end if;

      when ST_DATA =>
        if tx_strobe = '1' then
          rin.addr <= r.addr + 1;
        end if;

        if rx_strobe = '1' then
          if r.writing then
            rin.write_pending <= true;
            rin.wdata <= rx_data;
          else
            -- Set read pending here, it relaxes the timing for downstream
            -- memory implementation.
            rin.read_pending <= true;
          end if;
        end if;
    end case;
  end process;

  mem_addr_o <= r.addr;
  mem_r_strobe_o <= '1' when r.read_pending else '0';
  mem_w_strobe_o <= '1' when r.write_pending else '0';
  mem_w_data_o <= r.wdata when r.write_pending else (others => '-');
  selected_o <= not spi_i.cs_n;
  tx_data <= mem_r_data_i when r.state = ST_DATA else (others => '-');

  shreg: nsl.spi.spi_shift_register
    generic map(
      width => 8,
      msb_first => true
      )
    port map(
      spi_i => spi_i,
      spi_o => spi_o,

      tx_data_i => tx_data,
      tx_strobe_o => tx_strobe,
      rx_data_o => rx_data,
      rx_strobe_o => rx_strobe
      );

end architecture rtl;