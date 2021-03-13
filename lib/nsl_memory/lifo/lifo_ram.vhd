library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_memory;
use nsl_memory.lifo.all;

entity lifo_ram is
  generic(
    data_width_c : positive;
    word_count_c : positive
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    op_i : in lifo_op_t;
    data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
    data_o      : out std_ulogic_vector(data_width_c-1 downto 0);

    empty_o : out std_ulogic;
    full_o : out std_ulogic;
    free_o  : out integer range 0 to word_count_c;
    available_o : out integer range 0 to word_count_c
    );
end entity;

architecture beh of lifo_ram is

  constant ptr_width : natural := nsl_math.arith.log2(word_count_c);
  subtype ptr_t is unsigned(ptr_width-1 downto 0);

  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);
  type storage_t is array (integer range <>) of word_t;
  constant unk : word_t := (others => '-');
  
  type regs_t is
  record
    counter : integer range 0 to word_count_c;
    raddr : ptr_t;
    reg : storage_t(0 to word_count_c-1);
    top : word_t;
    top_valid : boolean;
  end record;

  signal r, rin: regs_t;

  signal wen: std_ulogic;
  signal rdata: word_t;
  signal raddr, waddr: ptr_t;

begin
  
  regs: process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.counter <= 0;
      r.top_valid <= false;
      r.raddr <= ptr_t(to_signed(-1, ptr_t'length));
    end if;
  end process;

  transition: process(r, op_i, r, data_i)
  begin
    rin <= r;

    case op_i is
      when LIFO_OP_PUSH =>
        if r.counter /= word_count_c then
          rin.counter <= r.counter + 1;
          rin.raddr <= r.raddr + 1;
          rin.reg <= data_i & r.reg(0 to word_count_c-2);
          rin.top <= data_i;
          rin.top_valid <= true;
        end if;

      when LIFO_OP_POP =>
        if r.counter /= 0 then
          rin.counter <= r.counter - 1;
          rin.raddr <= r.raddr - 1;
          rin.reg <= r.reg(1 to word_count_c-1) & unk;
          rin.top_valid <= false;
        end if;
        
      when others =>
        if not r.top_valid then
          rin.top <= rdata;
          rin.top_valid <= true;
        end if;
    end case;
  end process;

  wen <= '1' when op_i = LIFO_OP_PUSH and r.counter /= word_count_c else '0';
  waddr <= to_unsigned(r.counter, waddr'length);
  raddr <= r.raddr when op_i = LIFO_OP_PUSH else r.raddr - 1;

  ram: nsl_memory.ram.ram_2p_r_w
    generic map(
      addr_size_c => ptr_t'length,
      data_size_c => word_t'length,
      clock_count_c => 1
      )
    port map(
      clock_i(0) => clock_i,

      write_address_i => waddr,
      write_en_i => wen,
      write_data_i => data_i,

      read_address_i => raddr,
      read_data_o => rdata
      );

  empty_o <= '1' when r.counter = 0 else '0';
  full_o <= '1' when r.counter = word_count_c else '0';
  available_o <= r.counter;
  free_o <= word_count_c - r.counter;
  data_o <= r.top when r.top_valid else rdata;
  
end architecture;
