library ieee;
use ieee.std_logic_1164.all;

-- One register stage on a path between the HPS and the fabric core,
-- placed in a hyper-register of the core/periphery boundary as the
-- vendor bridge adapters do.  These registers have no reset.
entity hps_boundary_register is
  generic(
    width_c : positive;
    to_periphery_c : boolean
    );
  port(
    clock_i : in std_ulogic;
    data_i : in std_ulogic_vector(width_c-1 downto 0);
    data_o : out std_ulogic_vector(width_c-1 downto 0)
    );
end entity;

architecture beh of hps_boundary_register is

  attribute altera_attribute : string;

begin

  c2p: if to_periphery_c
  generate
    signal reg_s : std_ulogic_vector(width_c-1 downto 0);
    attribute altera_attribute of reg_s : signal is
      "-name FORCE_HYPER_REGISTER_FOR_CORE_PERIPHERY_TRANSFER ON; -name HYPER_REGISTER_DELAY_CHAIN 350";
  begin
    regs: process(clock_i)
    begin
      if rising_edge(clock_i) then
        reg_s <= data_i;
      end if;
    end process;

    data_o <= reg_s;
  end generate;

  p2c: if not to_periphery_c
  generate
    signal reg_s : std_ulogic_vector(width_c-1 downto 0);
    attribute altera_attribute of reg_s : signal is
      "-name FORCE_HYPER_REGISTER_FOR_PERIPHERY_CORE_TRANSFER ON";
  begin
    regs: process(clock_i)
    begin
      if rising_edge(clock_i) then
        reg_s <= data_i;
      end if;
    end process;

    data_o <= reg_s;
  end generate;

end architecture;
