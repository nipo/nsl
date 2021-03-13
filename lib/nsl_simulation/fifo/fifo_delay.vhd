library ieee;
use ieee.std_logic_1164.all;

entity fifo_delay is
  generic (
    width   : integer;
    latency : natural range 1 to 8
    );
  port (
    reset_n_i : in std_ulogic;
    clock_i    : in std_ulogic;

    in_data_i  : in  std_ulogic_vector(width-1 downto 0);
    in_valid_i : in  std_ulogic;
    in_ready_o : out std_ulogic;

    out_data_o  : out std_ulogic_vector(width-1 downto 0);
    out_ready_i : in  std_ulogic;
    out_valid_o : out std_ulogic
    );
end fifo_delay;

architecture rtl of fifo_delay is

  type regs_t is
  record
    delay : std_ulogic_vector(latency-1 downto 0);
  end record;

  signal r, rin: regs_t;
  signal s_in_ready : std_ulogic;
  
begin

  in_ready_o <= r.delay(0);
  out_data_o <= in_data_i;
  out_valid_o <= in_valid_i;

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.delay <= (others => '0');
    end if;
  end process;

  transition: process(r, out_ready_i)
  begin
    rin <= r;

    rin.delay(latency - 2 downto 0) <= r.delay(latency - 1 downto 1);
    rin.delay(latency - 1) <= out_ready_i;
  end process;
  
end rtl;
