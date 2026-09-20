library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package qspi_test_support is
  function memory_byte(address: unsigned(31 downto 0)) return std_ulogic_vector;

  component qspi_flash_model is
    port(
      cs_n_i, sck_i: in std_ulogic;
      dq_i, enable_i: in std_ulogic_vector(3 downto 0);
      dq_o: out std_ulogic_vector(3 downto 0);
      opcode_i: in std_ulogic_vector(7 downto 0);
      address_i: in unsigned(31 downto 0);
      address_bytes_i: in positive;
      address_lanes_i, data_lanes_i: in positive;
      dummy_cycles_i: in natural;
      data_bytes_i: in positive;
      half_period_i: in time;
      completed_o: out natural
      );
  end component;
end package;

package body qspi_test_support is
  function memory_byte(address: unsigned(31 downto 0)) return std_ulogic_vector is
  begin
    return std_ulogic_vector(address(7 downto 0) xor address(15 downto 8)
                            xor address(23 downto 16) xor address(31 downto 24)
                            xor x"a7");
  end function;
end package body;
