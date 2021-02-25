library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim, nsl_data;
use nsl_data.endian.all;

entity config_series7 is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    run_i : in std_ulogic;
    next_address_i : in unsigned(28 downto 0);
    rs_i : in std_ulogic_vector(1 downto 0) := "00";
    rs_en_i : in std_ulogic := '0'
    );
end entity;

architecture series7 of config_series7 is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_SEND_PRE,
    ST_SEND_WBSTAR,
    ST_SEND_POST
    );

  subtype config_word_t is std_ulogic_vector(31 downto 0);
  type config_word_vector is array (integer range <>) of config_word_t;

  type regs_t is
  record
    state : state_t;
    words_left: integer range 0 to 7;
    wbstar: std_ulogic_vector(31 downto 0);
  end record;

  constant config_pre : config_word_vector(3 downto 0) := (
    x"ffffffff", -- Dummy
    x"aa995566", -- Sync
    x"20000000", -- NOOP
    x"30020001"  -- Write WBSTAR
    );

  constant config_post : config_word_vector(2 downto 0) := (
    x"30008001", -- Write CMD
    x"0000000f", -- IPROG
    x"20000000"  -- NOOP
    );

  signal r, rin: regs_t;

  signal icape2_enable_n, icape2_write_n : std_ulogic;
  signal icape2_data : config_word_t;

  function wordswap(x:std_ulogic_vector) return std_ulogic_vector is
  begin
    return byteswap(bitswap(x));
  end function;

begin
  
  regs: process(clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, run_i, next_address_i, rs_i, rs_en_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if run_i = '1' then
          rin.wbstar <= (others => '0');
          rin.wbstar(next_address_i'range) <= std_ulogic_vector(next_address_i);
          rin.wbstar(31 downto 30) <= rs_i;
          rin.wbstar(29) <= rs_en_i;
          rin.state <= ST_SEND_PRE;
          rin.words_left <= config_pre'left;
        end if;

      when ST_SEND_PRE =>
        if r.words_left = 0 then
          rin.state <= ST_SEND_WBSTAR;
        else
          rin.words_left <= r.words_left - 1;
        end if;

      when ST_SEND_WBSTAR =>
        rin.state <= ST_SEND_POST;
        rin.words_left <= config_post'left;

      when ST_SEND_POST =>
        if r.words_left = 0 then
          rin.state <= ST_IDLE;
        else
          rin.words_left <= r.words_left - 1;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    icape2_enable_n <= '1';
    icape2_write_n <= '1';
    icape2_data <= (others => '-');

    case r.state is
      when ST_IDLE | ST_RESET =>
        null;

      when ST_SEND_PRE =>
        icape2_enable_n <= '0';
        icape2_write_n <= '0';
        icape2_data <= config_pre(r.words_left);

      when ST_SEND_WBSTAR =>
        icape2_enable_n <= '0';
        icape2_write_n <= '0';
        icape2_data <= r.wbstar;

      when ST_SEND_POST =>
        icape2_enable_n <= '0';
        icape2_write_n <= '0';
        icape2_data <= config_post(r.words_left);
    end case;
  end process;

  icape2_instance: unisim.vcomponents.icape2
    port map(
      clk => clock_i,
      csib => icape2_enable_n,
      i => std_logic_vector(wordswap(std_ulogic_vector(icape2_data))),
      rdwrb => icape2_write_n
      );
  
end architecture;
