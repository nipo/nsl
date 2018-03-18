library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.ti.all;

entity ti_cc_master is
  generic(
    divisor_width : natural
    );
  port(
    p_resetn    : in  std_ulogic;
    p_clk       : in  std_ulogic;

    p_divisor  : in std_ulogic_vector(divisor_width-1 downto 0);

    p_cc_resetn : out std_ulogic;
    p_cc_dc     : out std_ulogic;
    p_cc_ddo    : out std_ulogic;
    p_cc_ddi    : in  std_ulogic;
    p_cc_ddoe   : out std_ulogic;

    p_ready    : out std_ulogic;
    p_rdata    : out std_ulogic_vector(7 downto 0);
    p_wdata    : in  std_ulogic_vector(7 downto 0);

    p_cmd      : in  cc_cmd_t;
    p_busy     : out std_ulogic;
    p_done     : out std_ulogic
    );
end entity;

architecture rtl of ti_cc_master is
  
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

  ck : process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition : process (r, p_wdata, p_cmd, p_cc_ddi, p_divisor)
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
        if p_cmd = CC_RESET_RELEASE then
          step := true;
          rin.bit_count <= 0;
          rin.state <= ST_RESET_DC_L;

        elsif p_cmd = CC_RESET_ACQUIRE then
          step := true;
          rin.bit_count <= 2;
          rin.state <= ST_RESET_DC_L;

        elsif p_cmd = CC_WRITE then
          step := true;
          rin.bit_count <= 7;
          rin.shreg <= p_wdata;
          rin.state <= ST_WRITE_DC_H;

        elsif p_cmd = CC_WAIT then
          step := true;
          rin.bit_count <= to_integer(unsigned(p_wdata(5 downto 0)));
          rin.state <= ST_WAIT;
          
        elsif p_cmd = CC_READ then
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
        if p_cmd = CC_NOOP then
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
          rin.shreg <= r.shreg(6 downto 0) & p_cc_ddi;
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
            rin.was_ready <= not p_cc_ddi;
          else
            rin.bit_count <= r.bit_count - 1;
          end if;
        end if;

    end case;

    if step then
      rin.ctr <= to_integer(unsigned(p_divisor));
    end if;
  end process;

  moore : process (r)
  begin
    case r.state is
      when ST_WRITE_DC_L | ST_WRITE_DC_H =>
        p_cc_ddoe <= '1';

      when others =>
        p_cc_ddoe <= '0';
    end case;

    case r.state is
      when ST_RESET_DC_L | ST_RESET_DC_H =>
        p_cc_resetn <= '0';

      when others =>
        p_cc_resetn <= '1';
    end case;

    case r.state is
      when ST_RESET_DC_H | ST_WRITE_DC_H | ST_READ_DC_H =>
        p_cc_dc <= '1';
        
      when others =>
        p_cc_dc <= '0';
    end case;

    p_cc_ddo <= r.shreg(7);
    p_rdata <= r.shreg;
    p_ready <= r.was_ready;

    case r.state is
      when ST_DONE =>
        p_busy <= '1';
        p_done <= '1';

      when ST_IDLE =>
        p_busy <= '0';
        p_done <= '0';

      when others =>
        p_busy <= '1';
        p_done <= '0';
    end case;
  end process;
  
end architecture;
