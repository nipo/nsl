library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_memory;
use nsl_logic.bool.all;

entity fifo_cancellable is
  generic(
    data_width_c    : integer;
    word_count_l2_c : integer
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i       : in  std_ulogic;

    out_data_o          : out std_ulogic_vector(data_width_c-1 downto 0);
    out_ready_i         : in  std_ulogic;
    out_valid_o         : out std_ulogic;
    out_commit_i : in std_ulogic := '1';
    out_rollback_i : in std_ulogic := '0';
    out_available_o : out unsigned(word_count_l2_c downto 0);

    in_data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
    in_valid_i : in  std_ulogic;
    in_ready_o : out std_ulogic;
    in_commit_i : in std_ulogic := '1';
    in_rollback_i : in std_ulogic := '0';
    in_free_o : out unsigned(word_count_l2_c downto 0)
    );
end entity;

architecture beh of fifo_cancellable is

  -- Pointer has one extra bit to handle wraparound transparently
  subtype ptr_t is unsigned(word_count_l2_c downto 0);
  subtype mem_ptr_t is unsigned(word_count_l2_c-1 downto 0);

  function to_ptr(i: integer) return ptr_t is
  begin
    return to_unsigned(i, ptr_t'length);
  end function;

  constant ptr_toggle_c : ptr_t := to_ptr(2 ** word_count_l2_c);

  type regs_t is
  record
    -- Committed space pointers
    rptr, wptr : ptr_t;
    -- Speculative space pointers
    rptr_sp, wptr_sp : ptr_t;
    -- Memory read pointer, it is in advance of one memory position to be able
    -- to ask next data word from memory
    rptr_mem: ptr_t;
    rdata_valid : std_ulogic;

    reset_done: boolean;
  end record;

  signal r, rin : regs_t;

  signal s_do_write, s_do_read : std_ulogic;
  signal s_wptr_end: ptr_t;
  
begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.rptr <= to_ptr(0);
      r.wptr <= to_ptr(0);
      r.rptr_sp <= to_ptr(0);
      r.rptr_mem <= to_ptr(0);
      r.wptr_sp <= to_ptr(0);
      r.rdata_valid <= '0';
      r.reset_done <= false;
    end if;
  end process;

  transition: process(r, out_ready_i,
                      out_commit_i, out_rollback_i,
                      in_valid_i, in_commit_i, in_rollback_i,
                      s_do_read, s_do_write) is
  begin
    rin <= r;

    rin.reset_done <= true;

    if out_ready_i = '1' then
      rin.rdata_valid <= '0';
      rin.rptr_sp <= r.rptr_mem;
    end if;

    if s_do_read = '1' then
      rin.rdata_valid <= '1';
      rin.rptr_mem <= r.rptr_mem + 1;
      rin.rptr_sp <= r.rptr_mem;
    end if;

    if s_do_write = '1' then
      rin.wptr_sp <= r.wptr_sp + 1;
    end if;

    if in_commit_i = '1' then
      rin.wptr <= r.wptr_sp;
    elsif in_rollback_i = '1' then
      rin.wptr_sp <= r.wptr;
    end if;

    if out_commit_i = '1' then
      rin.rptr <= r.rptr_sp;
    elsif out_rollback_i = '1' then
      rin.rptr_mem <= r.rptr;
      rin.rptr_sp <= r.rptr;
      rin.rdata_valid <= '0';
    end if;
  end process;

  out_valid_o <= r.rdata_valid;

  s_wptr_end <= r.rptr xor ptr_toggle_c;
  s_do_write <= to_logic(r.wptr_sp /= s_wptr_end) and in_valid_i;
  s_do_read <= to_logic(r.rptr_mem /= r.wptr) and (out_ready_i or not r.rdata_valid);
  out_available_o <= r.wptr - r.rptr;
  in_free_o <= s_wptr_end - r.wptr  when reset_n_i = '1' else (others => '0');
  in_ready_o <= to_logic(r.wptr_sp /= s_wptr_end and r.reset_done);

  storage: nsl_memory.ram.ram_2p_r_w
    generic map(
      addr_size_c => mem_ptr_t'length,
      data_size_c => data_width_c,
      clock_count_c => 1,
      registered_output_c => false
      )
    port map(
      clock_i(0) => clock_i,

      write_address_i => r.wptr_sp(mem_ptr_t'range),
      write_en_i => s_do_write,
      write_data_i => in_data_i,

      read_address_i => r.rptr_mem(mem_ptr_t'range),
      read_en_i => s_do_read,
      read_data_o => out_data_o
      );
  
end architecture;
