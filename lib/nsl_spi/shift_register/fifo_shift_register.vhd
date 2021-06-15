library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.endian.bitswap;

entity fifo_shift_register is
  generic(
    divisor_max_c : natural := 0;
    width_c : natural := 8;
    msb_first_c : boolean := true
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    divisor_i : in integer range 0 to divisor_max_c := divisor_max_c;
    cpol_i : in std_ulogic := '0';
    cpha_i : in std_ulogic := '0';
    
    data_i : in std_ulogic_vector(width_c-1 downto 0);
    valid_i : in std_ulogic;
    ready_o : out std_ulogic;

    data_o : out std_ulogic_vector(width_c-1 downto 0);
    valid_o : out std_ulogic;
    ready_i : in std_ulogic := '1';

    sd_o : out std_ulogic;
    sck_o : out std_ulogic;
    sd_i : in std_ulogic
    );
end entity;

architecture beh of fifo_shift_register is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_FIRST_HALF,
    ST_SECOND_HALF,
    ST_DATA_PUT
    );
  
  type regs_t is
  record
    state: state_t;
    div_reload, div: integer range 0 to divisor_max_c;
    shreg: std_ulogic_vector(width_c-1 downto 0);
    left: natural range 0 to width_c;
    sd : std_ulogic;
    cpol : std_ulogic;
    cpha : std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, valid_i, data_i, sd_i, ready_i, divisor_i, cpha_i, cpol_i)
  begin
    rin <= r;

    rin.cpha <= cpha_i;
    rin.cpol <= cpol_i;
    rin.div_reload <= divisor_i;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if valid_i = '1' then
          if msb_first_c then
            rin.shreg <= data_i;
            rin.sd <= data_i(data_i'left);
          else
            rin.shreg <= bitswap(data_i);
            rin.sd <= data_i(data_i'right);
          end if;

          rin.left <= data_i'length-1;
          rin.state <= ST_FIRST_HALF;
          rin.div <= r.div_reload;
        end if;

      when ST_FIRST_HALF =>
        if divisor_max_c /= 0 and r.div /= 0 then
          rin.div <= r.div - 1;
        else
          rin.div <= r.div_reload;
          rin.state <= ST_SECOND_HALF;
          rin.shreg <= r.shreg(r.shreg'left-1 downto 0) & sd_i;
        end if;

      when ST_SECOND_HALF =>
        if divisor_max_c /= 0 and r.div /= 0 then
          rin.div <= r.div - 1;
        else
          rin.div <= r.div_reload;

          if r.left /= 0 then
            rin.sd <= r.shreg(r.shreg'left);
            rin.state <= ST_FIRST_HALF;
            rin.left <= r.left - 1;
          else
            rin.state <= ST_DATA_PUT;
          end if;
        end if;

      when ST_DATA_PUT =>
        if ready_i = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    ready_o <= '0';
    valid_o <= '0';
    if msb_first_c then
      data_o <= r.shreg;
    else
      data_o <= bitswap(r.shreg);
    end if;
    sd_o <= r.sd;
    sck_o <= r.cpol xor r.cpha;

    case r.state is
      when ST_SECOND_HALF =>
        sck_o <= r.cpol xnor r.cpha;

      when ST_FIRST_HALF =>
        sck_o <= r.cpol xor r.cpha;

      when ST_IDLE =>
        ready_o <= '1';

      when ST_DATA_PUT =>
        valid_o <= '1';

      when others =>
        null;
    end case;
  end process;

end architecture;
