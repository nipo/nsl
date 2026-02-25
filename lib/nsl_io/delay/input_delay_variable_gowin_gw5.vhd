library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity input_delay_variable is
    port (
        clock_i   : in  std_ulogic;
        reset_n_i : in  std_ulogic;
        mark_o    : out std_ulogic;
        shift_i   : in  std_ulogic;

        data_i : in  std_ulogic;
        data_o : out std_ulogic
    );
end entity;

architecture gowin of input_delay_variable is

    component iodelay
        generic (
            c_static_dly : integer := 0;
            dyn_dly_en   : string  := "FALSE";
            adapt_en     : string  := "FALSE"
        );
        port (
            do      : out std_logic;
            df      : out std_logic;
            di      : in  std_logic;
            sdtap   : in  std_logic;
            value   : in  std_logic;
            dlystep : in  std_logic_vector(7 downto 0)
        );
    end component;

    constant tap_step_count_c : integer := 256;
    signal step_count_s       : unsigned(7 downto 0);
begin

    regs : process (clock_i, reset_n_i) is
    begin
        if rising_edge(clock_i) then
            if shift_i = '1' then
                if step_count_s = 0 then
                    step_count_s <= to_unsigned(tap_step_count_c - 1, step_count_s'length);
                else
                    step_count_s <= step_count_s - 1;
                end if;
            end if;
        end if;

        if reset_n_i = '0' then
            step_count_s <= to_unsigned(0, step_count_s'length);
        end if;
    end process;

    mark_o <= '1' when step_count_s = 0 else
              '0';

    inst : iodelay
    generic map(
        dyn_dly_en => "TRUE"
    )
    port map(
        di      => data_i,
        sdtap   => '0',
        dlystep => std_logic_vector(step_count_s),
        value   => shift_i,
        df      => open,
        do      => data_o
    );
end architecture;
