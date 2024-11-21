library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory;

entity event_binned_counter is
  generic(
    event_bin_count_l2_c : natural := 8;
    event_count_width_c : natural := 16
    );
  port(
    event_clock_i    : in  std_ulogic;
    event_reset_n_i  : in  std_ulogic;

    event_valid_i : in std_ulogic;
    event_ready_o : out std_ulogic;
    event_bin_i : in unsigned(event_bin_count_l2_c-1 downto 0);

    -- Statistics read / clear port
    stat_clock_i : in std_ulogic;
    stat_reset_n_i : in std_ulogic;

    -- Select bin to operate on
    stat_bin_i : in unsigned(event_bin_count_l2_c-1 downto 0);
    -- Clear strobe (read is ignored) for a bin
    stat_clear_en_i : in std_ulogic;
    -- Read handshake for a bin
    stat_read_ready_i : in std_ulogic;
    stat_read_count_o : out unsigned(event_count_width_c-1 downto 0);
    stat_read_valid_o : out std_ulogic
    );
end entity;

architecture beh of event_binned_counter is

  subtype bin_t is unsigned(event_bin_count_l2_c-1 downto 0);
  subtype count_t is unsigned(event_count_width_c-1 downto 0);
  
  signal event_ram_enable_s, event_ram_wen_s: std_ulogic;
  signal event_ram_wdata_s, event_ram_rdata_s : std_ulogic_vector(count_t'range);
  signal event_ram_address_s : bin_t;

  signal stat_ram_enable_s, stat_ram_wen_s, stat_reading_s: std_ulogic;
  signal stat_ram_wdata_s, stat_ram_rdata_s : std_ulogic_vector(count_t'range);
  signal stat_ram_address_s : bin_t;

  type state_t is (
    ST_RESET,
    ST_CLEAR,
    ST_IDLE,
    ST_READ,
    ST_WAIT,
    ST_INC,
    ST_WRITE
    );
  
  type regs_t is
  record
    bin: bin_t;
    value: count_t;
    state: state_t;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(event_clock_i, event_reset_n_i) is
  begin
    if rising_edge(event_clock_i) then
      r <= rin;
    end if;

    if event_reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, event_valid_i, event_bin_i,
                      event_ram_rdata_s) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.bin <= (others => '1');
        rin.state <= ST_CLEAR;

      when ST_CLEAR =>
        if r.bin = 0 then
          rin.state <= ST_IDLE;
        else
          rin.bin <= r.bin - 1;
        end if;

      when ST_IDLE =>
        rin.bin <= unsigned(event_bin_i);
        if event_valid_i = '1' then
          rin.state <= ST_READ;
        end if;

      when ST_READ =>
        rin.state <= ST_WAIT;

      when ST_WAIT =>
        rin.state <= ST_INC;

      when ST_INC =>
        rin.value <= unsigned(event_ram_rdata_s) + 1;
        rin.state <= ST_WRITE;

      when ST_WRITE =>
        rin.state <= ST_IDLE;
    end case;
  end process;

  moore: process(r) is
  begin
    event_ready_o <= '0';

    event_ram_enable_s <= '0';
    event_ram_wen_s <= '0';
    event_ram_address_s <= (others => '-');
    event_ram_wdata_s <= (others => '-');

    case r.state is
      when ST_RESET | ST_INC =>
        null;

      when ST_CLEAR =>
        event_ram_enable_s <= '1';
        event_ram_wen_s <= '1';
        event_ram_wdata_s <= (others => '0');
        event_ram_address_s <= r.bin;

      when ST_IDLE =>
        event_ready_o <= '1';

      when ST_READ | ST_WAIT =>
        event_ram_enable_s <= '1';
        event_ram_address_s <= r.bin;

      when ST_WRITE =>
        event_ram_enable_s <= '1';
        event_ram_wen_s <= '1';
        event_ram_wdata_s <= std_ulogic_vector(r.value);
        event_ram_address_s <= r.bin;
    end case;
  end process;    

  ram: nsl_memory.ram.ram_2p_homogeneous
    generic map(
      addr_size_c => event_bin_count_l2_c,
      word_size_c => event_count_width_c,
      data_word_count_c => 1,
      registered_output_c => true,
      b_can_write_c => true
      )
    port map(
      a_clock_i => event_clock_i,
      a_enable_i => event_ram_enable_s,
      a_write_en_i(0) => event_ram_wen_s,
      a_address_i => event_ram_address_s,
      a_data_i => event_ram_wdata_s,
      a_data_o => event_ram_rdata_s,

      b_clock_i => stat_clock_i,
      b_enable_i => stat_ram_enable_s,
      b_write_en_i(0) => stat_ram_wen_s,
      b_address_i => stat_ram_address_s,
      b_data_i => stat_ram_wdata_s,
      b_data_o => stat_ram_rdata_s
      );
  
  stat_ram_enable_s <= stat_read_ready_i or stat_clear_en_i;
  stat_ram_wen_s <= stat_clear_en_i;
  stat_ram_address_s <= stat_bin_i;
  stat_ram_wdata_s <= (others => '0');
  stat_read_count_o <= unsigned(stat_ram_rdata_s);

  read_latency: process(stat_clock_i) is
  begin
    if rising_edge(stat_clock_i) then
      stat_read_valid_o <= stat_reading_s;
      stat_reading_s <= stat_read_ready_i;
    end if;
  end process;
  
end architecture;
