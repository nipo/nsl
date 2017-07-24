library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.framed.all;

library coresight;
use coresight.dp.all;

entity dp_transactor is
  port (
    p_clk      : in  std_ulogic;
    p_resetn   : in  std_ulogic;

    p_clk_div  : in  unsigned(15 downto 0);

    p_cmd_val  : in  std_ulogic;
    p_cmd_ack  : out std_ulogic;
    p_cmd_data : in  dp_cmd_data;

    p_rsp_val  : out std_ulogic;
    p_rsp_ack  : in  std_ulogic;
    p_rsp_data : out dp_rsp_data;

    p_swclk    : out std_ulogic;
    p_swdio_i  : in  std_ulogic;
    p_swdio_o  : out std_ulogic;
    p_swdio_oe : out std_ulogic
  );
end entity;

architecture rtl of dp_transactor is

  type state_t is (
    STATE_RESET,

    STATE_CMD_GET,
    STATE_CMD_ROUTE,

    STATE_CMD_SHIFT,
    STATE_CMD_TURNAROUND,

    STATE_ACK_SHIFT,
    STATE_ACK_TURNAROUND,

    STATE_DATA_SHIFT,
    STATE_PARITY_SHIFT,
    STATE_DATA_TURNAROUND,

    STATE_RUN,

    STATE_BITBANG,

    STATE_RSP_PUT
  );

  type regs_t is record
    state         : state_t;
    ack           : std_ulogic_vector(2 downto 0);
    turnaround    : integer range 0 to 3;
    scaler        : unsigned(p_clk_div'range);

    data          : std_ulogic_vector(31 downto 0);
    op            : std_ulogic_vector(7 downto 0);
    run_val       : std_ulogic;

    par_in        : std_ulogic;
    par_out       : std_ulogic;

    cmd           : std_ulogic_vector(7 downto 0);

    cycle_count   : natural range 0 to 63;

    swclk         : std_ulogic;
    swdio         : std_ulogic;
    swdio_oe      : std_ulogic;
  end record;

  signal r, rin: regs_t;

begin
  reg: process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= STATE_RESET;
      r.turnaround <= 0;
      r.scaler <= (others => '0');
      r.swclk <= '0';
      r.swdio <= '0';
      r.swdio_oe <= '1';
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process (r, p_cmd_val, p_cmd_data, p_rsp_ack, p_swdio_i, p_clk_div)
    variable swclk_falling : boolean;
    variable swclk_rising : boolean;
  begin
    rin <= r;
    swclk_falling := false;
    swclk_rising := false;

    rin.scaler <= r.scaler - 1;
    if r.scaler = (r.scaler'range => '0') then
      rin.scaler <= p_clk_div;
      rin.swclk <= not r.swclk;
      swclk_falling := r.swclk = '1';
      swclk_rising := r.swclk = '0';
    end if;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_CMD_GET;
        rin.scaler <= p_clk_div;

      when STATE_CMD_GET =>
        if p_cmd_val = '1' then
          rin.state <= STATE_CMD_ROUTE;
          rin.op <= p_cmd_data.op;
          rin.data <= p_cmd_data.data;
        end if;

      when STATE_CMD_ROUTE =>
        if swclk_rising then
          if std_match(r.op, DP_CMD_TURNAROUND) then
            rin.turnaround <= to_integer(unsigned(r.op(1 downto 0)));
            rin.state <= STATE_RSP_PUT;

          elsif std_match(r.op, DP_CMD_RUN) then
            rin.cycle_count <= to_integer(unsigned(r.op(5 downto 0)));
            rin.state <= STATE_RUN;
            rin.run_val <= r.op(6);

          elsif std_match(r.op, DP_CMD_BITBANG) then
            rin.cycle_count <= to_integer(unsigned(r.op(4 downto 0)));
            rin.state <= STATE_BITBANG;

          elsif std_match(r.op, DP_CMD_AP_ABORT) then
            rin.cmd <= x"81"; -- Write to DP 0
            rin.par_in <= '0';
            rin.par_out <= '0';
            rin.cycle_count <= 7;
            rin.state <= STATE_CMD_SHIFT;
            rin.data <= x"0000001f";

          elsif std_match(r.op, DP_CMD_RW) then
            rin.cmd(7 downto 6) <= "10";
            rin.cmd(5) <= r.op(0) xor r.op(1) xor r.op(4) xor r.op(5);
            rin.cmd(4 downto 3) <= std_ulogic_vector(r.op(1 downto 0));
            rin.cmd(2) <= r.op(4); -- Rnw
            rin.cmd(1) <= r.op(5); -- Apndp
            rin.cmd(0) <= '1';
            rin.par_in <= '0';
            rin.par_out <= '0';
            rin.cycle_count <= 7;
            rin.state <= STATE_CMD_SHIFT;

          else
            rin.state <= STATE_RSP_PUT;
          end if;
        end if;

      when STATE_CMD_SHIFT =>
        if swclk_falling then
          rin.swdio <= r.cmd(0);
          rin.swdio_oe <= '1';
        elsif swclk_rising then
          rin.cycle_count <= (r.cycle_count - 1) mod 64;
          rin.cmd <= "-" & r.cmd(7 downto 1);
          if r.cycle_count = 0 then
            rin.state <= STATE_CMD_TURNAROUND;
            rin.cycle_count <= r.turnaround;
          end if;
        end if;

      when STATE_CMD_TURNAROUND =>
        if swclk_falling then
          rin.swdio_oe <= '0';
        elsif swclk_rising then
          rin.cycle_count <= (r.cycle_count - 1) mod 64;
          if r.cycle_count = 0 then
            rin.state <= STATE_ACK_SHIFT;
            rin.cycle_count <= 2;
          end if;
        end if;

      when STATE_ACK_SHIFT =>
        if swclk_falling then
          rin.swdio_oe <= '0';
        elsif swclk_rising then
          rin.cycle_count <= (r.cycle_count - 1) mod 64;
          rin.ack <= p_swdio_i & r.ack(2 downto 1);
          if r.cycle_count = 0 then
            if r.op(4) = '1' then -- read
              rin.state <= STATE_DATA_SHIFT;
              rin.cycle_count <= 31;
            else
              rin.state <= STATE_ACK_TURNAROUND;
              rin.cycle_count <= r.turnaround;
            end if;
          end if;
        end if;

      when STATE_ACK_TURNAROUND =>
        if swclk_falling then
          rin.swdio_oe <= '0';
        elsif swclk_rising then
          rin.cycle_count <= (r.cycle_count - 1) mod 64;
          if r.cycle_count = 0 then
            rin.state <= STATE_DATA_SHIFT;
            rin.cycle_count <= 31;
          end if;
        end if;

      when STATE_DATA_SHIFT =>
        if swclk_falling then
          rin.swdio <= r.data(0);
          rin.swdio_oe <= not r.op(4); -- write
          rin.par_out <= r.par_out xor r.data(0);
        elsif swclk_rising then
          rin.cycle_count <= (r.cycle_count - 1) mod 64;
          rin.data <= p_swdio_i & r.data(31 downto 1);
          rin.par_in <= r.par_in xor p_swdio_i;
          if r.cycle_count = 0 then
            rin.state <= STATE_PARITY_SHIFT;
          end if;
        end if;

      when STATE_PARITY_SHIFT =>
        if swclk_falling then
          rin.swdio <= r.par_out;
          rin.swdio_oe <= not r.op(4); -- write
        elsif swclk_rising then
          rin.par_in <= r.par_in xor p_swdio_i;

          if r.op(4) = '1' then -- read
            rin.state <= STATE_DATA_TURNAROUND;
            rin.cycle_count <= r.turnaround;
          else
            rin.state <= STATE_RUN;
            rin.cycle_count <= 0;
            rin.run_val <= '0';
          end if;
        end if;

      when STATE_DATA_TURNAROUND =>
        if swclk_falling then
          rin.swdio_oe <= '0';
        elsif swclk_rising then
          rin.cycle_count <= (r.cycle_count - 1) mod 64;
          if r.cycle_count = 0 then
            rin.state <= STATE_RUN;
            rin.cycle_count <= 0;
            rin.run_val <= '0';
          end if;
        end if;

      when STATE_RUN =>
        if swclk_falling then
          rin.swdio_oe <= '1';
          rin.swdio <= r.run_val;
        elsif swclk_rising then
          rin.cycle_count <= (r.cycle_count - 1) mod 64;
          if r.cycle_count = 0 then
            rin.state <= STATE_RSP_PUT;
          end if;
        end if;

      when STATE_BITBANG =>
        if swclk_falling then
          rin.swdio_oe <= '1';
          rin.swdio <= r.data(0);
        elsif swclk_rising then
          rin.data <= '-' & r.data(31 downto 1);
          rin.cycle_count <= (r.cycle_count - 1) mod 64;
          if r.cycle_count = 0 then
            rin.state <= STATE_RSP_PUT;
          end if;
        end if;

      when STATE_RSP_PUT =>
        if swclk_falling then
          rin.swdio_oe <= '1';
          rin.swdio <= r.run_val;
        end if;

        if p_rsp_ack = '1' then
          rin.state <= STATE_CMD_GET;
        end if;
    end case;
  end process;

  p_swclk <= r.swclk;
  p_swdio_o <= r.swdio;
  p_swdio_oe <= r.swdio_oe;

  p_cmd_ack <= '1' when r.state = STATE_CMD_GET else '0';
  p_rsp_val <= '1' when r.state = STATE_RSP_PUT else '0';
  p_rsp_data.data <= r.data;
  p_rsp_data.ack <= r.ack;
  p_rsp_data.par_ok <= r.par_in;

end architecture;
