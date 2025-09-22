library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic;
use nsl_logic.logic.all;
use nsl_logic.bool.all;

entity memory_streamer is
  generic (
    addr_width_c : natural;
    data_width_c : natural;
    memory_latency_c : natural := 1;
    sideband_width_c : natural := 0
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    addr_valid_i : in std_ulogic := '1';
    addr_ready_o : out std_ulogic;
    addr_i : in unsigned(addr_width_c-1 downto 0);
    sideband_i : in std_ulogic_vector(sideband_width_c-1 downto 0);

    data_valid_o : out std_ulogic;
    data_ready_i : in std_ulogic := '1';
    data_o : out std_ulogic_vector(data_width_c-1 downto 0);
    sideband_o : out std_ulogic_vector(sideband_width_c-1 downto 0);

    mem_enable_o : out std_ulogic;
    mem_address_o : out unsigned(addr_width_c-1 downto 0);
    mem_sideband_o : out std_ulogic_vector(sideband_width_c-1 downto 0);
    mem_data_i : in std_ulogic_vector(data_width_c-1 downto 0)
    );
end memory_streamer;

architecture beh of memory_streamer is

  subtype data_t is std_ulogic_vector(data_width_c-1 downto 0);
  type data_vector is array(integer range <>) of data_t;
  subtype sideband_t is std_ulogic_vector(sideband_width_c-1 downto 0);
  type sideband_vector is array(integer range <>) of sideband_t;

  constant sideband_pad: sideband_t := (others => '-');
  constant pad: data_t := (others => '-');
  constant fifo_depth_c : integer := 2;
  constant total_fifo_depth_c : integer := fifo_depth_c+memory_latency_c+1;
  
  type regs_t is
  record
    running: boolean;
    address : unsigned(addr_width_c-1 downto 0);
    output_fifo: data_vector(0 to total_fifo_depth_c-1);
    sideband_fifo: sideband_vector(0 to total_fifo_depth_c-1);
    output_fillness: integer range 0 to total_fifo_depth_c;
    has_read: std_ulogic_vector(0 to memory_latency_c);
    sideband: sideband_vector(0 to memory_latency_c);
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.output_fillness <= 0;
      r.has_read <= (others => '0');
      r.running <= false;
    end if;
  end process;

  transition: process(r, addr_valid_i, addr_i, data_ready_i, mem_data_i, sideband_i) is
    variable push, pop: boolean;
  begin
    rin <= r;

    push := false;
    pop := false;

    rin.running <= true;

    if r.running then
      rin.sideband <= r.sideband(1 to r.sideband'right) & sideband_i;
      rin.address <= addr_i;
      rin.has_read <= r.has_read(1 to r.has_read'right) & '0';
      rin.has_read(rin.has_read'right)
        <= to_logic(r.output_fillness < fifo_depth_c and addr_valid_i = '1');

      push := r.has_read(0) = '1';
      pop := r.output_fillness /= 0 and data_ready_i = '1';
    end if;

    if push and pop then
      rin.output_fifo <= r.output_fifo(1 to r.output_fifo'right) & pad;
      rin.output_fifo(r.output_fillness-1) <= mem_data_i;
      rin.sideband_fifo <= r.sideband_fifo(1 to r.sideband_fifo'right) & sideband_pad;
      rin.sideband_fifo(r.output_fillness-1) <= r.sideband(0);
    elsif push then
      rin.output_fifo(r.output_fillness) <= mem_data_i;
      rin.sideband_fifo(r.output_fillness) <= r.sideband(0);
      rin.output_fillness <= r.output_fillness + 1;
    elsif pop then
      rin.output_fifo <= r.output_fifo(1 to r.output_fifo'right) & pad;
      rin.sideband_fifo <= r.sideband_fifo(1 to r.sideband_fifo'right) & sideband_pad;
      rin.output_fillness <= r.output_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    if r.running then
      addr_ready_o <= to_logic(r.output_fillness < fifo_depth_c);
      data_valid_o <= to_logic(r.output_fillness /= 0);
    else
      addr_ready_o <= '0';
      data_valid_o <= '0';
    end if;
    data_o <= r.output_fifo(0);
    sideband_o <= r.sideband_fifo(0);
    mem_sideband_o <= r.sideband(r.sideband'right);
    mem_address_o <= r.address;
    mem_enable_o <= or_reduce(r.has_read);
  end process;
  
end architecture;
