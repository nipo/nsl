library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

package axi_bridge is

  -- SMI to AXI-Lite master bridge.
  -- Actually, this could be used with any 16-bit data interface.
  --
  -- This is a set of 5 registers from ``block_offset_c`` to ``block_offset_c+4``.
  --
  -- Registers at offset 0 and 1 are address (MSB first),
  -- Registers at offset 2 and 3 are data.
  -- Register at offset 4 is the command. Bit 0 starts a command (it self
  -- clears once the access is complete), bit 1 is R/nW bit. Both bits may be
  -- set in one register write operation.
  component smi_axi_bridge is
    generic(
      config_c: nsl_amba.axi4_mm.config_t;
      block_offset_c: integer range 0 to 31-5+1
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      smi_reg_i: in integer range 0 to 31;
      smi_wen_i: in std_ulogic;
      smi_wdata_i: in unsigned(15 downto 0);
      smi_rdata_o: out unsigned(15 downto 0);

      axi_o: out nsl_amba.axi4_mm.master_t;
      axi_i: in nsl_amba.axi4_mm.slave_t
      );
  end entity;
end package;
