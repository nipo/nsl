library ieee;
use ieee.std_logic_1164.all;

-- On Agilex 5 the SDM brings the fabric into user mode sector by
-- sector, so a register leaving reset on its own may run while logic
-- it talks to is still being configured.  The SDM says when the whole
-- device is up through the USER_RESET role of one of its outputs,
-- high until then; this is what Intel's Reset Release IP instantiates,
-- and Quartus's design assistant flags a design lacking it.
--
-- The release is taken through two registers on clock_i, asserting
-- asynchronously.
entity reset_at_startup is
  port(
    clock_i       : in std_ulogic;
    reset_n_o    : out std_ulogic
    );
end entity;

architecture agilex5 of reset_at_startup is

  component fourteennm_sdm_gpio_out is
    generic(
      bitpos : integer := 0;
      role : string := ""
      );
    port(
      gpio_o : out std_logic
      );
  end component;

  signal conf_reset_s : std_logic;
  signal sync_s : std_ulogic_vector(0 to 1);

begin

  sdm: fourteennm_sdm_gpio_out
    generic map(
      bitpos => 15,
      role => "USER_RESET"
      )
    port map(
      gpio_o => conf_reset_s
      );

  sync: process(clock_i, conf_reset_s)
  begin
    if conf_reset_s = '1' then
      sync_s <= (others => '0');
    elsif rising_edge(clock_i) then
      sync_s <= sync_s(1) & '1';
    end if;
  end process;

  reset_n_o <= sync_s(0);

end architecture;
