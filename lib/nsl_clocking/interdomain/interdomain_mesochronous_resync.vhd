library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking;

entity interdomain_mesochronous_resync is
  generic(
    data_width_c   : integer
    );
  port(
    reset_n_i   : in std_ulogic;
    clock_i   : in std_ulogic_vector(0 to 1);

    data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
    data_o  : out std_ulogic_vector(data_width_c-1 downto 0);
    valid_o : out  std_ulogic
    );
end entity;

architecture beh of interdomain_mesochronous_resync is

  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);
  type word_vector_t is array (natural range <>) of word_t;

  signal cross_region_reg_d : word_vector_t(0 to 3);
  signal ctr_in, ctr_out : natural range 0 to 3;
  signal reset_n_in, reset_n_out : std_ulogic;

  attribute keep : string;
  attribute async_reg : string;
  attribute syn_keep : boolean;
  attribute nomerge : string;

  attribute keep of cross_region_reg_d : signal is "TRUE";
  attribute syn_keep of cross_region_reg_d : signal is true;
  attribute async_reg of cross_region_reg_d : signal is "TRUE";
  attribute nomerge of cross_region_reg_d : signal is "";
  
begin

  reset_resync_in: nsl_clocking.async.async_edge
    generic map(
      cycle_count_c => 2,
      target_value_c => '1',
      async_reset_c => true
      )
    port map(
      clock_i => clock_i(0),
      data_i => reset_n_i,
      data_o => reset_n_in
      );

  reset_resync_out: nsl_clocking.async.async_edge
    generic map(
      cycle_count_c => 2,
      target_value_c => '1',
      async_reset_c => true
      )
    port map(
      clock_i => clock_i(1),
      data_i => reset_n_in,
      data_o => reset_n_out
      );

  regs_in: process(clock_i, reset_n_in)
  begin
    if rising_edge(clock_i(0)) then
      if reset_n_in = '0' then
        ctr_in <= 0;
      else
        ctr_in <= (ctr_in + 1) mod 4;
      end if;

      for i in 0 to 3
      loop
        if i = ctr_in then
          cross_region_reg_d(i) <= data_i;
        end if;
      end loop;
    end if;
  end process;

  regs_out: process(clock_i, reset_n_out)
  begin
    if rising_edge(clock_i(1)) then
      if reset_n_out = '0' then
        ctr_out <= 0;
        valid_o <= '0';
      else
        ctr_out <= (ctr_out + 1) mod 4;
        valid_o <= '1';
      end if;

      data_o <= cross_region_reg_d(ctr_out);
    end if;
  end process;
  
end architecture;
