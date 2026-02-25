library ieee;
use ieee.std_logic_1164.all;

library unisim;

entity serdes_sdr10_output is
    generic (
        left_to_right_c : boolean := false
    );
    port (
        bit_clock_i     : in std_ulogic;
        gearbox_clock_i : in std_ulogic := '0';
        word_clock_i    : in std_ulogic;
        reset_n_i       : in std_ulogic;

        serdes_strobe_i : in std_ulogic := '0';

        parallel_i : in  std_ulogic_vector(0 to 9);
        serial_o   : out std_ulogic
    );
end entity;

architecture series6 of serdes_sdr10_output is

    signal reset : std_ulogic;
    signal d     : std_ulogic_vector(0 to 9);

    signal cascade_do : std_ulogic;
    signal cascade_to : std_ulogic;
    signal cascade_di : std_ulogic;
    signal cascade_ti : std_ulogic;

    -- Gearbox: 10 bits @ 100MHz -> 2x5 bits @ 200MHz
    signal received_word_s : std_ulogic_vector(0 to 9);
    signal high_nlow_s     : boolean;
    signal gearbox_data_s  : std_ulogic_vector(0 to 4);
begin

    reset <= not reset_n_i;

    ltr : if left_to_right_c
        generate
        d <= parallel_i;
    end generate;

    rtl : if not left_to_right_c
        generate
        in_map : for i in 0 to 9
            generate
            d(9 - i) <= parallel_i(i);
        end generate;
    end generate;

    process (word_clock_i, reset_n_i)
    begin
        if rising_edge(word_clock_i) then
            received_word_s <= d;
        end if;

        if reset_n_i = '0' then
            received_word_s <= (others => '0');
        end if;
    end process;

    gearbox_proc : process (gearbox_clock_i, reset_n_i)
    begin
        if rising_edge(gearbox_clock_i) then
            if high_nlow_s then
                gearbox_data_s <= received_word_s(0 to 4);
            else
                gearbox_data_s <= received_word_s(5 to 9);
            end if;
            high_nlow_s <= not high_nlow_s;
        end if;

        if reset_n_i = '0' then
            high_nlow_s    <= true;
            gearbox_data_s <= (others => '0');
        end if;
    end process;

    master : unisim.vcomponents.OSERDES2
    generic map(
        DATA_WIDTH   => 5,
        DATA_RATE_OQ => "SDR",
        DATA_RATE_OT => "SDR",
        SERDES_MODE  => "MASTER",
        OUTPUT_MODE  => "SINGLE_ENDED"
    )
    port map(
        OQ     => serial_o,
        OCE    => '1',
        CLK0   => bit_clock_i,
        CLK1   => '0',
        IOCE   => serdes_strobe_i,
        RST    => reset,
        CLKDIV => gearbox_clock_i,

        D4 => '0',
        D3 => '0',
        D2 => '0',
        D1 => gearbox_data_s(4),

        TQ    => open,
        T1    => '0',
        T2    => '0',
        T3    => '0',
        T4    => '0',
        TRAIN => '0',
        TCE   => '1',

        SHIFTIN1 => '1',        -- Dummy input in Master
        SHIFTIN2 => '1',        -- Dummy input in Master
        SHIFTIN3 => cascade_do, -- From Slave
        SHIFTIN4 => cascade_to, -- From Slave

        SHIFTOUT1 => cascade_di, -- To Slave
        SHIFTOUT2 => cascade_ti, -- To Slave
        SHIFTOUT3 => open,       -- Dummy output
        SHIFTOUT4 => open        -- Dummy output
    );

    slave : unisim.vcomponents.OSERDES2
    generic map(
        DATA_WIDTH   => 5,
        DATA_RATE_OQ => "SDR",
        DATA_RATE_OT => "SDR",
        SERDES_MODE  => "SLAVE",
        OUTPUT_MODE  => "DIFFERENTIAL"
    )
    port map(
        OQ     => open,
        OCE    => '1',
        CLK0   => bit_clock_i,
        CLK1   => '0',
        IOCE   => serdes_strobe_i,
        RST    => reset,
        CLKDIV => gearbox_clock_i,

        D4 => gearbox_data_s(3),
        D3 => gearbox_data_s(2),
        D2 => gearbox_data_s(1),
        D1 => gearbox_data_s(0),

        TQ    => open,
        T1    => '0',
        T2    => '0',
        T3    => '0',
        T4    => '0',
        TRAIN => '0',
        TCE   => '1',

        SHIFTIN1 => cascade_di, -- From Master
        SHIFTIN2 => cascade_ti, -- From Master
        SHIFTIN3 => '1',        -- Dummy input in Slave
        SHIFTIN4 => '1',        -- Dummy input in Slave

        SHIFTOUT1 => open,       -- Dummy output
        SHIFTOUT2 => open,       -- Dummy output
        SHIFTOUT3 => cascade_do, -- To Master
        SHIFTOUT4 => cascade_to  -- To Master
    );

end architecture;
