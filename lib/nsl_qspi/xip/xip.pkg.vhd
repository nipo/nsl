library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library nsl_amba, nsl_bnoc, nsl_data;

package xip is

  type read_profile_t is
  record
    opcode: nsl_data.bytestream.byte;
    address_32: boolean;
    address_quad: boolean;
    dummy_cycles: natural range 0 to 256;
  end record;

  type xip_config_t is
  record
    enabled: boolean;
    quad_enable: boolean;
    flash_offset: unsigned(31 downto 0);
    divider: positive range 1 to 256;
    single_profile: read_profile_t;
    quad_profile: read_profile_t;
  end record;

  constant xip_config_reset_c: xip_config_t := (
    enabled => false,
    quad_enable => false,
    flash_offset => x"00000000",
    divider => 1,
    single_profile => (x"03", false, false, 0),
    quad_profile => (x"6b", false, false, 8)
    );

  -- a framed client, not a physical pin controller. Connect its
  -- command/response pair through a framed arbiter along with an
  -- external flash-management controller. Flash reset, QE
  -- programming, mode configuration and initialization belong to that
  -- controller.
  --
  -- Aligned INCR and FIXED reads, including narrow transfers, are supported.
  -- Data occupies the AXI byte lanes selected by the address; unused lanes are
  -- zero. IDs and RLAST are preserved. There is one outstanding read burst and
  -- one flash frame per AXI beat, with no caching or prefetch. This favors simple
  -- arbitration over throughput. R remains stable while stalled.
  -- Disabled, unaligned, oversized, WRAP/reserved, exclusive, 4-KiB-crossing or
  -- address-overflow reads return SLVERR for the entire burst without flash
  -- traffic. Both AXI address overflow and offset-adjusted 24/32-bit flash
  -- overflow are checked. Write AW and W channels are accepted independently;
  -- after AW and the complete W burst are consumed, B returns SLVERR with AWID.
  -- One write burst may be drained concurrently with a read burst.
  component axi4_mm_qspi_xip is
    generic(
      config_c: nsl_amba.axi4_mm.config_t
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      config_i: in xip_config_t;

      axi_i: in nsl_amba.axi4_mm.master_t;
      axi_o: out nsl_amba.axi4_mm.slave_t;

      cmd_o: out nsl_bnoc.framed.framed_req;
      cmd_i: in nsl_bnoc.framed.framed_ack;
      rsp_i: in nsl_bnoc.framed.framed_req;
      rsp_o: out nsl_bnoc.framed.framed_ack
      );
  end component;

  -- A partial write asserts APB SLVERR, but ``apb_regmap`` still
  -- pulses its write strobe and this wrapper updates the entire
  -- addressed register from PWDATA; it is therefore an error response
  -- with side effects, not a rejected write.
  --
  -- Masters must issue full-word writes.  Configure APB error
  -- signaling if the SLVERR indication is required. The aperture
  -- repeats if decoded more broadly.
  --
  -- Reserved bits are RAZ.
  -- 
  -- ====== ================= ==============================================
  -- Offset Register          Fields
  -- ====== ================= ==============================================
  -- 0x00   CONTROL           bit 0 enable, bit 1 quad enable
  -- 0x04   FLASH_OFFSET      32-bit byte offset
  -- 0x08   DIVIDER           bits 7:0 half-period minus one
  -- 0x0c   SINGLE_PROFILE    opcode [7:0], address32 [8], address_quad [9],
  --                          dummy cycles [24:16] (values >256 clamp to 256)
  -- 0x10   QUAD_PROFILE      same encoding
  -- others reserved          zero
  -- ====== ================= ==============================================
  -- 
  -- APB and AXI share a clock/reset. Software should disable XIP while updating
  -- multiple registers, then enable after completing flash initialization.
  -- An already accepted burst continues with its captured configuration.
  component axi4_mm_qspi_xip_apb is
    generic(
      config_c: nsl_amba.axi4_mm.config_t;
      apb_config_c: nsl_amba.apb.config_t
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      apb_i: in nsl_amba.apb.master_t;
      apb_o: out nsl_amba.apb.slave_t;

      axi_i: in nsl_amba.axi4_mm.master_t;
      axi_o: out nsl_amba.axi4_mm.slave_t;

      cmd_o: out nsl_bnoc.framed.framed_req;
      cmd_i: in nsl_bnoc.framed.framed_ack;
      rsp_i: in nsl_bnoc.framed.framed_req;
      rsp_o: out nsl_bnoc.framed.framed_ack
      );
  end component;

end package;
