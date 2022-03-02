library ieee;
use ieee.std_logic_1164.all;

library nsl_spi, nsl_logic;
use nsl_logic.bool.all;

entity slave_shift_register_oversampled is
  generic(
    width_c : natural;
    msb_first_c : boolean := true;
    cs_n_active_c : std_ulogic := '0'
    );
  port(
    clock_i     : in std_ulogic;

    cpol_i : in std_ulogic := '0';
    cpha_i : in std_ulogic := '0';

    spi_i       : in nsl_spi.spi.spi_slave_i;
    spi_o       : out nsl_spi.spi.spi_slave_o;

    active_o    : out std_ulogic;
    
    tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
    tx_ready_o  : out std_ulogic;

    rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
    rx_valid_o  : out std_ulogic
    );
end entity;

architecture rtl of slave_shift_register_oversampled is
  
  type regs_t is record
    sck: std_ulogic;
    cs_n: std_ulogic;

    bit_idx : natural range 0 to width_c - 1;
    shreg : std_ulogic_vector(width_c - 1 downto 0);
    first, refill: boolean;

    din: std_ulogic;

    rx : std_ulogic_vector(width_c - 1 downto 0);
    rx_valid : std_ulogic;
  end record;

  signal r, rin: regs_t;
  
  function shreg_out(shreg : in std_ulogic_vector) return std_ulogic is
  begin
    if msb_first_c then
      return shreg(shreg'left);
    else
      return shreg(shreg'right);
    end if;
  end function;

  function shreg_shift(shreg : in std_ulogic_vector; din : std_ulogic) return std_ulogic_vector is
  begin
    if msb_first_c then
      return shreg(shreg'left-1 downto 0) & din;
    else
      return din & shreg(shreg'left downto 1);
    end if;
  end function;

begin

  regs: process(clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, spi_i, tx_data_i) is
    variable sample, shift: boolean;
  begin
    rin <= r;

    sample := false;
    shift := false;

    rin.refill <= false;
    rin.rx_valid <= '0';
    rin.sck <= spi_i.sck;
    rin.cs_n <= spi_i.cs_n;

    if spi_i.cs_n /= cs_n_active_c then
      rin.first <= true;
      rin.shreg <= (others => '-');
      rin.rx <= (others => '-');
      rin.refill <= false;

      if cpha_i = '0' then
        rin.bit_idx <= 0;
      else
        rin.bit_idx <= width_c - 1;
      end if;
    end if;

    if spi_i.cs_n /= r.cs_n and spi_i.cs_n = cs_n_active_c then
      rin.refill <= true;
    end if;

    if rin.refill then
      rin.shreg <= tx_data_i;
    end if;

    if spi_i.cs_n = cs_n_active_c
      and spi_i.sck /= r.sck then
        if spi_i.sck /= cpol_i then
          if cpha_i = '0' then
            sample := true;
          else
            shift := true;
          end if;
        else
          if cpha_i = '0' then
            shift := true;
          else
            sample := true;
          end if;
        end if;
    end if;

    if sample then
      rin.din <= spi_i.mosi;
      rin.first <= false;
      if r.bit_idx = width_c - 1 then
        rin.rx <= shreg_shift(r.shreg, spi_i.mosi);
        rin.rx_valid <= to_logic(not r.first);
      end if;
    end if;
    
    if shift then
      if r.bit_idx = width_c - 1 then
        rin.bit_idx <= 0;
        rin.refill <= not r.first;
      else
        rin.bit_idx <= r.bit_idx + 1;
        rin.shreg <= shreg_shift(r.shreg, r.din);
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    spi_o.miso <= shreg_out(r.shreg);
    tx_ready_o <= to_logic(r.refill);
    rx_data_o <= r.rx;
    rx_valid_o <= r.rx_valid;
    active_o <= to_logic(r.cs_n = cs_n_active_c);
  end process;

end architecture;
