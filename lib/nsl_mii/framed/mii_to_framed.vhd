library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_mii;

entity mii_to_framed is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    mii_i : in nsl_mii.mii.mii_datapath;

    framed_o : out nsl_bnoc.framed.framed_req
    );
end entity;

architecture rtl of mii_to_framed is

  type state_t is (
    STATE_FILL0,
    STATE_FILL1,
    STATE_FILL2,
    STATE_FW0,
    STATE_FW1,
    STATE_LAST
    );
  
  type regs_t is record
    state: state_t;
    data_in: std_ulogic_vector(7 downto 0);
    data_out: std_ulogic_vector(7 downto 0);
  end record;
  
  signal r, rin : regs_t;

begin

  regs: process (reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      r.state <= STATE_FILL0;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, mii_i)
  begin
    rin <= r;

    case r.state is
      when STATE_FILL0 =>
        if mii_i.dv = '1' then
          rin.state <= STATE_FILL1;
          rin.data_in(3 downto 0) <= mii_i.d;
        end if;

      when STATE_FILL1 =>
        rin.data_in(7 downto 4) <= mii_i.d;
        rin.state <= STATE_FILL2;

      when STATE_FW0 | STATE_FILL2 =>
        if mii_i.dv = '1' then
          rin.state <= STATE_FW1;
        else
          rin.state <= STATE_LAST;
        end if;
        rin.data_out <= r.data_in;
        rin.data_in(3 downto 0) <= mii_i.d;

      when STATE_FW1 =>
        rin.data_in(7 downto 4) <= mii_i.d;
        rin.state <= STATE_FW0;

      when STATE_LAST =>
        rin.state <= STATE_FILL0;
    end case;
  end process;
    
  moore: process(r, clock_i)
  begin
    case r.state is
      when STATE_FILL0 | STATE_FILL1 | STATE_FILL2 =>
        framed_o.valid <= '0';
        framed_o.last <= '1';

      when STATE_FW0 =>
        framed_o.valid <= '1';
        framed_o.last <= '0';

      when STATE_FW1 =>
        framed_o.valid <= '0';
        framed_o.last <= '0';

      when STATE_LAST =>
        framed_o.valid <= '1';
        framed_o.last <= '1';
    end case;
  end process;

  framed_o.data <= r.data_out;

end architecture;
