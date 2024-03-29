library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_widener is
  generic(
    part_count_c    : integer;
    in_width_c : integer
    );
  port(
    reset_n_i : in std_ulogic;
    clk_i     : in std_ulogic;

    out_data_o  : out std_ulogic_vector(part_count_c*in_width_c-1 downto 0);
    out_ready_i : in  std_ulogic;
    out_valid_o : out std_ulogic;

    in_data_i  : in  std_ulogic_vector(in_width_c-1 downto 0);
    in_valid_i : in  std_ulogic;
    in_ready_o : out std_ulogic
    );
end fifo_widener;

architecture rtl of fifo_widener is

  constant width_out_c : integer := in_width_c * part_count_c;

  type regs_t is
  record
    buf : std_ulogic_vector(width_out_c-1 downto 0);
    filled : natural range 0 to part_count_c;
  end record;

  signal r, rin : regs_t;

begin

  reg: process (clk_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.filled <= 0;
    elsif clk_i'event and clk_i = '1' then
      r <= rin;
    end if;
  end process reg;

  process (r, in_valid_i, out_ready_i, in_data_i)
  begin
    rin <= r;

    if r.filled /= part_count_c then
      if in_valid_i = '1' then
        rin.filled <= r.filled + 1;
        rin.buf <= in_data_i & r.buf(r.buf'left downto in_width_c);
      end if;
    elsif out_ready_i = '1' then
        rin.filled <= 0;
    end if;
  end process;
  
  out_valid_o <= '1' when r.filled = part_count_c else '0';
  in_ready_o <= '1' when r.filled /= part_count_c else '0';
  out_data_o <= r.buf;
   
end rtl;
