library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_spi, nsl_memory;
use nsl_spi.slave.all;

--          /---------> Sized to framed ---> out
--          |
-- SPI <> shreg
--          ^
--          \---------< Framed to sized <--- in

-- Status register:   "000000xx"
--                           ^^
--                           ||
--    TX buffer ready -------/|
--    RX txn pending  --------/

-- Status reg query: MOSI   [00] [--]
--                   MISO   [--] [SS]

-- TX query: MOSI   [80] [LL] [HH]  [--] x (HHLL + 1)
--           MISO   [--] [--] [--]  [--] x (HHLL + 1)

-- RX query: MOSI   [c0] [--] [--]  [--] x (HHLL + 1)
--           MISO   [--] [LL] [HH]  [--] x (HHLL + 1)

entity spi_framed_gateway is
  generic(
    msb_first_c   : boolean := true;
    max_txn_length_c : positive := 128
    );
  port(
    clock_i       : in  std_ulogic;
    reset_n_i    : in  std_ulogic;

    spi_i       : in nsl_spi.spi.spi_slave_i;
    spi_o       : out nsl_spi.spi.spi_slave_o;
    
    cpol_i : in std_ulogic := '0';
    cpha_i : in std_ulogic := '0';

    outbound_o   : out nsl_bnoc.framed.framed_req;
    outbound_i   : in  nsl_bnoc.framed.framed_ack;
    inbound_i    : in  nsl_bnoc.framed.framed_req;
    inbound_o    : out nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of spi_framed_gateway is

  type state_t is (
    ST_CMD,
    ST_STATUS,
    ST_FROM_SPI_DATA,
    ST_TO_SPI_DATA,
    ST_OVER
    );
  
  type regs_t is record
    state : state_t;
    tmp   : nsl_bnoc.framed.framed_data_t;
    invert : boolean;
  end record;

  signal r, rin: regs_t;

  signal s_inbound, s_outbound: nsl_bnoc.sized.sized_bus;
  signal s_from_spi_valid, s_selected : std_ulogic;
  signal s_to_spi, s_from_spi : nsl_bnoc.framed.framed_data_t;
    
begin

  bridge_inbound: nsl_bnoc.sized.sized_from_framed
    generic map(
      max_txn_length => max_txn_length_c
      )
    port map(
      p_resetn => reset_n_i,
      p_clk => clock_i,
      p_in_val => inbound_i,
      p_in_ack => inbound_o,
      p_out_val => s_inbound.req,
      p_out_ack => s_inbound.ack
      );

  bridge_out: nsl_bnoc.sized.sized_to_framed
    port map(
      p_resetn => reset_n_i,
      p_clk => clock_i,
      p_out_val => outbound_o,
      p_out_ack => outbound_i,
      p_in_val => s_outbound.req,
      p_in_ack => s_outbound.ack
      );
  
  shreg: nsl_spi.shift_register.slave_shift_register_oversampled
    generic map(
      width_c => 8,
      msb_first_c => msb_first_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      spi_i => spi_i,
      spi_o => spi_o,

      cpol_i => cpol_i,
      cpha_i => cpha_i,
      
      active_o => s_selected,
      tx_data_i => s_to_spi,
      rx_data_o => s_from_spi,
      rx_valid_o => s_from_spi_valid
      );
  
  regs: process(clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, s_from_spi, s_from_spi_valid, s_selected, s_inbound)
  begin
    rin <= r;
    
    case r.state is
      when ST_CMD =>
        if s_from_spi_valid = '1' then
          if std_match(s_from_spi, SPI_FRAMED_GW_STATUS) then
            rin.state <= ST_STATUS;
          elsif std_match(s_from_spi, SPI_FRAMED_GW_PUT) then
            rin.state <= ST_FROM_SPI_DATA;
          elsif std_match(s_from_spi, SPI_FRAMED_GW_GET) then
            if s_inbound.req.valid = '0' then
              rin.state <= ST_OVER;
              rin.tmp <= x"ee";
            else
              rin.state <= ST_TO_SPI_DATA;
            end if;
          else
            rin.state <= ST_OVER;
            rin.tmp <= x"ba";
          end if;
        end if;

      when ST_STATUS =>
        if s_from_spi_valid = '1' then
          rin.state <= ST_OVER;
          rin.tmp <= x"ff";
        end if;

      when ST_FROM_SPI_DATA =>
        null;

      when ST_TO_SPI_DATA =>
        if s_from_spi_valid = '1' then
          if s_inbound.req.valid = '0' then
            rin.state <= ST_OVER;
            rin.tmp <= x"ee";
          end if;
        end if;

      when ST_OVER =>
        null;

    end case;

    if s_selected = '0' then
      rin.state <= ST_CMD;
    end if;
  end process;

    
  spi_dout: process(r, s_outbound.ack, s_from_spi_valid, s_from_spi, s_inbound.req)
  begin
    s_to_spi <= x"ff";
    s_inbound.ack.ready <= '0';
    s_outbound.req.valid <= '0';
    s_outbound.req.data <= (others => '-');

    case r.state is
      when ST_STATUS =>
        s_to_spi(7 downto 2) <= (others => '0');
        s_to_spi(1) <= s_outbound.ack.ready;
        s_to_spi(0) <= s_inbound.req.valid;

      when ST_TO_SPI_DATA =>
        -- Postpone reading ack to full byte transfer
        s_to_spi <= s_inbound.req.data;
        s_inbound.ack.ready <= s_from_spi_valid;

      when ST_FROM_SPI_DATA =>
        s_outbound.req.valid <= s_from_spi_valid;
        s_outbound.req.data <= s_from_spi;

      when ST_OVER =>
        s_to_spi <= r.tmp;

      when others =>
        null;
    end case;

  end process;
  
end architecture;
