library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_narrower is
  generic(
    part_count_c : integer;
    out_width_c : integer
    );
  port(
    reset_n_i  : in  std_ulogic;
    clock_i     : in  std_ulogic;

    out_data_o    : out std_ulogic_vector(out_width_c-1 downto 0);
    out_ready_i    : in  std_ulogic;
    out_valid_o : out std_ulogic;

    in_data_i   : in  std_ulogic_vector(part_count_c*out_width_c-1 downto 0);
    in_valid_i  : in  std_ulogic;
    in_ready_o : out std_ulogic
    );
end fifo_narrower;

architecture rtl of fifo_narrower is

  constant width_in_c : integer := out_width_c * part_count_c;

  type regs_t is
  record
    buf : std_ulogic_vector(width_in_c-1 downto 0);
    filled : natural range 0 to part_count_c;
  end record;

  signal r, rin: regs_t;

begin

  reg: process (clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.filled <= 0;
    elsif clock_i'event and clock_i = '1' then
      r <= rin;
    end if;
  end process reg;

  process (in_valid_i, in_data_i, out_ready_i, r)
  begin
    rin <= r;

    if r.filled = 0 then
      if in_valid_i = '1' then
        rin.filled <= part_count_c;
        rin.buf <= in_data_i;
      end if;
    elsif out_ready_i = '1' then
      rin.filled <= r.filled - 1;
      rin.buf <= (others => '-');
      rin.buf(width_in_c - out_width_c - 1 downto 0)
        <= r.buf(width_in_c - 1 downto out_width_c);
    end if;
  end process;

  out_valid_o <= '0' when r.filled = 0 else '1';
  in_ready_o <= '1' when r.filled = 0 else '0';
  out_data_o <= r.buf(out_width_c - 1 downto 0);
   
end rtl;
