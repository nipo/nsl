library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_spi, nsl_memory;
use nsl_spi.slave.all;

--          /--------> framed async fifo ---> Sized to framed ---> out
--          |
-- SPI <> shreg
--          ^
--          \--------- framed async fifo <--- Framed to sized <--- in

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

-- RX cont:  MOSI   [c1] [LL] [HH]  [--] x (HHLL + 1)
--           MISO   [--] [--] [--]  [--] x (HHLL + 1)

entity spi_framed_gateway is
  generic(
    msb_first_c   : boolean := true
    );
  port(
    clock_i       : in  std_ulogic;
    reset_n_i    : in  std_ulogic;

    spi_i       : in nsl_spi.spi.spi_slave_i;
    spi_o       : out nsl_spi.spi.spi_slave_o;

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
    ST_FROM_SPI_SIZE_L,
    ST_FROM_SPI_SIZE_H,
    ST_FROM_SPI_DATA,
    ST_TO_SPI_SIZE_L,
    ST_TO_SPI_SIZE_H,
    ST_TO_SPI_DATA,
    ST_TO_SPI_CONT_SIZE_L,
    ST_TO_SPI_CONT_SIZE_H,
    ST_TO_SPI_CONT_DATA,
    ST_OVER
    );
  
  type regs_t is record
    state      : state_t;
    header     : nsl_bnoc.framed.framed_data_t;
    count      : std_ulogic_vector(15 downto 0);
  end record;

  signal r, rin: regs_t;

  signal s_inbound_spi, s_outbound_spi, s_inbound_io, s_outbound_io: nsl_bnoc.sized.sized_bus;
  signal s_from_spi_valid, s_to_spi_ready, s_out_empty_n : std_ulogic;
  signal s_to_spi, s_from_spi : nsl_bnoc.framed.framed_data_t;
    
begin

  bridge_inbound: nsl_bnoc.sized.sized_from_framed
    port map(
      p_resetn => reset_n_i,
      p_clk => clock_i,
      p_in_val => inbound_i,
      p_in_ack => inbound_o,
      p_out_val => s_inbound_io.req,
      p_out_ack => s_inbound_io.ack
      );

  bridge_out: nsl_bnoc.sized.sized_to_framed
    port map(
      p_resetn => reset_n_i,
      p_clk => clock_i,
      p_out_val => outbound_o,
      p_out_ack => outbound_i,
      p_in_val => s_outbound_io.req,
      p_in_ack => s_outbound_io.ack
      );

  resync_in: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => 8,
      data_width_c => 8,
      clock_count_c => 2
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,
      clock_i(1) => spi_i.sck,
      in_valid_i => s_inbound_io.req.valid,
      in_data_i => s_inbound_io.req.data,
      in_ready_o => s_inbound_io.ack.ready,
      out_data_o => s_inbound_spi.req.data,
      out_valid_o => s_inbound_spi.req.valid,
      out_ready_i => s_inbound_spi.ack.ready
      );

  resync_out: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => 8,
      data_width_c => 8,
      clock_count_c => 2
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => spi_i.sck,
      clock_i(1) => clock_i,
      in_valid_i => s_outbound_spi.req.valid,
      in_data_i => s_outbound_spi.req.data,
      in_ready_o => s_outbound_spi.ack.ready,
      out_valid_o => s_outbound_io.req.valid,
      out_data_o => s_outbound_io.req.data,
      out_ready_i => s_outbound_io.ack.ready
      );
  
  shreg: nsl_spi.shift_register.spi_shift_register
    generic map(
      width_c => 8,
      msb_first_c => msb_first_c
      )
    port map(
      spi_i => spi_i,
      spi_o => spi_o,

      tx_data_i => s_to_spi,
      tx_strobe_o => s_to_spi_ready,
      rx_data_o => s_from_spi,
      rx_strobe_o => s_from_spi_valid
      );
  
  regs: process(spi_i.cs_n, spi_i.sck)
  begin
    if spi_i.cs_n = '1' then
      r.state <= ST_CMD;
    elsif rising_edge(spi_i.sck) then
      r <= rin;
    end if;
  end process;

  transition: process(r, s_from_spi, s_from_spi_valid, s_to_spi_ready)
  begin
    rin <= r;
    
    case r.state is
      when ST_CMD =>
        if s_from_spi_valid = '1' then
          if std_match(s_from_spi, SPI_FRAMED_GW_STATUS) then
            rin.state <= ST_STATUS;
          elsif std_match(s_from_spi, SPI_FRAMED_GW_PUT) then
            rin.state <= ST_FROM_SPI_SIZE_L;
          elsif std_match(s_from_spi, SPI_FRAMED_GW_GET) then
            rin.state <= ST_TO_SPI_SIZE_L;
          elsif std_match(s_from_spi, SPI_FRAMED_GW_GET_CONT) then
            rin.state <= ST_TO_SPI_CONT_SIZE_L;
          else
            rin.state <= ST_OVER;
          end if;
        end if;

      when ST_STATUS =>
        if s_to_spi_ready = '1' then
          rin.state <= ST_OVER;
        end if;

      when ST_TO_SPI_SIZE_L =>
        if s_to_spi_ready = '1' then
          rin.state <= ST_TO_SPI_SIZE_H;
          rin.count(7 downto 0) <= s_inbound_spi.req.data;
        end if;

      when ST_TO_SPI_SIZE_H =>
        if s_to_spi_ready = '1' then
          rin.state <= ST_TO_SPI_DATA;
          rin.count(15 downto 8) <= s_inbound_spi.req.data;
        end if;

      when ST_TO_SPI_DATA =>
        if s_to_spi_ready = '1' then
          rin.count <= std_ulogic_vector(unsigned(r.count) - 1);
          if r.count = (r.count'range => '0') then
            rin.state <= ST_OVER;
          end if;
        end if;

      when ST_FROM_SPI_SIZE_L =>
        if s_from_spi_valid = '1' then
          rin.state <= ST_FROM_SPI_SIZE_H;
          rin.count(7 downto 0) <= s_from_spi;
        end if;

      when ST_FROM_SPI_SIZE_H =>
        if s_from_spi_valid = '1' then
          rin.state <= ST_FROM_SPI_DATA;
          rin.count(15 downto 8) <= s_from_spi;
        end if;

      when ST_FROM_SPI_DATA =>
        if s_from_spi_valid = '1' then
          rin.count <= std_ulogic_vector(unsigned(r.count) - 1);
          if r.count = (r.count'range => '0') then
            rin.state <= ST_OVER;
          end if;
        end if;
          
      when ST_TO_SPI_CONT_SIZE_L =>
        if s_from_spi_valid = '1' then
          rin.state <= ST_TO_SPI_CONT_SIZE_H;
          rin.count(7 downto 0) <= s_from_spi;
        end if;

      when ST_TO_SPI_CONT_SIZE_H =>
        if s_from_spi_valid = '1' then
          rin.state <= ST_TO_SPI_CONT_DATA;
          rin.count(15 downto 8) <= s_from_spi;
        end if;

      when ST_TO_SPI_CONT_DATA =>
        if s_to_spi_ready = '1' then
          rin.count <= std_ulogic_vector(unsigned(r.count) - 1);
          if r.count = (r.count'range => '0') then
            rin.state <= ST_OVER;
          end if;
        end if;

      when ST_OVER =>
        null;

    end case;
  end process;

  s_outbound_spi.req.data <= s_from_spi;
    
  spi_dout: process(r, s_outbound_spi.req.data, s_to_spi_ready, s_from_spi_valid)
  begin
    case r.state is
      when ST_STATUS =>
        s_to_spi(7 downto 2) <= (others => '0');
        s_to_spi(1) <= not s_outbound_io.req.valid;
        s_to_spi(0) <= s_inbound_spi.req.valid;

      when ST_TO_SPI_SIZE_H | ST_TO_SPI_SIZE_L
        | ST_TO_SPI_DATA | ST_TO_SPI_CONT_DATA
        | ST_OVER =>
        s_to_spi <= s_inbound_spi.req.data;
        
      when others =>
        s_to_spi <= (others => '-');
--        s_to_spi <= x"81";

    end case;

    case r.state is
      when ST_TO_SPI_SIZE_L | ST_TO_SPI_SIZE_H | ST_TO_SPI_DATA | ST_TO_SPI_CONT_DATA =>
        s_inbound_spi.ack.ready <= s_to_spi_ready;

      when others =>
        s_inbound_spi.ack.ready <= '0';
    end case;

    case r.state is
      when ST_FROM_SPI_SIZE_L | ST_FROM_SPI_SIZE_H | ST_FROM_SPI_DATA =>
        s_outbound_spi.req.valid <= s_from_spi_valid;

      when others =>
        s_outbound_spi.req.valid <= '0';
    end case;

  end process;
  
end architecture;
