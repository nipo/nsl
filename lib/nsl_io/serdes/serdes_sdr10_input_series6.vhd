library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim, nsl_data;

entity serdes_sdr10_input is
    generic (
        left_to_right_c : boolean := false
    );
    port (
        bit_clock_i     : in std_ulogic;
        gearbox_clock_i : in std_ulogic := '0';
        word_clock_i    : in std_ulogic;
        reset_n_i       : in std_ulogic;

        serdes_strobe_i : in std_ulogic := '0';

        serial_i   : in  std_ulogic;
        parallel_o : out std_ulogic_vector(0 to 9);

        bitslip_i : in  std_ulogic;
        mark_o    : out std_ulogic
    );
end entity;

architecture series6 of serdes_sdr10_input is

    signal reset_s : std_ulogic;

    signal cascade     : std_ulogic;
    signal d_word_sync : std_ulogic_vector(0 to 9);
    signal d           : std_ulogic_vector(0 to 9);
    signal slip_count  : integer range 0 to 9;

    signal mark_s     : std_ulogic;
    signal old_mark_s : std_ulogic;

    signal invert_s      : boolean;
    signal high_nlow_s   : boolean;
    signal parallel_s    : std_ulogic_vector(0 to 4);
    signal gearbox_reg_s : std_ulogic_vector(0 to 4);
begin

    reset_s <= not reset_n_i;

    output : process (d_word_sync) is
    begin
        if not left_to_right_c then
            parallel_o <= d_word_sync;
        else
            for i in 0 to 9 loop
                parallel_o(9 - i) <= d_word_sync(i);
            end loop;
        end if;
    end process;

    slip_tracker : process (gearbox_clock_i) is
    begin
        if rising_edge(gearbox_clock_i) then
            if reset_n_i = '0' then
                slip_count <= 9;
            else
                if bitslip_i = '1' then
                    if slip_count = 0 then
                        slip_count <= 9;
                    else
                        slip_count <= slip_count - 1;
                    end if;
                end if;
            end if;
        end if;

    end process;

    mark_s <= '1' when slip_count = 0 else
              '0';
    mark_o <= mark_s;

    invert_s <= slip_count >= 5;

    master : unisim.vcomponents.ISERDES2
    generic map(
        BITSLIP_ENABLE => true,
        DATA_RATE      => "SDR",
        DATA_WIDTH     => 5,
        INTERFACE_TYPE => "NETWORKING",
        SERDES_MODE    => "MASTER"
    )
    port map(
        CE0    => '1',
        CLK0   => bit_clock_i,
        CLK1   => '0',
        CLKDIV => gearbox_clock_i,
        RST    => reset_s,

        D        => serial_i,
        Q1       => parallel_s(3),
        Q2       => parallel_s(2),
        Q3       => parallel_s(1),
        Q4       => parallel_s(0),
        SHIFTOUT => cascade,

        BITSLIP => bitslip_i,
        IOCE    => serdes_strobe_i,
        SHIFTIN => '0'
    );

    slave : unisim.vcomponents.ISERDES2
    generic map(
        BITSLIP_ENABLE => true,
        DATA_RATE      => "SDR",
        DATA_WIDTH     => 5,
        INTERFACE_TYPE => "NETWORKING",
        SERDES_MODE    => "SLAVE"
    )
    port map(
        CE0    => '1',
        CLK0   => bit_clock_i,
        CLK1   => '0',
        CLKDIV => gearbox_clock_i,
        RST    => reset_s,

        Q4 => parallel_s(4),

        D       => '0',
        BITSLIP => bitslip_i,
        IOCE    => serdes_strobe_i,
        SHIFTIN => cascade
    );

    gearbox_proc : process (gearbox_clock_i)
    begin
        if rising_edge(gearbox_clock_i) then
            if reset_n_i = '0' then
                high_nlow_s <= true;
                old_mark_s  <= mark_s;
            else
                if high_nlow_s then
                    gearbox_reg_s <= parallel_s;
                else
                    if not invert_s then
                        d <= gearbox_reg_s & parallel_s;
                    else
                        d <= parallel_s & gearbox_reg_s;
                    end if;
                end if;

                old_mark_s <= mark_s;
                if not (mark_s = '1' and old_mark_s = '0') then
                    high_nlow_s <= not high_nlow_s;
                end if;
            end if;
        end if;
    end process;

    word_proc : process (word_clock_i)
    begin
        if rising_edge(word_clock_i) then
            d_word_sync <= d;
        end if;
    end process;

end architecture;
