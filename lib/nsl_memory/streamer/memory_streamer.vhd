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

-- Beats coming back from the memory are held in a circular buffer
-- followed by an output register.
--
-- The buffer is not a shifting structure: a beat is written to the
-- slot the one-hot write pointer designates and stays there. Slot
-- data inputs are therefore driven straight from mem_data_i and slot
-- clock enables are one AND away from flip-flops. The one-hot read
-- pointer selects the slot that refills the output register. Fillness
-- counters take part in flow control and in the empty/bypass flag
-- only, never in data steering.
architecture beh of memory_streamer is

  subtype data_t is std_ulogic_vector(data_width_c-1 downto 0);
  type data_vector is array(integer range <>) of data_t;
  subtype sideband_t is std_ulogic_vector(sideband_width_c-1 downto 0);
  type sideband_vector is array(integer range <>) of sideband_t;

  -- Addresses are accepted as long as less than fifo_depth_c beats
  -- are held, so up to memory_latency_c+1 more reads may be in flight
  -- and land afterwards.
  constant fifo_depth_c : integer := 2;
  constant total_fifo_depth_c : integer := fifo_depth_c+memory_latency_c+1;
  -- One of the held beats sits in the output register.
  constant buffer_depth_c : integer := total_fifo_depth_c-1;

  subtype pointer_t is std_ulogic_vector(0 to buffer_depth_c-1);
  constant pointer_init_c : pointer_t := (0 => '1', others => '0');

  function mux(sel : pointer_t; d : data_vector) return data_t is
    variable ret : data_t := (others => '0');
  begin
    for i in d'range loop
      if sel(i) = '1' then
        ret := ret or d(i);
      end if;
    end loop;
    return ret;
  end function;

  function mux(sel : pointer_t; d : sideband_vector) return sideband_t is
    variable ret : sideband_t := (others => '0');
  begin
    for i in d'range loop
      if sel(i) = '1' then
        ret := ret or d(i);
      end if;
    end loop;
    return ret;
  end function;

  type regs_t is
  record
    running: boolean;
    address : unsigned(addr_width_c-1 downto 0);
    has_read: std_ulogic_vector(0 to memory_latency_c);
    sideband: sideband_vector(0 to memory_latency_c);

    fifo_data: data_vector(0 to buffer_depth_c-1);
    fifo_sideband: sideband_vector(0 to buffer_depth_c-1);
    wptr: pointer_t;
    rptr: pointer_t;
    buffer_fillness: integer range 0 to buffer_depth_c;
    buffer_empty: boolean;

    out_data: data_t;
    out_sideband: sideband_t;
    out_valid: std_ulogic;

    fillness: integer range 0 to total_fifo_depth_c;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.fillness <= 0;
      r.buffer_fillness <= 0;
      r.buffer_empty <= true;
      r.wptr <= pointer_init_c;
      r.rptr <= pointer_init_c;
      r.out_valid <= '0';
      r.has_read <= (others => '0');
      r.running <= false;
    end if;
  end process;

  transition: process(r, addr_valid_i, addr_i, data_ready_i, mem_data_i, sideband_i) is
    variable push, pop, out_free: boolean;
  begin
    rin <= r;

    push := false;
    pop := r.out_valid = '1' and data_ready_i = '1';
    out_free := r.out_valid = '0' or data_ready_i = '1';

    rin.running <= true;

    if r.running then
      rin.sideband <= r.sideband(1 to r.sideband'right) & sideband_i;
      rin.address <= addr_i;
      rin.has_read <= r.has_read(1 to r.has_read'right) & '0';
      rin.has_read(rin.has_read'right)
        <= to_logic(r.fillness < fifo_depth_c and addr_valid_i = '1');

      push := r.has_read(0) = '1';
    end if;

    -- Returning data always lands in the slot the write pointer
    -- designates. The pointer only moves for a beat that is actually
    -- retained there, i.e. one that did not go straight through to
    -- the output register.
    if push then
      for i in pointer_t'range loop
        if r.wptr(i) = '1' then
          rin.fifo_data(i) <= mem_data_i;
          rin.fifo_sideband(i) <= r.sideband(0);
        end if;
      end loop;

      if not r.buffer_empty or not out_free then
        rin.wptr <= r.wptr(r.wptr'right) & r.wptr(r.wptr'left to r.wptr'right-1);
      end if;
    end if;

    if out_free then
      if not r.buffer_empty then
        rin.out_data <= mux(r.rptr, r.fifo_data);
        rin.out_sideband <= mux(r.rptr, r.fifo_sideband);
        rin.out_valid <= '1';
        rin.rptr <= r.rptr(r.rptr'right) & r.rptr(r.rptr'left to r.rptr'right-1);
      elsif push then
        rin.out_data <= mem_data_i;
        rin.out_sideband <= r.sideband(0);
        rin.out_valid <= '1';
      else
        rin.out_valid <= '0';
      end if;
    end if;

    -- Fillness and its empty flag only make sense together, which the
    -- reset establishes and the running flag guards until then: a peer
    -- holding data_ready_i asserted from the very first delta cycle
    -- would otherwise take the decrement branch on the default value
    -- of the flag, before the reset even applies.
    if r.running then
      if push and not out_free then
        rin.buffer_fillness <= r.buffer_fillness + 1;
        rin.buffer_empty <= false;
      elsif out_free and not push and not r.buffer_empty then
        rin.buffer_fillness <= r.buffer_fillness - 1;
        rin.buffer_empty <= r.buffer_fillness = 1;
      end if;

      if push and not pop then
        rin.fillness <= r.fillness + 1;
      elsif pop and not push then
        rin.fillness <= r.fillness - 1;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    if r.running then
      addr_ready_o <= to_logic(r.fillness < fifo_depth_c);
    else
      addr_ready_o <= '0';
    end if;
    data_valid_o <= r.out_valid;
    data_o <= r.out_data;
    sideband_o <= r.out_sideband;
    mem_sideband_o <= r.sideband(r.sideband'right);
    mem_address_o <= r.address;
    mem_enable_o <= or_reduce(r.has_read);
  end process;

end architecture;
