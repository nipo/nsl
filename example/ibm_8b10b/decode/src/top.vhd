library ieee;
use ieee.std_logic_1164.all;

library nsl_line_coding;

entity top is
  generic (
    implementation_c : string := "foreign";
    strict_c : boolean := true
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    data_i : in std_ulogic_vector(9 downto 0);

    data_o : out std_ulogic_vector(7 downto 0);
    control_o : out std_ulogic;
    disparity_error_o : out std_ulogic;
    code_error_o : out std_ulogic
  );
end top;

architecture arch of top is

  signal data : std_ulogic_vector(9 downto 0);

begin

  di_ff: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      data <= data_i;
    end if;
  end process;
  
  decoder: nsl_line_coding.ibm_8b10b.ibm_8b10b_decoder
    generic map(
      implementation_c => implementation_c,
      strict_c => strict_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      data_i => data,

      data_o => data_o,
      control_o => control_o,
      disparity_error_o => disparity_error_o,
      code_error_o => code_error_o
      );

end arch;
