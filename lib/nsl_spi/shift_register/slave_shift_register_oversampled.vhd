library ieee;
use ieee.std_logic_1164.all;

library nsl_spi, nsl_logic, nsl_clocking;
use nsl_logic.bool.all;

entity slave_shift_register_oversampled is
  generic(
    width_c : natural;
    msb_first_c : boolean := true;
    cs_n_active_c : std_ulogic := '0'
    );
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

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
    dout_left : natural range 0 to width_c - 1;
    dout_shreg : std_ulogic_vector(width_c - 1 downto 0);
    dout_refill: boolean;
    din_left : natural range 0 to width_c - 1;
    din_shreg : std_ulogic_vector(width_c - 1 downto 0);

    rx : std_ulogic_vector(width_c - 1 downto 0);
    rx_valid : std_ulogic;
    active : std_ulogic;
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

  signal spi_i_s : nsl_spi.spi.spi_slave_i;
  signal cs_fall, cs_rise: std_ulogic;
  signal sck_fall, sck_rise: std_ulogic;
  signal cs_begin, cs_end: std_ulogic;
  signal sck_lead, sck_tail: std_ulogic;

begin

  sck_sync: nsl_clocking.async.async_input
    generic map(
      sample_count_c => 1,
      debounce_count_c => 0
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      data_i => spi_i.sck,
      data_o => spi_i_s.sck,
      falling_o => sck_fall,
      rising_o => sck_rise
      );

  sck_lead <= sck_rise when cpol_i = '0' else sck_fall;
  sck_tail <= sck_fall when cpol_i = '0' else sck_rise;
  
  mosi_sync: nsl_clocking.async.async_input
    generic map(
      sample_count_c => 0,
      debounce_count_c => 2
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      data_i => spi_i.mosi,
      data_o => spi_i_s.mosi
      );

  cs_n_sync: nsl_clocking.async.async_input
    generic map(
      sample_count_c => 0,
      debounce_count_c => 2
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      data_i => spi_i.cs_n,
      data_o => spi_i_s.cs_n,
      falling_o => cs_fall,
      rising_o => cs_rise
      );

  cs_begin <= cs_fall when cs_n_active_c = '0' else cs_rise;
  cs_end <= cs_rise when cs_n_active_c = '0' else cs_fall;

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.dout_shreg <= (others => '0');
      r.active <= '0';
      r.rx_valid <= '0';
      r.dout_refill <= false;
    end if;
  end process;

  transition: process(r, spi_i_s, tx_data_i, cs_begin, cs_end, sck_lead, sck_tail, cpol_i, cpha_i) is
    variable take, put: boolean;
  begin
    rin <= r;

    take := false;
    put := false;

    rin.dout_refill <= false;
    rin.rx_valid <= '0';

    if spi_i_s.cs_n /= cs_n_active_c then
      rin.din_shreg <= (others => '-');
      rin.dout_shreg <= (others => '-');
      rin.rx <= (others => '-');
      rin.dout_refill <= false;
      rin.din_left <= 0;
      rin.dout_left <= 0;
    else
      if sck_lead = '1' then
        if cpha_i = '0' then
          take := true;
        else
          put := true;
        end if;
      end if;
      if sck_tail = '1' then
        if cpha_i = '0' then
          put := true;
        else
          take := true;
        end if;
      end if;
    end if;

    if cs_begin = '1' then
      rin.active <= '1';
      if cpha_i = '0' and spi_i_s.sck = cpol_i then
        rin.dout_refill <= true;
      else
        rin.dout_left <= 0;
      end if;
      rin.din_left <= width_c - 1;
    end if;

    if cs_end = '1' then
      rin.active <= '0';
    end if;

    if r.dout_refill then
      rin.dout_shreg <= tx_data_i;
      rin.dout_left <= width_c - 1;
    end if;

    if take then
      if r.din_left /= 0 then
        rin.din_left <= r.din_left - 1;
        rin.din_shreg <= shreg_shift(r.din_shreg, spi_i_s.mosi);
      else
        rin.din_shreg <= (others => '-');
        rin.din_left <= width_c - 1;
        rin.rx <= shreg_shift(r.din_shreg, spi_i_s.mosi);
        rin.rx_valid <= '1';
      end if;
    end if;
    
    if put then
      rin.dout_shreg <= shreg_shift(r.dout_shreg, '-');
      if r.dout_left = 0 then
        rin.dout_refill <= true;
        rin.dout_left <= width_c - 1;
      else
        rin.dout_left <= r.dout_left - 1;
      end if;
    end if;
  end process;

  spi_o.miso.v <= shreg_out(r.dout_shreg);
  spi_o.miso.en <= r.active;
  tx_ready_o <= to_logic(r.dout_refill);
  rx_data_o <= r.rx;
  rx_valid_o <= r.rx_valid;
  active_o <= r.active;

end architecture;
