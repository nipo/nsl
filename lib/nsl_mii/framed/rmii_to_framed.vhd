library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_mii;

entity rmii_to_framed is
  port(
    clock_i        : in std_ulogic;
    reset_n_i     : in std_ulogic;

    rmii_i  : in nsl_mii.mii.rmii_datapath;

    framed_o : out nsl_bnoc.framed.framed_req
    );
end entity;

architecture rtl of rmii_to_framed is

  type state_t is (
    STATE_IDLE,
    STATE_FILL,
    STATE_FW,
    STATE_FLUSH,
    STATE_LAST
    );
  
  type regs_t is record
    state: state_t;
    dibit_count: unsigned(1 downto 0);
    shifter: std_ulogic_vector(5 downto 0);
    data: std_ulogic_vector(7 downto 0);
    crs: std_ulogic;
    dv: std_ulogic;
  end record;
  
  signal r, rin : regs_t;

begin

  regs: process (reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      r.state <= STATE_IDLE;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, rmii_i)
  begin
    rin <= r;

    case r.state is
      when STATE_IDLE =>
        rin.dibit_count <= "00";

        if rmii_i.dv = '1' then
          case rmii_i.d is
            when "11" =>
              rin.state <= STATE_FILL;
            when "10" =>
              rin.state <= STATE_FLUSH;
            when others =>
              rin.state <= STATE_IDLE;
          end case;
        end if;

      when STATE_FILL | STATE_FW =>
        rin.shifter <= rmii_i.d & r.shifter(5 downto 2);
        rin.dibit_count <= r.dibit_count + 1;

        if r.dibit_count = "11" then
          rin.state <= STATE_FW;
          rin.data <= rmii_i.d & r.shifter(5 downto 0);
        end if;

        if r.dibit_count(0) = '1' and rmii_i.dv = '0' then
          rin.state <= STATE_LAST;
        end if;
        
      when STATE_LAST =>
        rin.state <= STATE_IDLE;

      when STATE_FLUSH =>
        rin.dibit_count <= r.dibit_count + 1;

        if rmii_i.dv = '0' and r.dibit_count(0) = '1' then
          rin.state <= STATE_LAST;
        end if;
    end case;
  end process;
    
  moore: process(r, clock_i)
  begin
    case r.state is
      when STATE_IDLE | STATE_FILL =>
        framed_o.valid <= '0';
        framed_o.last <= '-';

      when STATE_FW | STATE_FLUSH =>
        if r.dibit_count = "11" then
          framed_o.valid <= '1';
        else
          framed_o.valid <= '0';
        end if;
        framed_o.last <= '0';

      when STATE_LAST =>
        framed_o.valid <= '1';
        framed_o.last <= '1';
    end case;
  end process;

  framed_o.data <= r.data;

end architecture;
