library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.mii.all;
use nsl.framed.all;

entity rmii_to_framed is
  port(
    p_clk        : in std_ulogic;
    p_resetn     : in std_ulogic;

    p_rmii_data  : in rmii_datapath;

    p_framed_val : out nsl.framed.framed_req;
    p_framed_ack : in nsl.framed.framed_ack
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

  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= STATE_IDLE;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_rmii_data, p_framed_ack)
  begin
    rin <= r;

    case r.state is
      when STATE_IDLE =>
        rin.dibit_count <= "00";

        if p_rmii_data.dv = '1' then
          case p_rmii_data.d is
            when "11" =>
              rin.state <= STATE_FILL;
            when "10" =>
              rin.state <= STATE_FLUSH;
            when others =>
              rin.state <= STATE_IDLE;
          end case;
        end if;

      when STATE_FILL | STATE_FW =>
        rin.shifter <= p_rmii_data.d & r.shifter(5 downto 2);
        rin.dibit_count <= r.dibit_count + 1;

        if r.dibit_count = "11" then
          rin.state <= STATE_FW;
          rin.data <= p_rmii_data.d & r.shifter(5 downto 0);
        end if;

        if r.dibit_count(0) = '1' and p_rmii_data.dv = '0' then
          rin.state <= STATE_LAST;
        end if;
        
      when STATE_LAST =>
        rin.state <= STATE_IDLE;

      when STATE_FLUSH =>
        rin.dibit_count <= r.dibit_count + 1;

        if p_rmii_data.dv = '0' and r.dibit_count(0) = '1' then
          rin.state <= STATE_LAST;
        end if;
    end case;
  end process;
    
  moore: process(r, p_clk)
  begin
    case r.state is
      when STATE_IDLE | STATE_FILL =>
        p_framed_val.val <= '0';
        p_framed_val.more <= '0';

      when STATE_FW | STATE_FLUSH =>
        if r.dibit_count = "11" then
          p_framed_val.val <= '1';
        else
          p_framed_val.val <= '0';
        end if;
        p_framed_val.more <= '1';

      when STATE_LAST =>
        p_framed_val.val <= '1';
        p_framed_val.more <= '0';
    end case;
  end process;

  p_framed_val.data <= r.data;

end architecture;
