library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_ti;
use nsl_ti.cc.all;

entity cc_master is
  generic(
    divisor_width : natural
    );
  port(
    reset_n_i    : in  std_ulogic;
    clock_i       : in  std_ulogic;

    divisor_i  : in std_ulogic_vector(divisor_width-1 downto 0);

    cc_o : out cc_m_o;
    cc_i : in cc_m_i;

    ready_o    : out std_ulogic;
    rdata_o    : out std_ulogic_vector(7 downto 0);
    wdata_i    : in  std_ulogic_vector(7 downto 0);

    cmd_i      : in  cc_cmd_t;
    busy_o     : out std_ulogic;
    done_o     : out std_ulogic
    );
end entity;

architecture rtl of cc_master is
  
  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_DONE_WAIT,
    ST_DONE,
    ST_WAIT,
    ST_RESET_DC_H,
    ST_RESET_DC_L,
    ST_WRITE_DC_L,
    ST_WRITE_DC_H,
    ST_READ_START,
    ST_READ_DC_L,
    ST_READ_DC_H
    );
  
  type regs_t is record
    state                : state_t;
    bit_count            : natural range 0 to 63;
    shreg                : std_ulogic_vector(7 downto 0);
    was_ready            : std_ulogic;
    ctr                  : natural range 0 to 2 ** divisor_width - 1;
  end record;

  signal r, rin : regs_t;

begin

  ck : process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition : process (r, wdata_i, cmd_i, cc_i.dd, divisor_i)
    variable ready, step : boolean;
  begin
    rin <= r;

    step := false;
    if r.ctr /= 0 then
      rin.ctr <= r.ctr - 1;
      ready := false;
    else
      ready := true;
    end if;

    case r.state is
      when ST_RESET =>
        step := true;
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if cmd_i = CC_RESET_RELEASE then
          step := true;
          rin.bit_count <= 0;
          rin.state <= ST_RESET_DC_L;

        elsif cmd_i = CC_RESET_ACQUIRE then
          step := true;
          rin.bit_count <= 2;
          rin.state <= ST_RESET_DC_L;

        elsif cmd_i = CC_WRITE then
          step := true;
          rin.bit_count <= 7;
          rin.shreg <= wdata_i;
          rin.state <= ST_WRITE_DC_H;

        elsif cmd_i = CC_WAIT then
          step := true;
          rin.bit_count <= to_integer(unsigned(wdata_i(5 downto 0)));
          rin.state <= ST_WAIT;
          
        elsif cmd_i = CC_READ then
          step := true;
          rin.state <= ST_READ_START;
          rin.bit_count <= 5;
          
        end if;
        
      when ST_WAIT =>
        if ready then
          step := true;
          if r.bit_count = 0 then
            rin.state <= ST_DONE_WAIT;
          else
            rin.bit_count <= r.bit_count - 1;
          end if;
        end if;
        
      when ST_DONE_WAIT =>
        if ready then
          rin.state <= ST_DONE;
        end if;

      when ST_DONE =>
        if cmd_i = CC_NOOP then
          rin.state <= ST_IDLE;
        end if;
        
      when ST_RESET_DC_H =>
        if ready then
          step := true;
          rin.state <= ST_RESET_DC_L;
        end if;
        
      when ST_RESET_DC_L =>
        if ready then
          step := true;
          if r.bit_count = 0 then
            rin.state <= ST_DONE_WAIT;
          else
            rin.bit_count <= r.bit_count - 1;
            rin.state <= ST_RESET_DC_H;
          end if;
        end if;
        
      when ST_WRITE_DC_H =>
        if ready then
          step := true;
          rin.state <= ST_WRITE_DC_L;
        end if;
        
      when ST_WRITE_DC_L =>
        if ready then
          step := true;
          rin.shreg <= r.shreg(6 downto 0) & '-';
          if r.bit_count = 0 then
            rin.state <= ST_DONE_WAIT;
          else
            rin.bit_count <= r.bit_count - 1;
            rin.state <= ST_WRITE_DC_H;
          end if;
        end if;
        
      when ST_READ_DC_H =>
        if ready then
          step := true;
          rin.state <= ST_READ_DC_L;
          rin.shreg <= r.shreg(6 downto 0) & cc_i.dd;
        end if;
        
      when ST_READ_DC_L =>
        if ready then
          step := true;
          if r.bit_count /= 0 then
            rin.bit_count <= r.bit_count - 1;
            rin.state <= ST_READ_DC_H;
          else
            rin.state <= ST_DONE_WAIT;
          end if;
        end if;
        
      when ST_READ_START =>
        if ready then
          step := true;
          if r.bit_count = 0 then
            rin.bit_count <= 7;
            rin.state <= ST_READ_DC_H;
            rin.was_ready <= not cc_i.dd;
          else
            rin.bit_count <= r.bit_count - 1;
          end if;
        end if;

    end case;

    if step then
      rin.ctr <= to_integer(unsigned(divisor_i));
    end if;
  end process;

  moore : process (r)
  begin
    case r.state is
      when ST_WRITE_DC_L | ST_WRITE_DC_H =>
        cc_o.dd.output <= '1';

      when others =>
        cc_o.dd.output <= '0';
    end case;

    case r.state is
      when ST_RESET_DC_L | ST_RESET_DC_H =>
        cc_o.reset_n <= '0';

      when others =>
        cc_o.reset_n <= '1';
    end case;

    case r.state is
      when ST_RESET_DC_H | ST_WRITE_DC_H | ST_READ_DC_H =>
        cc_o.dc <= '1';
        
      when others =>
        cc_o.dc <= '0';
    end case;

    cc_o.dd.v <= r.shreg(7);
    rdata_o <= r.shreg;
    ready_o <= r.was_ready;

    case r.state is
      when ST_DONE =>
        busy_o <= '1';
        done_o <= '1';

      when ST_IDLE =>
        busy_o <= '0';
        done_o <= '0';

      when others =>
        busy_o <= '1';
        done_o <= '0';
    end case;
  end process;
  
end architecture;
