library ieee;
use ieee.std_logic_1164.all;

library nsl_spi;

entity spi_fifo_transport_master is
  generic(
    width_c : positive;
    -- SPI Clock divisor from fifo clock
    divisor_c : integer range 2 to 65536
    );
  port(
    -- clocks the fifo
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;

    spi_o       : out nsl_spi.spi.spi_slave_i;
    spi_i       : in  nsl_spi.spi.spi_slave_o;
    irq_n_i     : in  std_ulogic;

    tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
    tx_valid_i  : in  std_ulogic;
    tx_ready_o  : out std_ulogic;

    rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
    rx_valid_o  : out std_ulogic;
    rx_ready_i  : in  std_ulogic
    );
end entity;

architecture beh of spi_fifo_transport_master is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_SHIFT_START,
    ST_SHIFT_L,
    ST_SHIFT_H,
    ST_SHIFT_END
    );

  subtype shreg_t is std_ulogic_vector(width_c+2-1 downto 0);
  -- Ready, Valid, Data[width_c]
  
  type regs_t is
  record
    state : state_t;
    rxd, txd : std_ulogic_vector(width_c-1 downto 0);
    rxd_valid, txd_valid : std_ulogic;

    shreg : shreg_t;
    mosi : std_ulogic;
    left : natural range 0 to shreg_t'length - 1;
    div : natural range 0 to divisor_c;
    pad_count : natural range 0 to 3;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, spi_i, irq_n_i, tx_data_i, tx_valid_i, rx_ready_i)
    variable peer_ready, peer_valid : std_ulogic;
    variable peer_data : std_ulogic_vector(width_c-1 downto 0);
  begin
    rin <= r;
    peer_ready := r.shreg(r.shreg'left);
    peer_valid := r.shreg(r.shreg'left-1);
    peer_data := r.shreg(width_c-1 downto 0);

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.div <= divisor_c - 1;
        rin.rxd_valid <= '0';
        rin.txd_valid <= '0';
        rin.pad_count <= 3;

      when ST_IDLE =>
        if r.div /= 0 then
          rin.div <= r.div - 1;
        elsif irq_n_i = '0' or r.txd_valid = '1' then
          rin.state <= ST_SHIFT_START;
          rin.div <= divisor_c - 1;
        elsif r.pad_count /= 0 then
          rin.pad_count <= r.pad_count - 1;
          rin.state <= ST_SHIFT_START;
          rin.div <= divisor_c - 1;
        end if;

      when ST_SHIFT_START =>
        if r.div /= 0 then
          rin.div <= r.div - 1;
        else
          rin.left <= shreg_t'length - 1;
          rin.shreg <= (not r.rxd_valid) & r.txd_valid & r.txd;
          rin.state <= ST_SHIFT_L;
          rin.div <= divisor_c - 1;
        end if;

      when ST_SHIFT_L =>
        rin.mosi <= r.shreg(r.shreg'left);
        if r.div /= 0 then
          rin.div <= r.div - 1;
        else
          rin.state <= ST_SHIFT_H;
          rin.div <= divisor_c - 1;
          rin.shreg <= r.shreg(r.shreg'left - 1 downto 0) & spi_i.miso;
        end if;

      when ST_SHIFT_H =>
        if r.div /= 0 then
          rin.div <= r.div - 1;
        elsif r.left /= 0 then
          rin.left <= r.left - 1;
          rin.state <= ST_SHIFT_L;
          rin.div <= divisor_c - 1;
        else
          rin.state <= ST_SHIFT_END;
          rin.div <= divisor_c - 1;
        end if;

      when ST_SHIFT_END =>
        if r.div /= 0 then
          rin.div <= r.div - 1;
        else
          rin.left <= width_c + 1;
          rin.state <= ST_IDLE;
          rin.div <= divisor_c - 1;
        end if;
    end case;

    case r.state is
      when ST_IDLE =>
        if r.txd_valid = '0' and tx_valid_i = '1' then
          rin.pad_count <= 1;
          rin.txd <= tx_data_i;
          rin.txd_valid <= '1';
        end if;

        if r.rxd_valid = '1' and rx_ready_i = '1' then
          rin.pad_count <= 1;
          rin.rxd_valid <= '0';
        end if;

      when ST_SHIFT_END =>
        if peer_ready = '1' and r.txd_valid = '1' then
          rin.pad_count <= 1;
          rin.txd_valid <= '0';
        end if;
        
        if peer_valid = '1' and r.rxd_valid = '0' then
          rin.pad_count <= 1;
          rin.rxd_valid <= '1';
          rin.rxd <= peer_data;
        end if;

      when others =>
        null;
    end case;

  end process;

  moore: process(r)
  begin
    spi_o.cs_n <= '1';
    spi_o.sck <= '0';
    spi_o.mosi <= r.mosi;
    tx_ready_o <= '0';
    rx_data_o <= (others => '-');
    rx_valid_o <= '0';

    case r.state is
      when ST_IDLE =>
        tx_ready_o <= not r.txd_valid;
        rx_data_o <= r.rxd;
        rx_valid_o <= r.rxd_valid;

      when others =>
        null;
    end case;

    case r.state is
      when ST_SHIFT_END | ST_SHIFT_START | ST_SHIFT_L =>
        spi_o.cs_n <= '0';

      when ST_SHIFT_H =>
        spi_o.cs_n <= '0';
        spi_o.sck <= '1';

      when others =>
        null;
    end case;
  end process;

end architecture;
