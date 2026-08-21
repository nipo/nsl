library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package streamer is

  -- Latency-hiding front-end for a read-only memory port.
  --
  -- Every address accepted on addr_valid_i/addr_ready_o yields exactly
  -- one beat on data_valid_o/data_ready_i, in order, carrying the
  -- sideband that came with the address. Addresses are only accepted
  -- while there is room to land the data they will return, so a
  -- stalled data side never loses a beat.
  --
  -- mem_address_o is presented one cycle after the address is
  -- accepted and mem_data_i is expected memory_latency_c cycles
  -- later. mem_enable_o stays asserted for as long as reads are in
  -- flight, so a memory with registered outputs keeps clocking its
  -- pipeline until the data comes out.
  component memory_streamer is
    generic (
      addr_width_c : natural;
      data_width_c : natural;
      memory_latency_c : natural := 1;
      sideband_width_c : natural := 0
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      addr_valid_i : in std_ulogic := '1';
      addr_ready_o : out std_ulogic;
      addr_i : in unsigned(addr_width_c-1 downto 0);
      sideband_i : in std_ulogic_vector(sideband_width_c-1 downto 0);

      data_valid_o : out std_ulogic;
      data_ready_i : in std_ulogic := '1';
      data_o : out std_ulogic_vector(data_width_c-1 downto 0);
      sideband_o : out std_ulogic_vector(sideband_width_c-1 downto 0);

      mem_enable_o : out std_ulogic;
      mem_address_o : out unsigned(addr_width_c-1 downto 0);
      mem_sideband_o : out std_ulogic_vector(sideband_width_c-1 downto 0);
      mem_data_i : in std_ulogic_vector(data_width_c-1 downto 0)
      );
  end component;
end package;
