library ieee;
use ieee.std_logic_1164.all;

library nsl_line_coding;

entity top is
  generic(
    implementation_c : string := "logic"
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    data_i : in std_ulogic_vector(7 downto 0);
    control_i : in std_ulogic;
    
    data_o : out std_ulogic_vector(9 downto 0)
  );
end top;

architecture arch of top is

  signal data : std_ulogic_vector(7 downto 0);
  signal control : std_ulogic;

begin

  d_ff: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      data <= data_i;
      control <= control_i;
    end if;
  end process;
  
  encoder: nsl_line_coding.ibm_8b10b.ibm_8b10b_encoder
    generic map(
      implementation_c => implementation_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      data_i => data,
      control_i => control,

      data_o => data_o
      );
  
end arch;
