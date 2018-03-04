library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.mii.all;
use nsl.framed.all;

entity rmii_from_framed is
  generic(
    inter_frame : natural := 56
    );
  port(
    p_clk : in std_ulogic;
    p_resetn : in std_ulogic;

    p_rmii_data : out rmii_datapath;

    p_framed_val : in nsl.framed.framed_req;
    p_framed_ack : out nsl.framed.framed_ack
    );
end entity;

architecture rtl of rmii_from_framed is

  type state_t is (
    STATE_IDLE,
    STATE_SOF,
    STATE_FW,
    STATE_IFS
    );

  type regs_t is record
    wait_ctr: natural range 0 to inter_frame;
    state: state_t;
    dibit_count: unsigned(1 downto 0);
    data: std_ulogic_vector(7 downto 0);
    underflow: std_ulogic;
    last: std_ulogic;
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

  transition: process(r, p_framed_val)
  begin
    rin <= r;

    case r.state is
      when STATE_IDLE =>
        if p_framed_val.valid = '1' then
          rin.state <= STATE_SOF;
          rin.dibit_count <= "00";
          rin.data <= p_framed_val.data;
          rin.underflow <= '0';
          rin.last <= '0';
        end if;

      when STATE_SOF =>
        rin.dibit_count <= r.dibit_count + 1;
        if r.dibit_count = "11" then
          rin.state <= STATE_FW;
        end if;

      when STATE_FW =>
        rin.dibit_count <= r.dibit_count + 1;
        if r.dibit_count = "11" then
          rin.data <= p_framed_val.data;
          rin.last <= p_framed_val.last;

          if r.last = '1' then
            rin.state <= STATE_IFS;
            rin.wait_ctr <= inter_frame;
          end if;
        else
          rin.data <= "XX" & r.data(7 downto 2);
        end if;

      when STATE_IFS =>
        if r.wait_ctr = 0 then
          rin.state <= STATE_IDLE;
        else
          rin.wait_ctr <= r.wait_ctr - 1;
        end if;
    end case;
  end process;

  moore: process(r, p_clk)
  begin
    if falling_edge(p_clk) then
      case r.state is
        when STATE_IDLE =>
          p_rmii_data.dv <= '0';
          p_rmii_data.d <= (others => 'X');
          p_framed_ack.ready <= '1';

        when STATE_SOF =>
          p_rmii_data.dv <= '1';
          if r.dibit_count = "11" then
            p_rmii_data.d <= "11";
          else
            p_rmii_data.d <= "01";
          end if;
          p_framed_ack.ready <= '0';

        when STATE_FW =>
          p_rmii_data.dv <= '1';
          p_rmii_data.d <= r.data(1 downto 0);
          if r.dibit_count = "11" then
            p_framed_ack.ready <= not r.last;
          else
            p_framed_ack.ready <= '0';
          end if;

        when STATE_IFS =>
          p_rmii_data.dv <= '0';
          p_rmii_data.d <= (others => 'X');
          p_framed_ack.ready <= '0';
      end case;
    end if;
  end process;

end architecture;
