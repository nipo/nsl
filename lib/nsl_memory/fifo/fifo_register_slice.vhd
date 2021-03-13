library ieee;
use ieee.std_logic_1164.all;

entity fifo_register_slice is
  generic(
    data_width_c   : integer
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i    : in  std_ulogic;

    out_data_o          : out std_ulogic_vector(data_width_c-1 downto 0);
    out_ready_i         : in  std_ulogic;
    out_valid_o         : out std_ulogic;

    in_data_i       : in  std_ulogic_vector(data_width_c-1 downto 0);
    in_valid_i      : in  std_ulogic;
    in_ready_o      : out std_ulogic
    );

end fifo_register_slice;

architecture rtl of fifo_register_slice is

  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);

  type state_t is (
    ST_RESET,
    ST_EMPTY,
    ST_PIPE,
    ST_FULL
    );

  type word_vector_t is array(natural range 0 to 1) of word_t;
    
  type regs_t is
  record
    state: state_t;
    data: word_vector_t;
  end record;

  signal r, rin: regs_t;

  attribute keep : string;
  attribute nomerge : string;
  attribute keep of r : signal is "TRUE";
  attribute nomerge of r : signal is "true";

begin

  regs: process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      if reset_n_i = '0' then
        r.state <= ST_RESET;
      else
        r <= rin;
      end if;
    end if;
  end process;

  transition: process(r, out_ready_i, in_data_i, in_valid_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_EMPTY;

      when ST_EMPTY =>
        if in_valid_i = '1' then
          rin.data(0) <= in_data_i;
          rin.state <= ST_PIPE;
        end if;

      when ST_PIPE =>
        if in_valid_i = '1' and out_ready_i = '1' then
          rin.data(0) <= in_data_i;
        elsif in_valid_i = '1' and out_ready_i = '0' then
          rin.data(1) <= in_data_i;
          rin.state <= ST_FULL;
        elsif in_valid_i = '0' and out_ready_i = '1' then
          rin.state <= ST_EMPTY;
        end if;

      when ST_FULL =>
        if out_ready_i = '1' then
          rin.data(0) <= r.data(1);
          rin.state <= ST_PIPE;
        end if;

    end case;
  end process;

  moore: process(r)
  begin
    out_valid_o <= '0';
    in_ready_o <= '0';
    out_data_o <= (others => '-');

    case r.state is
      when ST_RESET =>
        null;

      when ST_EMPTY =>
        in_ready_o <= '1';

      when ST_PIPE =>
        out_valid_o <= '1';
        out_data_o <= r.data(0);
        in_ready_o <= '1';

      when ST_FULL =>
        out_valid_o <= '1';
        out_data_o <= r.data(0);
    end case;
  end process;
  
end rtl;
