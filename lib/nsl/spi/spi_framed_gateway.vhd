library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.spi.all;
use nsl.fifo.all;
use nsl.framed.all;
use nsl.sized.all;

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
    msb_first   : boolean := true
    );
  port(
    p_framed_clk       : in  std_ulogic;
    p_framed_resetn    : in  std_ulogic;

    p_sck       : in  std_ulogic;
    p_csn       : in  std_ulogic;
    p_miso      : out std_ulogic;
    p_mosi      : in  std_ulogic;

    p_out_val   : out framed_req;
    p_out_ack   : in  framed_ack;
    p_in_val    : in  framed_req;
    p_in_ack    : out framed_ack
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
    header     : framed_data_t;
    count      : std_ulogic_vector(15 downto 0);
  end record;

  signal r, rin: regs_t;

  signal s_in_spi, s_out_spi, s_in_io, s_out_io: sized_bus;
  signal s_from_spi_valid, s_to_spi_ready, s_out_empty_n : std_ulogic;
  signal s_to_spi, s_from_spi : framed_data_t;
    
begin

  bridge_in: sized_from_framed
    port map(
      p_resetn => p_framed_resetn,
      p_clk => p_framed_clk,
      p_in_val => p_in_val,
      p_in_ack => p_in_ack,
      p_out_val => s_in_io.req,
      p_out_ack => s_in_io.ack
      );

  bridge_out: sized_to_framed
    port map(
      p_resetn => p_framed_resetn,
      p_clk => p_framed_clk,
      p_out_val => p_out_val,
      p_out_ack => p_out_ack,
      p_in_val => s_out_io.req,
      p_in_ack => s_out_io.ack
      );

  resync_in: fifo_async
    generic map(
      depth => 8,
      data_width => 8
      )
    port map(
      p_resetn => p_framed_resetn,
      p_in_clk => p_framed_clk,
      p_out_clk => p_sck,
      p_in_valid => s_in_io.req.valid,
      p_in_data => s_in_io.req.data,
      p_in_ready => s_in_io.ack.ready,
      p_out_data => s_in_spi.req.data,
      p_out_valid => s_in_spi.req.valid,
      p_out_ready => s_in_spi.ack.ready
      );

  resync_out: fifo_async
    generic map(
      depth => 8,
      data_width => 8
      )
    port map(
      p_resetn => p_framed_resetn,
      p_in_clk => p_sck,
      p_out_clk => p_framed_clk,
      p_in_valid => s_out_spi.req.valid,
      p_in_data => s_out_spi.req.data,
      p_in_ready => s_out_spi.ack.ready,
      p_out_valid => s_out_io.req.valid,
      p_out_data => s_out_io.req.data,
      p_out_ready => s_out_io.ack.ready
      );
  
  shreg: spi_shift_register
    generic map(
      width => 8,
      msb_first => msb_first
      )
    port map(
      spi_i.sck => p_sck,
      spi_i.cs_n => p_csn,
      spi_i.mosi => p_mosi,
      spi_o.miso => p_miso,

      tx_data_i => s_to_spi,
      tx_strobe_o => s_to_spi_ready,
      rx_data_o => s_from_spi,
      rx_strobe_o => s_from_spi_valid
      );
  
  regs: process(p_csn, p_sck)
  begin
    if p_csn = '1' then
      r.state <= ST_CMD;
    elsif rising_edge(p_sck) then
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
          rin.count(7 downto 0) <= s_in_spi.req.data;
        end if;

      when ST_TO_SPI_SIZE_H =>
        if s_to_spi_ready = '1' then
          rin.state <= ST_TO_SPI_DATA;
          rin.count(15 downto 8) <= s_in_spi.req.data;
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

  s_out_spi.req.data <= s_from_spi;
    
  spi_dout: process(r, s_out_spi.req.data, s_to_spi_ready, s_from_spi_valid)
  begin
    case r.state is
      when ST_STATUS =>
        s_to_spi(7 downto 2) <= (others => '0');
        s_to_spi(1) <= not s_out_io.req.valid;
        s_to_spi(0) <= s_in_spi.req.valid;

      when ST_TO_SPI_SIZE_H | ST_TO_SPI_SIZE_L
        | ST_TO_SPI_DATA | ST_TO_SPI_CONT_DATA
        | ST_OVER =>
        s_to_spi <= s_in_spi.req.data;
        
      when others =>
        s_to_spi <= (others => '-');
--        s_to_spi <= x"81";

    end case;

    case r.state is
      when ST_TO_SPI_SIZE_L | ST_TO_SPI_SIZE_H | ST_TO_SPI_DATA | ST_TO_SPI_CONT_DATA =>
        s_in_spi.ack.ready <= s_to_spi_ready;

      when others =>
        s_in_spi.ack.ready <= '0';
    end case;

    case r.state is
      when ST_FROM_SPI_SIZE_L | ST_FROM_SPI_SIZE_H | ST_FROM_SPI_DATA =>
        s_out_spi.req.valid <= s_from_spi_valid;

      when others =>
        s_out_spi.req.valid <= '0';
    end case;

  end process;
  
end architecture;
