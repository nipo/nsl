library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_mii;

entity mii_from_framed is
  generic(
    inter_frame : natural := 56
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    mii_o : out nsl_mii.mii.mii_datapath;

    framed_i : in nsl_bnoc.framed.framed_req;
    framed_o : out nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of mii_from_framed is

  type state_t is (
    STATE_IDLE,
    STATE_FW0,
    STATE_FW1,
    STATE_IFS
    );
  
  type regs_t is record
    wait_ctr: natural range 0 to inter_frame;
    state: state_t;
    data: std_ulogic_vector(7 downto 0);
    underflow: std_ulogic;
    done: std_ulogic;
  end record;
  
  signal r, rin : regs_t;
  
begin

  regs: process (reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= STATE_IDLE;
    end if;
  end process;

  transition: process(r, framed_i)
  begin
    rin <= r;

    case r.state is
      when STATE_IDLE =>
        if framed_i.valid = '1' then
          rin.state <= STATE_FW0;
          rin.data <= framed_i.data;
          rin.underflow <= '0';
          rin.done <= '0';
        end if;

      when STATE_FW0 =>
        rin.state <= STATE_FW1;

      when STATE_FW1 =>
        if r.done = '1' then
          rin.state <= STATE_IFS;
          rin.wait_ctr <= inter_frame;
        else
          rin.state <= STATE_FW0;
          rin.done <= framed_i.last;
          if framed_i.valid = '1' then
            rin.data <= framed_i.data;
          else
            rin.data <= (others => 'X');
            rin.underflow <= '1';
          end if;
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
          mii_o.dv <= '0';
          mii_o.er <= '0';
          mii_o.d <= (others => 'X');
          framed_o.ready <= '1';

        when STATE_FW0 =>
          mii_o.dv <= '1';
          mii_o.er <= r.underflow;
          mii_o.d <= r.data(3 downto 0);
          framed_o.ready <= '0';

        when STATE_FW1 =>
          mii_o.dv <= '1';
          mii_o.er <= r.underflow;
          mii_o.d <= r.data(7 downto 4);
          framed_o.ready <= not r.done;

        when STATE_IFS =>
          mii_o.dv <= '0';
          mii_o.er <= '0';
          mii_o.d <= (others => 'X');
          framed_o.ready <= '0';
      end case;
    end if;
  end process;

end architecture;
