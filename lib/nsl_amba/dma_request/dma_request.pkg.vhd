library ieee;
use ieee.std_logic_1164.all;

-- DMA peripheral request interface.
--
-- Signals and semantics are the ones of the ARM CoreLink DMA-330
-- peripheral request interface: two valid/ready handshaked buses,
-- request (dr*) from the peripheral, acknowledge (da*) from the DMA
-- controller.  Every signal only changes on the clock edge,
-- drtype/drlast only when drvalid is low or drready is high, datype
-- only when davalid is low or daready is high.
package dma_request is

  subtype request_type_t is std_ulogic_vector(1 downto 0);
  -- drtype values
  constant drtype_single_c : request_type_t := "00";
  constant drtype_burst_c : request_type_t := "01";
  constant drtype_flush_c : request_type_t := "10";
  -- datype values
  constant datype_single_c : request_type_t := "00";
  constant datype_burst_c : request_type_t := "01";
  constant datype_flush_c : request_type_t := "10";

  -- Driven by the peripheral.
  type peripheral_t is
  record
    drvalid: std_ulogic;
    drtype: request_type_t;
    drlast: std_ulogic;
    daready: std_ulogic;
  end record;

  -- Driven by the DMA controller.
  type dmac_t is
  record
    drready: std_ulogic;
    davalid: std_ulogic;
    datype: request_type_t;
  end record;

  type peripheral_vector is array (natural range <>) of peripheral_t;
  type dmac_vector is array (natural range <>) of dmac_t;

  -- A peripheral never requesting and always accepting acknowledges.
  constant peripheral_idle_c : peripheral_t := (
    drvalid => '0',
    drtype => drtype_single_c,
    drlast => '0',
    daready => '1'
    );

end package;
