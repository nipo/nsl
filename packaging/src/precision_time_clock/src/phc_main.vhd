library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi, nsl_time, nsl_math, work;
use nsl_time.timestamp.all;
use nsl_math.fixed.all;

entity phc_main is
  generic(
    increment_msb: integer := 7;
    increment_lsb: integer := -15
    );
  port(
    aclk : in std_ulogic;
    aresetn : in std_ulogic;

    config_i : in nsl_axi.axi4_lite.a32_d32_ms;
    config_o : out nsl_axi.axi4_lite.a32_d32_sm;

    timestamp_o : out timestamp_t
    );
end entity;

architecture rtl of phc_main is

  constant reg_sub_ns_inc_c : integer := 0;
  constant reg_ns_adj_c : integer := 1;
  constant reg_timestamp_sec_c : integer := 2;
  constant reg_timestamp_ns_c : integer := 3;
  
  signal config_addr_s : unsigned(4 downto 2);
  signal config_w_data_s : std_ulogic_vector(31 downto 0);
  signal config_w_mask_s : std_ulogic_vector(3 downto 0);
  signal config_w_ready_s : std_ulogic;
  signal config_w_valid_s : std_ulogic;
  signal config_r_data_s : std_ulogic_vector(31 downto 0);
  signal config_r_ready_s : std_ulogic;
  signal config_r_valid_s : std_ulogic;

  signal timestamp_s : timestamp_t;

  type regs_t is
  record
    sub_ns_inc: ufixed(increment_msb downto increment_lsb);
    ns_adj: timestamp_nanosecond_offset_t;
    ns_adj_strobe, axi_timestamp_strobe: std_ulogic;
    axi_timestamp: timestamp_t;
    read_ns_cap: timestamp_nanosecond_t;
  end record;

  signal r, rin: regs_t;
  
begin

  config_slave: nsl_axi.axi4_lite.axi4_lite_a32_d32_slave
    generic map(
      addr_size => config_addr_s'length+2
      )
    port map(
      aclk => aclk,
      aresetn => aresetn,

      p_axi_ms => config_i,
      p_axi_sm => config_o,

      p_addr => config_addr_s,

      p_w_data => config_w_data_s,
      p_w_mask => config_w_mask_s,
      p_w_ready => config_w_ready_s,
      p_w_valid => config_w_valid_s,

      p_r_data => config_r_data_s,
      p_r_ready => config_r_ready_s,
      p_r_valid => config_r_valid_s
      );

  regs: process(aclk, aresetn) is
  begin
    if rising_edge(aclk) then
      r <= rin;
    end if;

    if aresetn = '0' then
      r.sub_ns_inc <= (others => '0');
      r.ns_adj <= (others => '0');
      r.axi_timestamp.second <= (others => '0');
      r.axi_timestamp.nanosecond <= (others => '0');
      r.read_ns_cap <= (others => '0');
      r.ns_adj_strobe <= '0';
      r.axi_timestamp_strobe <= '0';
    end if;
  end process;

  transition: process(r, config_addr_s, config_w_data_s, config_w_mask_s, config_w_valid_s, config_r_ready_s) is
    variable reg_index: integer range 0 to (2**config_addr_s'length) - 1;
  begin
    rin <= r;

    reg_index := to_integer(config_addr_s);

    rin.ns_adj_strobe <= '0';
    rin.axi_timestamp_strobe <= '0';
    
    if config_w_valid_s = '1' then
      case reg_index is
        when reg_sub_ns_inc_c =>
          rin.sub_ns_inc <= ufixed(config_w_data_s(rin.sub_ns_inc'left+16 downto rin.sub_ns_inc'right+16));

        when reg_ns_adj_c =>
          rin.ns_adj <= signed(config_w_data_s(rin.ns_adj'range));
          rin.ns_adj_strobe <= '1';

        when reg_timestamp_sec_c =>
          rin.axi_timestamp.second <= unsigned(config_w_data_s(rin.axi_timestamp.second'range));

        when reg_timestamp_ns_c =>
          rin.axi_timestamp.nanosecond <= unsigned(config_w_data_s(rin.axi_timestamp.nanosecond'range));
          rin.axi_timestamp_strobe <= '1';

        when others =>
          null;
      end case;
    end if;

    if config_r_ready_s = '1' and reg_index = reg_timestamp_sec_c then
      rin.read_ns_cap <= timestamp_s.nanosecond;
    end if;
  end process;

  mealy: process(r, timestamp_s) is
    variable reg_index: integer range 0 to (2**config_addr_s'length) - 1;
  begin
    rin <= r;

    config_w_ready_s <= '1';
    config_r_data_s <= (others => '0');
    config_r_valid_s <= '1';

    reg_index := to_integer(config_addr_s);
    
    case reg_index is
      when reg_sub_ns_inc_c =>
        config_r_data_s(rin.sub_ns_inc'left+16 downto rin.sub_ns_inc'right+16) <= to_suv(r.sub_ns_inc);

      when reg_ns_adj_c =>
        null;

      when reg_timestamp_sec_c =>
        config_r_data_s(timestamp_s.second'range) <= std_ulogic_vector(timestamp_s.second);

      when reg_timestamp_ns_c =>
        config_r_data_s(timestamp_s.nanosecond'range) <= std_ulogic_vector(r.read_ns_cap);

      when others =>
        null;
    end case;
  end process;

  backend: nsl_time.clock.clock_adjustable
    port map(
      clock_i => aclk,
      reset_n_i => aresetn,

      sub_nanosecond_inc_i => r.sub_ns_inc,

      nanosecond_adj_i => r.ns_adj,
      nanosecond_adj_set_i => r.ns_adj_strobe,

      timestamp_i => r.axi_timestamp,
      timestamp_set_i => r.axi_timestamp_strobe,
      
      timestamp_o => timestamp_s
      );

  timestamp_o <= timestamp_s;

end architecture;
