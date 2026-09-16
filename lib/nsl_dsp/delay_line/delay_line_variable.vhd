library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory;

entity delay_line_variable is
  generic(
    data_width_c : integer;
    delay_width_c : positive
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i : in  std_ulogic;

    ready_o : out std_ulogic;
    valid_i : in  std_ulogic;
    delay_i : in unsigned(delay_width_c-1 downto 0);
    data_i : in std_ulogic_vector(data_width_c-1 downto 0);
    data_o : out std_ulogic_vector(data_width_c-1 downto 0)
    );
end entity;

architecture beh of delay_line_variable is

  subtype address_t is unsigned(delay_width_c-1 downto 0);
  subtype count_t is unsigned(delay_width_c downto 0);

  type regs_t is
  record
    ready : std_ulogic;
    active : std_ulogic;
    delay : address_t;
    waddr : address_t;
    raddr : address_t;
    count : count_t;
    dout : std_ulogic_vector(data_width_c-1 downto 0);
  end record;

  signal r, rin : regs_t;
  signal mem_waddr_s, mem_raddr_s : address_t;
  signal mem_wdata_s, mem_rdata_s : std_ulogic_vector(data_width_c-1 downto 0);
  signal mem_wen_s : std_ulogic;

begin

  assert data_width_c > 0
    report "delay_line_variable requires a positive data width"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.ready <= '0';
      r.active <= '0';
      r.delay <= (others => '0');
      r.waddr <= (others => '0');
      r.raddr <= (others => '0');
      r.count <= (others => '0');
      r.dout <= (others => '0');
    end if;
  end process;

  transition: process(r, delay_i, valid_i, data_i) is
    variable first_raddr : address_t;
  begin
    rin <= r;
    rin.ready <= '1';

    first_raddr := to_unsigned(0, first_raddr'length) - delay_i;

    if r.delay /= delay_i then
      rin.delay <= delay_i;
      rin.waddr <= (others => '0');
      rin.raddr <= first_raddr;
      rin.count <= (others => '0');
      rin.active <= '0';

      if r.ready = '1' and valid_i = '1' then
        rin.waddr <= to_unsigned(1, rin.waddr'length);
        rin.raddr <= first_raddr + 1;
        rin.count <= to_unsigned(1, rin.count'length);
        rin.dout <= data_i;
      end if;
    elsif r.ready = '1' and valid_i = '1' then
      rin.waddr <= r.waddr + 1;
      rin.raddr <= r.raddr + 1;
      rin.dout <= data_i;

      if r.active = '0' and r.count /= 0 then
        rin.active <= '1';
      end if;

      if r.count = 0 or r.count <= resize(r.delay, rin.count'length) then
        rin.count <= r.count + 1;
      end if;
    end if;
  end process;

  addresses: process(r, delay_i, valid_i) is
  begin
    mem_waddr_s <= r.waddr;
    mem_raddr_s <= r.raddr;

    if r.delay /= delay_i then
      mem_waddr_s <= (others => '0');
      mem_raddr_s <= to_unsigned(0, mem_raddr_s'length) - delay_i;
    end if;

    if r.ready = '1' and valid_i = '1' then
      mem_wen_s <= '1';
    else
      mem_wen_s <= '0';
    end if;
  end process;

  mem_wdata_s <= data_i;

  storage: entity nsl_memory.ram_2p_homogeneous
    generic map(
      addr_size_c => delay_width_c,
      word_size_c => data_width_c,
      data_word_count_c => 1,
      registered_output_c => false,
      b_can_write_c => false
      )
    port map(
      a_clock_i => clock_i,
      a_enable_i => '1',
      a_write_en_i(0) => mem_wen_s,
      a_address_i => mem_waddr_s,
      a_data_i => mem_wdata_s,
      a_data_o => open,

      b_clock_i => clock_i,
      b_enable_i => mem_wen_s,
      b_write_en_i(0) => '0',
      b_address_i => mem_raddr_s,
      b_data_i => (others => '0'),
      b_data_o => mem_rdata_s
      );

  output: process(r, delay_i, mem_rdata_s) is
  begin
    data_o <= (others => '0');

    if r.ready = '1' and r.active = '1' and r.delay = delay_i then
      if r.delay = 0 then
        data_o <= r.dout;
      elsif r.count > resize(r.delay, r.count'length) then
        data_o <= mem_rdata_s;
      end if;
    end if;
  end process;

  ready_o <= r.ready;

end architecture;
