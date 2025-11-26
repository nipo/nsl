library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

-- Bnoc pipe abstraction. A pipe is a 8-bit fifo with no other
-- information than data.
package pipe is

  subtype pipe_data_t is std_ulogic_vector(7 downto 0);

  type pipe_req_t is record
    data  : pipe_data_t;
    valid : std_ulogic;
  end record;

  type pipe_ack_t is record
    ready : std_ulogic;
  end record;

  type pipe_bus_t is
  record
    req : pipe_req_t;
    ack : pipe_ack_t;
  end record;

  constant pipe_req_idle_c : pipe_req_t := (data => "--------",
                                            valid => '0');
  constant pipe_ack_idle_c : pipe_ack_t := (ready => '0');
  constant pipe_ack_blackhole_c : pipe_ack_t := (ready => '1');

  function pipe_flit(data: pipe_data_t;
                     valid : boolean := true) return pipe_req_t;
  function pipe_accept(ready: boolean := true) return pipe_ack_t;
  
  type pipe_req_vector is array(integer range <>) of pipe_req_t;
  type pipe_ack_vector is array(integer range <>) of pipe_ack_t;
  type pipe_bus_vector is array(integer range <>) of pipe_bus_t;
  
  component pipe_fifo
    generic(
      word_count_c  : integer;
      clock_count_c : natural range 1 to 2
      );
    port(
      reset_n_i : in  std_ulogic;
      clock_i   : in  std_ulogic_vector(0 to clock_count_c-1);

      in_i : in  pipe_req_t;
      in_o : out pipe_ack_t;
      out_o : out pipe_req_t;
      out_i : in pipe_ack_t
      );
    --@-- clocking reset:reset_n_i, port:clock_i(0)
    --@-- clocking clock:clock_i(0), port:in
    --@-- clocking clock:clock_i(clock_count_c-1), port:out
  end component;

end package pipe;

package body pipe is

  function pipe_flit(data: pipe_data_t;
                     valid : boolean := true) return pipe_req_t
  is
  begin
    if valid then
      return (valid => '1', data => data);
    else
      return pipe_req_idle_c;
    end if;
  end function;

  function pipe_accept(ready: boolean := true) return pipe_ack_t
  is
  begin
    if ready then
      return (ready => '1');
    else
      return (ready => '0');
    end if;
  end function;

end package body;
