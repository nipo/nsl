library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_receiver is
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    sck_i : in  std_ulogic;
    ws_i  : in  std_ulogic;
    sd_i  : in  std_ulogic;

    valid_o : out std_ulogic;
    channel_o : out std_ulogic;
    data_o  : out unsigned
    );
end entity;

architecture beh of i2s_receiver is

  type regs_t is
  record
    ws : std_ulogic;
    sck : std_ulogic;
    rx, en : unsigned(data_o'length-1 downto 0);
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.en <= (others => '0');
      r.rx <= (others => '0');
    end if;
  end process;

  transition: process(r, ws_i, sck_i, sd_i) is
  begin
    rin <= r;

    rin.sck <= sck_i;
    if r.sck = '0' and sck_i = '1' then
      for i in r.en'range
      loop
        if r.en(i) = '1' then
          rin.rx(i) <= sd_i;
        end if;
      end loop;

      rin.en <= "0" & r.en(r.en'left downto 1);

      rin.ws <= ws_i;
      if r.ws /= ws_i then
        rin.en <= (others => '0');
        rin.en(rin.en'left) <= '1';
      end if;
    end if;
  end process;

  valid_o <= r.en(r.en'left);
  channel_o <= not r.ws;
  data_o <= r.rx;
  
end architecture;

