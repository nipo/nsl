library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_math, nsl_data;
use nsl_math.fixed.all;

entity rect_table is
  port (
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    angle_i : in ufixed;
    ready_o : out std_ulogic;
    valid_i : in std_ulogic;

    sinus_o : out sfixed;
    cosinus_o : out sfixed;
    valid_o : out std_ulogic;
    ready_i : in std_ulogic
    );
end rect_table;

architecture beh of rect_table is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_READING,
    ST_RESP
    );

  type regs_t is
  record
    state : state_t;
    address : unsigned(angle_i'length-1 downto 0);
  end record;

  constant dt_bit_count : integer := sinus_o'length + cosinus_o'length;
  constant dt_byte_count : integer := (dt_bit_count + 7) / 8;
  subtype dt_word_type is std_ulogic_vector(dt_byte_count*8 - 1 downto 0);
  
  signal r, rin: regs_t;
  signal rdata: dt_word_type;

  function table_precalc() return nsl_data.bytestream.byte_string is
    variable sinus : sfixed(sinus_o'range);
    variable cosinus : sfixed(sinus_o'range);
    variable angle_r, sinus_r, cosinus_r : real;
    variable ret : nsl_data.bytestream.byte_string(0 to ((2**angle_i'length) * dt_byte_count)-1);
    variable entry : dt_word_type;
  begin
    each_angle: for i in 0 to 2**angle_i'length-1
    loop
      angle_r := i * 2.0 ** angle_i'right;
      sinus_r := sin(angle_r * math_pi);
      cosinus_r := cos(angle_r * math_pi);
      sinus := to_sfixed(sinus_r, sinus'left, sinus'right);
      cosinus := to_sfixed(cosinus_r, cosinus'left, cosinus'right);
      entry(sinus_o'length-1 downto 0) := to_suv(sinus);
      entry(sinus_o'length + cosinus_o'length-1 downto sinus_o'length) := to_suv(cosinus);
      ret(dt_byte_count*i to dt_byte_count * i + dt_byte_count) := nsl_data.endian.to_le(entry);
    end loop;
    return ret;
  end function;
  
begin

  assert angle_i'left = 0
    report "angle_i'left must be 0"
    severity failure;

  assert sinus_o'left = 0
    report "sinus_o'left must be 0"
    severity failure;

  assert cosinus_o'left = 0
    report "cosinus_o'left must be 0"
    severity failure;
  
  regs: process(clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, valid_i, ready_i, angle_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
      when ST_IDLE =>
        if valid_i = '1' then
          rin.state <= ST_READING;
          rin.address <= unsigned(std_ulogic_vector(angle_i));
        end if;
      when ST_READING =>
        rin.state <= ST_RESP;
      when ST_RESP =>
        if ready_i = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    valid_o <= '0';
    ready_o <= '0';
    value_o <= (others => '-');

    case r.state is
      when ST_RESET | ST_READING =>
        null;
      when ST_IDLE =>
        ready_o <= '1';
      when ST_RESP =>
        valid_o <= '1';
    end case;
  end process;

  storage: nsl_memory.rom.rom_bytes
    generic map(
      word_addr_size_c => angle_i'length,
      word_byte_count_c => dt_byte_count,
      contents_c => table_precalc()
      )
    port map(
      clock_i => clock_i,

      address_i => r.address,
      data_o => rdata
      );

  sinus_o <= sfixed(rdata(sinus_o'length-1 downto 0));
  cosinus_o <= sfixed(rdata(sinus_o'length + cosinus_o'length-1 downto sinus_o'length));

end architecture;
