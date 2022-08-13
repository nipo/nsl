library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_data, nsl_math, nsl_logic, nsl_bnoc, nsl_i2c, work;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_bnoc.framed_transactor.all;
use nsl_bnoc.framed.all;
use work.si5351.all;

entity si5351_config_switcher is
  generic(
    i2c_addr_c: unsigned(6 downto 0) := "1100000";
    config_c: config_vector
    );
  port(
    reset_n_i   : in std_ulogic;
    clock_i     : in std_ulogic;

    -- Forces refresh
    force_i : in std_ulogic := '0';
    busy_o  : out std_ulogic;

    ms0_i : natural range 0 to config_c'length-1;
    ms1_i : natural range 0 to config_c'length-1;
    ms2_i : natural range 0 to config_c'length-1;
    ms3_i : natural range 0 to config_c'length-1;
    ms4_i : natural range 0 to config_c'length-1;
    ms5_i : natural range 0 to config_c'length-1;
    ms6_i : natural range 0 to config_c'length-1;
    ms7_i : natural range 0 to config_c'length-1;

    cmd_o  : out framed_req;
    cmd_i  : in  framed_ack;
    rsp_i  : in  framed_req;
    rsp_o  : out framed_ack
    );
end entity;

architecture beh of si5351_config_switcher is

  subtype config_index_t is natural range 0 to config_c'length-1;
  type config_index_vector is array(natural range 0 to 7) of config_index_t;
  
  type config_data05_t is
  record
    control: byte_string(0 to 0);
    ms: byte_string(0 to 7);
  end record;

  type config_data67_t is
  record
    control: byte_string(0 to 0);
    ms: byte_string(0 to 0);
  end record;

  type config_data05_vector is array(natural range <>) of config_data05_t;
  type config_data67_vector is array(natural range <>) of config_data67_t;

  function control05_generate(cfg: config_t) return byte_string is
    constant pdn: std_ulogic := to_logic(not cfg.enabled);
    constant int: std_ulogic := to_logic(cfg.integer_only);
    constant src: std_ulogic := to_logic(cfg.pll = MS_SRC_PLLB);
    constant inv: std_ulogic := to_logic(cfg.inverted);
    constant src10: std_ulogic_vector(1 downto 0) := std_ulogic_vector(to_unsigned(drv_src_t'pos(cfg.source), 2));
    constant idrv10: std_ulogic_vector(1 downto 0) := std_ulogic_vector(to_unsigned(drv_strength_t'pos(cfg.strength), 2));
    variable ret: byte_string(0 to 0);
  begin
    ret(0) := pdn & int & src & inv & src10 & idrv10;
    return ret;
  end function;
  
  function control67_generate(cfg: config_t) return byte_string is
    constant pdn: std_ulogic := to_logic(not cfg.enabled);
    constant int: std_ulogic := to_logic(false);
    constant src: std_ulogic := to_logic(cfg.pll = MS_SRC_PLLB);
    constant inv: std_ulogic := to_logic(cfg.inverted);
    constant src10: std_ulogic_vector(1 downto 0) := std_ulogic_vector(to_unsigned(drv_src_t'pos(cfg.source), 2));
    constant idrv10: std_ulogic_vector(1 downto 0) := std_ulogic_vector(to_unsigned(drv_strength_t'pos(cfg.strength), 2));
    variable ret: byte_string(0 to 0);
  begin
    ret(0) := pdn & int & src & inv & src10 & idrv10;
    return ret;
  end function;

  function ms05_generate(cfg: config_t) return byte_string is
    variable p1, p2, p3: integer;
    variable p1u: unsigned(17 downto 0);
    variable p2u: unsigned(19 downto 0);
    variable p3u: unsigned(19 downto 0);
    constant div: unsigned(2 downto 0) := "000";
    variable divby4: std_ulogic;
    variable bratio, rfrac: real;
    variable rint: integer;
    variable div4: boolean;
  begin
    div4 := false;
    if cfg.ratio = 4.0 then
      p1 := 0;
      p2 := 0;
      p3 := 1;
      div4 := true;
    else
      assert cfg.ratio >= 8.0 and cfg.ratio <= 2048.0
        report "Bad divisor"
        severity failure;
      bratio := (cfg.ratio - 4.0) * 128.0;
      rint := integer(floor(bratio));
      rfrac := bratio - real(rint);
      p1 := rint;
      p2 := integer(round(rfrac * real(cfg.denom)));
      p3 := cfg.denom;
    end if;

    divby4 := to_logic(div4);
    p1u := to_unsigned(p1, 18);
    p2u := to_unsigned(p2, 20);
    p3u := to_unsigned(p3, 20);

    return to_be(p3u(15 downto 0)
                 & "0" & div & divby4 & divby4 & p1u(17 downto 0)
                 & p3u(19 downto 16) & p2u(19 downto 0));
  end function;
  
  function ms67_generate(cfg: config_t) return byte_string is
    variable p1u: unsigned(7 downto 0) := to_unsigned(integer(cfg.ratio / 2.0) * 2, 8);
  begin
    return to_be(p1u);
  end function;

  function config_data05_generate(cfg: config_vector) return config_data05_vector is
    alias config: config_vector(0 to cfg'length-1) is cfg;
    variable ret : config_data05_vector(0 to cfg'length-1);
  begin
    for i in ret'range
    loop
      ret(i).control := control05_generate(config(i));
      ret(i).ms := ms05_generate(config(i));
    end loop;
    return ret;
  end function;

  function config_data67_generate(cfg: config_vector) return config_data67_vector is
    alias config: config_vector(0 to cfg'length-1) is cfg;
    variable ret : config_data67_vector(0 to cfg'length-1);
  begin
    for i in ret'range
    loop
      ret(i).control := control67_generate(config(i));
      ret(i).ms := ms67_generate(config(i));
    end loop;
    return ret;
  end function;

  constant config_data05_c : config_data05_vector := config_data05_generate(config_c);
  constant config_data67_c : config_data67_vector := config_data67_generate(config_c);
  
  type state_t is (
    ST_RESET,
    ST_IDLE,

    ST_PUT_CONTROL05,
    ST_PUT_MS05,
    ST_PUT_CONTROL67,
    ST_PUT_MS67
    );

  signal config_index_s: config_index_vector;

  subtype controller_data_t is byte_string(0 to 7);
  signal controller_valid_s, controller_ready_s : std_ulogic;
  signal controller_addr_s : unsigned(7 downto 0);
  signal controller_data_s : controller_data_t;
  signal controller_data_len_s : natural range 1 to controller_data_s'length;

  type regs_t is
  record
    state: state_t;
    config_index: config_index_vector;
    config_dirty: std_ulogic_vector(0 to 7);
    index: natural range 0 to 7;
  end record;

  signal r, rin : regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  config_index_s(0) <= ms0_i;
  config_index_s(1) <= ms1_i;
  config_index_s(2) <= ms2_i;
  config_index_s(3) <= ms3_i;
  config_index_s(4) <= ms4_i;
  config_index_s(5) <= ms5_i;
  config_index_s(6) <= ms6_i;
  config_index_s(7) <= ms7_i;
  
  transition: process(r, config_index_s, force_i, controller_ready_s) is
  begin
    rin <= r;

    for i in config_index_s'range
    loop
      if r.config_index(i) /= config_index_s(i) then
        rin.config_dirty(i) <= '1';
      end if;
    end loop;

    case r.state is
      when ST_RESET =>
        rin.config_dirty <= (others => '1');
        rin.state <= ST_IDLE;
        rin.index <= 0;

      when ST_IDLE =>
        if r.config_dirty(r.index) = '1' then
          if r.index < 6 then
            rin.state <= ST_PUT_CONTROL05;
          else
            rin.state <= ST_PUT_CONTROL67;
          end if;
          rin.config_dirty(r.index) <= '0';
          rin.config_index(r.index) <= config_index_s(r.index);
        else
          rin.index <= (r.index + 1) mod 8;
        end if;

      when ST_PUT_CONTROL05 =>
        if controller_ready_s = '1' then
          rin.state <= ST_PUT_MS05;
        end if;
        
      when ST_PUT_CONTROL67 =>
        if controller_ready_s = '1' then
          rin.state <= ST_PUT_MS67;
        end if;

      when ST_PUT_MS05 | ST_PUT_MS67 =>
        if controller_ready_s = '1' then
          rin.state <= ST_IDLE;
          rin.index <= (r.index + 1) mod 8;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    controller_valid_s <= '0';
    controller_data_s <= (others => "--------");
    controller_data_len_s <= 1;
    controller_addr_s <= "--------";

    case r.state is
      when ST_RESET =>
        busy_o <= '0';

      when ST_IDLE =>
        busy_o <= '0';
        for i in r.config_dirty'range
        loop
          if r.config_dirty(i) = '1' then
            busy_o <= '1';
          end if;
        end loop;

      when ST_PUT_CONTROL05 =>
        busy_o <= '1';
        controller_valid_s <= '1';
        controller_data_len_s <= config_data05_c(r.config_index(r.index)).control'length;
        controller_data_s(0 to config_data05_c(r.config_index(r.index)).control'length-1)
          <= config_data05_c(r.config_index(r.index)).control;
        controller_addr_s <= to_unsigned(16 + r.index, 8);

      when ST_PUT_CONTROL67 =>
        busy_o <= '1';
        controller_valid_s <= '1';
        controller_data_len_s <= config_data67_c(r.config_index(r.index)).control'length;
        controller_data_s(0 to config_data67_c(r.config_index(r.index)).control'length-1)
          <= config_data67_c(r.config_index(r.index)).control;
        controller_addr_s <= to_unsigned(16 + r.index, 8);

      when ST_PUT_MS05 =>
        busy_o <= '1';
        controller_valid_s <= '1';
        controller_data_len_s <= config_data05_c(r.config_index(r.index)).ms'length;
        controller_data_s(0 to config_data05_c(r.config_index(r.index)).ms'length-1)
          <= config_data05_c(r.config_index(r.index)).ms;
        controller_addr_s <= to_unsigned(42 + r.index * 8, 8);

      when ST_PUT_MS67 =>
        busy_o <= '1';
        controller_valid_s <= '1';
        controller_data_len_s <= config_data67_c(r.config_index(r.index)).ms'length;
        controller_data_s(0 to config_data67_c(r.config_index(r.index)).ms'length-1)
          <= config_data67_c(r.config_index(r.index)).ms;
        controller_addr_s <= to_unsigned(90 + r.index - 6, 8);
    end case;
  end process;

  controller: nsl_i2c.transactor.framed_addressed_controller
    generic map(
      addr_byte_count_c => controller_addr_s'length / 8,
      big_endian_c => false,
      txn_byte_count_max_c => controller_data_s'length
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      cmd_i => cmd_i,
      cmd_o => cmd_o,
      rsp_i => rsp_i,
      rsp_o => rsp_o,

      valid_i => controller_valid_s,
      ready_o => controller_ready_s,
      saddr_i => i2c_addr_c,
      addr_i => controller_addr_s,
      write_i => '1',
      wdata_i => controller_data_s,
      data_byte_count_i => controller_data_len_s,

      valid_o => open,
      ready_i => '1',
      rdata_o => open,
      error_o => open
      );
  
end architecture;
