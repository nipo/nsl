library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_mii;

entity rmii_from_framed is
  generic(
    inter_frame : natural := 56
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    rmii_o : out nsl_mii.mii.rmii_datapath;

    framed_i : in nsl_bnoc.framed.framed_req;
    framed_o : out nsl_bnoc.framed.framed_ack
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

  regs: process (reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      r.state <= STATE_IDLE;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, framed_i)
  begin
    rin <= r;

    case r.state is
      when STATE_IDLE =>
        if framed_i.valid = '1' then
          rin.state <= STATE_SOF;
          rin.dibit_count <= "00";
          rin.data <= framed_i.data;
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
          rin.data <= framed_i.data;
          rin.last <= framed_i.last;

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

  moore: process(r, clock_i)
  begin
    if falling_edge(clock_i) then
      case r.state is
        when STATE_IDLE =>
          rmii_o.dv <= '0';
          rmii_o.d <= (others => 'X');
          framed_o.ready <= '1';

        when STATE_SOF =>
          rmii_o.dv <= '1';
          if r.dibit_count = "11" then
            rmii_o.d <= "11";
          else
            rmii_o.d <= "01";
          end if;
          framed_o.ready <= '0';

        when STATE_FW =>
          rmii_o.dv <= '1';
          rmii_o.d <= r.data(1 downto 0);
          if r.dibit_count = "11" then
            framed_o.ready <= not r.last;
          else
            framed_o.ready <= '0';
          end if;

        when STATE_IFS =>
          rmii_o.dv <= '0';
          rmii_o.d <= (others => 'X');
          framed_o.ready <= '0';
      end case;
    end if;
  end process;

end architecture;
