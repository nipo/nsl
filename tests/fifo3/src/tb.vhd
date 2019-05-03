library ieee, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb is
end tb;

library nsl, util;

architecture arch of tb is

  constant width : integer := 8;
  subtype word_t is std_ulogic_vector(width-1 downto 0);

  type half_period_t is
  record
    left, right, left_init, right_init: time;
  end record;

  type half_period_array_t is array(natural range <>) of half_period_t;
  
  constant half_period : half_period_array_t(0 to 13) := (
    (3 ns, 20 ns, 1000 ns, 0 ns),
    (3 ns, 20 ns, 0 ns, 1000 ns),
    (5 ns, 10 ns, 1000 ns, 0 ns),
    (5 ns, 10 ns, 0 ns, 1000 ns),
    (7 ns, 8 ns, 1000 ns, 0 ns),
    (7 ns, 8 ns, 0 ns, 1000 ns),
    (8 ns, 10 ns, 0 ns, 80 ns),
    (10 ns, 10 ns, 0 ns, 1000 ns),
    (10 ns, 10 ns, 1000 ns, 0 ns),
    (10 ns, 8 ns, 0 ns, 1000 ns),
    (10 ns, 8 ns, 80 ns, 0 ns),
    (10 ns, 8 ns, 1000 ns, 0 ns),
    (20 ns, 5 ns, 0 ns, 1000 ns),
    (20 ns, 5 ns, 1000 ns, 0 ns));
  
  type side_t is
  record
    clock, ready, valid, ready_after, valid_after : std_ulogic;
    data, data_after: word_t;
  end record;

  signal l, r : side_t;
  signal s_resetn_async, s_done, s_eot : std_ulogic;

  procedure data_put(signal clock : in std_ulogic;
                     signal ready : in std_ulogic;
                     signal valid : out std_ulogic;
                     signal data : out word_t;
                     constant wdata : in word_t) is
  begin
    valid <= '1';
    data <= wdata;

    wait until ready = '1' and rising_edge(clock);
    wait until falling_edge(clock);
    valid <= '0';
    data <= (others => '-');
  end procedure;

  procedure slv_write(buf: inout line; v: in std_ulogic_vector) is
    variable c: character;
  begin
    for i in v'range loop
      case v(i) is
        when 'X' => c := 'X';
        when 'U' => c := 'U';
        when 'Z' => c := 'Z';
        when '0' => c := '0';
        when '1' => c := '1';
        when '-' => c := '-';
        when 'W' => c := 'W';
        when 'H' => c := 'H';
        when 'L' => c := 'L';
        when others => c := '0';
      end case;
      write(buf, c);
    end loop;
  end procedure slv_write;
  
  procedure data_get(signal clock : in std_ulogic;
                     signal ready : out std_ulogic;
                     signal valid : in std_ulogic;
                     signal data : in word_t;
                     constant rdata : in word_t) is
    variable complaint : line;
  begin
    ready <= '1';

    wait until valid = '1' and rising_edge(clock);

    write(complaint, string'("Expected value "));
    slv_write(complaint, std_ulogic_vector(rdata));
    write(complaint, string'(" does not match fifo data "));
    slv_write(complaint, std_ulogic_vector(data));
    assert data = rdata
      report complaint.all & CR & LF
      severity error;

    wait until falling_edge(clock);
    ready <= '0';
  end procedure;
  
begin

  fifo: nsl.fifo.fifo_async
    generic map(
      data_width => width,
      depth => 16
      )
    port map(
      p_resetn => s_resetn_async,

      p_in_clk => l.clock,
      p_in_data => l.data,
      p_in_valid => l.valid,
      p_in_ready => l.ready,

      p_out_clk => r.clock,
      p_out_data => r.data,
      p_out_ready => r.ready,
      p_out_valid => r.valid
      );

  input_gen: process
    variable iter: natural;
    variable i : natural range 0 to 2**width-1;
  begin
    l.valid <= '0';
    l.data <= (others => '-');

    for iter in half_period'range
    loop
      wait until s_resetn_async = '1';

      wait for half_period(iter).left_init;
      wait until falling_edge(l.clock);

      for i in 0 to 2 ** width -1
      loop
        data_put(l.clock, l.ready_after, l.valid, l.data, std_ulogic_vector(to_unsigned((i+128) mod 256, width)));
      end loop;

      wait until s_eot = '1';
      wait until s_eot = '0';
    end loop;
    
    wait;
  end process;

  output_gen: process
    variable iter: natural;
    variable i : natural range 0 to 2**width-1;
  begin
    r.ready <= '0';
    s_done <= '0';
    s_eot <= '0';

    for iter in half_period'range
    loop
      wait until s_resetn_async = '1';

      wait for half_period(iter).right_init;
      wait until falling_edge(r.clock);

      for i in 0 to 2 ** width -1
      loop
        data_get(r.clock, r.ready, r.valid_after, r.data_after, std_ulogic_vector(to_unsigned((i+128) mod 256, width)));
      end loop;

      wait for 30 ns;
      s_eot <= '1';
      wait for 100 ns;
      s_eot <= '0';
    end loop;

    s_done <= '1';
    wait;
  end process;

  reset_gen: process
    variable iter: natural;
  begin
    for iter in half_period'range
    loop
      s_resetn_async <= '0';
      wait for 10 ns;
      s_resetn_async <= '1';

      wait until s_eot = '1';
      wait until s_eot = '0';
    end loop;
    
    wait;    
  end process;

  l.ready_after <= l.ready after 1 ns;
  l.valid_after <= l.valid after 1 ns;
  l.data_after <= l.data after 1 ns;
  r.ready_after <= r.ready after 1 ns;
  r.valid_after <= r.valid after 1 ns;
  r.data_after <= r.data after 1 ns;
  
  l_clock_gen: process
    variable last_eot: std_ulogic;
    variable iter: natural;
  begin
    l.clock <= '0';

    last_eot := s_eot;
    for iter in half_period'range
    loop
      while not (last_eot = '0' and s_eot = '1') loop
        last_eot := s_eot;
        l.clock <= '1';
        wait for half_period(iter).left;
        l.clock <= '0';
        wait for half_period(iter).left;
      end loop;
      last_eot := s_eot;
    end loop;
    wait;
  end process;

  r_clock_gen: process
    variable last_eot: std_ulogic;
    variable iter: natural;
  begin
    r.clock <= '0';

    last_eot := s_eot;
    for iter in half_period'range
    loop
      while not (last_eot = '0' and s_eot = '1') loop
        last_eot := s_eot;
        r.clock <= '1';
        wait for half_period(iter).right;
        r.clock <= '0';
        wait for half_period(iter).right;
      end loop;
      last_eot := s_eot;
    end loop;
    wait;
  end process;

end;
