library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_line_coding;
use nsl_line_coding.ibm_8b10b.all;
use nsl_line_coding.ibm_8b10b_stream.all;

entity ibm_8b10b_stream_idle_filter is
  generic(
    config_c : config_t;
    idle_c : data_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of ibm_8b10b_stream_idle_filter is

  signal filtered_s : master_t;

begin

  assert config_c.has_strobe
    report "Idle filter requires a configuration with strobe enabled"
    severity failure;

  filter: process(in_i) is
    variable m : master_t;
    variable w : data_vector(0 to config_c.word_count-1);
  begin
    m := in_i;
    w := words(config_c, in_i);

    for i in w'range
    loop
      if m.strobe(i) = '1' and w(i) = idle_c then
        m.strobe(i) := '0';
      end if;
    end loop;

    filtered_s <= m;
  end process;

  output_slice: nsl_amba.stream_fifo.axi4_stream_slice
    generic map(
      config_c => as_stream_config(config_c)
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => filtered_s,
      in_o => in_o,

      out_o => out_o,
      out_i => out_i
      );

end architecture;
