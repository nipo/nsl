library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity framed_gate_arbitrer is
  generic(
    gate_count_c : integer
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    request_i   : in  std_ulogic_vector(0 to gate_count_c-1);
    grant_o     : out std_ulogic_vector(0 to gate_count_c-1);
    busy_i      : in  std_ulogic_vector(0 to gate_count_c-1);

    selected_o  : out unsigned;
    request_o   : out std_ulogic;
    grant_i     : in  std_ulogic;
    busy_o      : out std_ulogic
    );
end entity;

architecture rtl of framed_gate_arbitrer is

  type state_t is (
    ST_RESET,
    ST_WAIT_REQUEST,
    ST_WAIT_GRANT,
    ST_WAIT_START,
    ST_WAIT_DONE
    );
  
  type regs_t is record
    state : state_t;
    selected : natural range 0 to gate_count_c - 1;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, request_i, busy_i, grant_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_WAIT_REQUEST;

      when ST_WAIT_REQUEST =>
        ports: for i in gate_count_c-1 downto 0
        loop
          if request_i(i) = '1' then
            rin.state <= ST_WAIT_GRANT;
            rin.selected <= i;
          end if;
        end loop;

      when ST_WAIT_GRANT =>
        if grant_i = '1' then
          rin.state <= ST_WAIT_START;
        end if;

      when ST_WAIT_START =>
        if busy_i(r.selected) = '1' then
          rin.state <= ST_WAIT_DONE;
        end if;

      when ST_WAIT_DONE =>
        if busy_i(r.selected) = '0' then
          rin.state <= ST_WAIT_REQUEST;
        end if;
        
    end case;
  end process;

  moore: process(r)
  begin
    grant_o <= (others => '0');
    busy_o <= '0';
    request_o <= '0';
    selected_o <= to_unsigned(r.selected, selected_o'length);

    case r.state is
      when ST_RESET | ST_WAIT_REQUEST =>
        null;

      when ST_WAIT_GRANT =>
        request_o <= '1';

      when ST_WAIT_START => 
        busy_o <= '1';
        grant_o(r.selected) <= '1';

      when ST_WAIT_DONE =>
        busy_o <= '1';
    end case;
  end process;
    
end architecture;
