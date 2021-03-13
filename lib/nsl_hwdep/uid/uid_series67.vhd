library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;

library nsl_data;
use nsl_data.crc.all;

entity uid32_reader is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    done_o : out std_ulogic;
    uid_o : out unsigned(31 downto 0)
    );
end entity;

architecture xil of uid32_reader is

  type state_t is (
    ST_RESET,
    ST_READ,
    ST_DONE
    );

  type regs_t is
  record
    state : state_t;

    counter : integer range 36 downto 8;
    crc32 : crc32;
  end record;

  signal r, rin: regs_t;
  signal s_dna_dout, s_dna_read, s_dna_shift : std_ulogic;
  
begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, s_dna_dout)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.counter <= 36;
        rin.crc32 <= crc_ieee_802_3_init;
        rin.state <= ST_READ;

      when ST_READ =>
        if r.counter = 0 then
          rin.state <= ST_DONE;
        else
          rin.counter <= r.counter - 1;
        end if;

        rin.crc32 <= crc_update(init => r.crc32,
                                poly => crc_ieee_802_3_poly,
                                insert_msb => crc_ieee_802_3_insert_msb,
                                v => s_dna_dout);

      when ST_DONE =>
        null;
    end case;
  end process;

  moore: process(r)
  begin
    s_dna_read <= '0';
    s_dna_shift <= '0';
    done_o <= '0';
    uid_o <= unsigned(r.crc32);

    case r.state is
      when ST_RESET =>
        s_dna_read <= '1';

      when ST_READ =>
        s_dna_shift <= '1';

      when ST_DONE =>
        done_o <= '1';
    end case;
  end process;

  dna_port: unisim.vcomponents.dna_port
    port map(
      clk => clock_i,
      shift => s_dna_shift,
      read => s_dna_read,
      din => '0',
      dout => s_dna_dout
      );
  
end architecture;
