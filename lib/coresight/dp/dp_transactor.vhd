library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl, coresight, signalling;
library coresight;
use coresight.dp.all;

entity dp_transactor is
  port (
    p_clk      : in  std_ulogic;
    p_resetn   : in  std_ulogic;

    p_cmd_val  : in  std_ulogic;
    p_cmd_ack  : out std_ulogic;
    p_cmd_data : in  dp_cmd_data;

    p_rsp_val  : out std_ulogic;
    p_rsp_ack  : in  std_ulogic;
    p_rsp_data : out dp_rsp_data;

    p_swd_c     : out signalling.swd.swd_master_c;
    p_swd_s     : in  signalling.swd.swd_master_s
  );
end entity;

architecture rtl of dp_transactor is

  type st_t is (
    ST_RESET,

    ST_CMD_GET,
    ST_CMD_ROUTE,

    ST_CMD_SHIFT,
    ST_CMD_TURNAROUND,

    ST_ACK_SHIFT,

    ST_ACK_TURNAROUND,
    ST_DATA_SHIFT_OUT,
    ST_PARITY_SHIFT_OUT,

    ST_DATA_SHIFT_IN,
    ST_PARITY_SHIFT_IN,
    ST_DATA_TURNAROUND,

    ST_RUN,

    ST_BITBANG,

    ST_RSP_PUT
  );

  type regs_t is record
    state         : st_t;
    ack           : std_ulogic_vector(2 downto 0);

    turnaround    : natural range 0 to 3;
    cycle_count   : natural range 0 to 63;

    divisor       : unsigned(15 downto 0);
    counter       : unsigned(15 downto 0);

    data          : std_ulogic_vector(31 downto 0);
    op            : std_ulogic_vector(7 downto 0);
    run_val       : std_ulogic;
    is_read       : boolean;

    par_in        : std_ulogic;
    par_out       : std_ulogic;

    cmd           : std_ulogic_vector(7 downto 0);

    swd           : signalling.swd.swd_master_c;
  end record;

  signal r, rin: regs_t;

  constant c_zero : unsigned(5 downto 0) := (others => '0');
  
begin
  reg: process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= ST_RESET;
      r.swd.clk <= '0';
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process (r, p_cmd_val, p_cmd_data, p_rsp_ack, p_swd_s)
    variable swclk_falling : boolean;
    variable swclk_rising : boolean;
  begin
    rin <= r;
    swclk_falling := false;
    swclk_rising := false;

    rin.counter <= r.counter - 1;

    if r.counter = (r.counter'range => '0') then
      rin.counter <= r.divisor;
      rin.swd.clk <= not r.swd.clk;
      swclk_falling := r.swd.clk = '1';
      swclk_rising := r.swd.clk = '0';
    end if;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_CMD_GET;
        rin.swd.clk <= '0';
        rin.swd.dio.v <= '0';
        rin.turnaround <= 0;
        rin.divisor <= (others => '1');
        rin.counter <= (others => '0');

      when ST_CMD_GET =>
        if p_cmd_val = '1' then
          rin.state <= ST_CMD_ROUTE;
          rin.op <= p_cmd_data.op;
          rin.data <= p_cmd_data.data;
        end if;

      when ST_CMD_ROUTE =>
        if swclk_rising then
          if std_match(r.op, DP_CMD_TURNAROUND) then
            rin.turnaround <= to_integer(unsigned(r.op(1 downto 0)));
            rin.state <= ST_RSP_PUT;

          elsif std_match(r.op, DP_CMD_RUN) then
            rin.cycle_count <= to_integer(unsigned(r.op(5 downto 0)));
            rin.state <= ST_RUN;
            rin.run_val <= r.op(6);

          elsif std_match(r.op, DP_CMD_DIVISOR) then
            rin.divisor <= unsigned(r.data(31 downto 16));
            rin.state <= ST_RSP_PUT;

          elsif std_match(r.op, DP_CMD_BITBANG) then
            rin.cycle_count <= to_integer(unsigned(r.op(4 downto 0)));
            rin.state <= ST_BITBANG;

          elsif std_match(r.op, DP_CMD_ABORT) then
            rin.cmd <= x"81"; -- Write to DP 0
            rin.par_in <= '0';
            rin.par_out <= '0';
            rin.cycle_count <= 7;
            rin.state <= ST_CMD_SHIFT;
            rin.data <= x"0000001f";
            rin.is_read <= false;
            rin.run_val <= '0';

          elsif std_match(r.op, DP_CMD_RW) then
            rin.cmd(7 downto 6) <= "10";
            rin.cmd(5) <= r.op(0) xor r.op(1) xor r.op(4) xor r.op(5);
            rin.cmd(4 downto 3) <= std_ulogic_vector(r.op(1 downto 0));
            rin.cmd(2) <= r.op(4); -- Rnw
            rin.cmd(1) <= r.op(5); -- Apndp
            rin.cmd(0) <= '1';
            rin.is_read <= r.op(4) = '1'; -- Rnw
            rin.par_in <= '0';
            rin.par_out <= '0';
            rin.cycle_count <= 7;
            rin.state <= ST_CMD_SHIFT;
            rin.run_val <= '0';

          else
            rin.cmd <= x"ff";
            rin.state <= ST_RSP_PUT;
          end if;
        end if;

      when ST_CMD_SHIFT =>
        if swclk_falling then
          rin.swd.dio.v <= r.cmd(0);
          rin.swd.dio.en <= '1';
        elsif swclk_rising then
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
            rin.cmd <= "-" & r.cmd(7 downto 1);
          else
            rin.state <= ST_CMD_TURNAROUND;
            rin.cycle_count <= r.turnaround;
          end if;
        end if;

      when ST_CMD_TURNAROUND =>
        if swclk_falling then
          rin.swd.dio.en <= '0';
          rin.swd.dio.v <= '-';
        elsif swclk_rising then
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.state <= ST_ACK_SHIFT;
            rin.cycle_count <= 2;
          end if;
        end if;

      when ST_ACK_SHIFT =>
        if swclk_falling then
          rin.swd.dio.en <= '0';
          rin.swd.dio.v <= '-';
        elsif swclk_rising then
          rin.ack <= to_x01(p_swd_s.dio.v) & r.ack(2 downto 1);
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            if r.is_read then
              rin.state <= ST_DATA_SHIFT_IN;
              rin.cycle_count <= 31;
            else
              rin.state <= ST_ACK_TURNAROUND;
              rin.cycle_count <= r.turnaround;
            end if;
          end if;
        end if;

      when ST_ACK_TURNAROUND =>
        if swclk_falling then
          rin.swd.dio.en <= '0';
          rin.swd.dio.v <= '-';
        elsif swclk_rising then
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.state <= ST_DATA_SHIFT_OUT;
            rin.cycle_count <= 31;
          end if;
        end if;

      when ST_DATA_SHIFT_OUT =>
        if swclk_falling then
          rin.swd.dio.en <= '1';
          rin.swd.dio.v <= r.data(0);
          rin.par_out <= r.par_out xor r.data(0);
        elsif swclk_rising then
          rin.data <= '-' & r.data(31 downto 1);
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.state <= ST_PARITY_SHIFT_OUT;
          end if;
        end if;

      when ST_PARITY_SHIFT_OUT =>
        if swclk_falling then
          rin.swd.dio.en <= '1';
          rin.swd.dio.v <= r.par_out;
        elsif swclk_rising then
          rin.state <= ST_RUN;
          rin.cycle_count <= 1;
        end if;

      when ST_DATA_SHIFT_IN =>
        if swclk_falling then
          rin.swd.dio.en <= '0';
          rin.swd.dio.v <= '-';
        elsif swclk_rising then
          rin.data <= to_x01(p_swd_s.dio.v) & r.data(31 downto 1);
          rin.par_in <= r.par_in xor to_x01(p_swd_s.dio.v);
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.state <= ST_PARITY_SHIFT_IN;
          end if;
        end if;

      when ST_PARITY_SHIFT_IN =>
        if swclk_falling then
          rin.swd.dio.en <= '0';
          rin.swd.dio.v <= '-';
        elsif swclk_rising then
          rin.par_in <= r.par_in xor to_x01(p_swd_s.dio.v);
          rin.state <= ST_DATA_TURNAROUND;
          rin.cycle_count <= r.turnaround;
        end if;

      when ST_DATA_TURNAROUND =>
        if swclk_falling then
          rin.swd.dio.en <= '0';
          rin.swd.dio.v <= '-';
        elsif swclk_rising then
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.state <= ST_RUN;
            rin.cycle_count <= 1;
          end if;
        end if;

      when ST_RUN =>
        if swclk_falling then
          rin.swd.dio.en <= '1';
          rin.swd.dio.v <= r.run_val;
        elsif swclk_rising then
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.state <= ST_RSP_PUT;
          end if;
        end if;

      when ST_BITBANG =>
        if swclk_falling then
          rin.swd.dio.en <= '1';
          rin.swd.dio.v <= r.data(0);
          rin.run_val <= r.data(0);
        elsif swclk_rising then
          rin.data <= '-' & r.data(31 downto 1);
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.state <= ST_RSP_PUT;
          end if;
        end if;

      when ST_RSP_PUT =>
        if swclk_falling then
          rin.swd.dio.en <= '1';
          rin.swd.dio.v <= r.run_val;
        end if;

        if p_rsp_ack = '1' then
          rin.state <= ST_CMD_GET;
        end if;
    end case;
  end process;

  p_swd_c <= r.swd;
  p_cmd_ack <= '1' when r.state = ST_CMD_GET else '0';
  p_rsp_val <= '1' when r.state = ST_RSP_PUT else '0';
  p_rsp_data.data <= r.data;
  p_rsp_data.ack <= r.ack;
  p_rsp_data.par_ok <= r.par_in;

end architecture;
