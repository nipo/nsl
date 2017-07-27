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

    p_clk_ref  : in  std_ulogic;

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
    STATE_DATA_SHIFT_OUT,
    STATE_PARITY_SHIFT_OUT,

    STATE_DATA_SHIFT_IN,
    STATE_PARITY_SHIFT_IN,
    STATE_DATA_TURNAROUND,

    STATE_RUN,

    STATE_BITBANG,

    STATE_RSP_PUT
  );

  type regs_t is record
    state         : state_t;
    ack           : std_ulogic_vector(2 downto 0);
    turnaround    : unsigned(1 downto 0);

    data          : std_ulogic_vector(31 downto 0);
    op            : std_ulogic_vector(7 downto 0);
    run_val       : std_ulogic;
    is_read       : std_ulogic;

    par_in        : std_ulogic;
    par_out       : std_ulogic;

    cmd           : std_ulogic_vector(7 downto 0);

    cycle_count   : unsigned(5 downto 0);

    swclk         : std_ulogic;
    swdio         : std_ulogic;
    swdio_oe      : std_ulogic;
  end record;

  signal r, rin: regs_t;

  constant c_zero : unsigned(5 downto 0) := (others => '0');
  
begin
  reg: process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= STATE_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process (r, p_cmd_val, p_cmd_data, p_rsp_ack, p_swdio_i, p_clk_ref)
    variable swclk_falling : boolean;
    variable swclk_rising : boolean;
  begin
    rin <= r;
    swclk_falling := false;
    swclk_rising := false;

    rin.swclk <= p_clk_ref;

    if p_clk_ref /= r.swclk then
      swclk_falling := r.swclk = '1';
      swclk_rising := r.swclk = '0';
    end if;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_CMD_GET;
        rin.swclk <= '0';
        rin.swdio <= '0';
        rin.turnaround <= (others => '0');

      when STATE_CMD_GET =>
        if p_cmd_val = '1' then
          rin.state <= STATE_CMD_ROUTE;
          rin.op <= p_cmd_data.op;
          rin.data <= p_cmd_data.data;
        end if;

      when STATE_CMD_ROUTE =>
        if swclk_rising then
          if std_match(r.op, DP_CMD_TURNAROUND) then
            rin.turnaround <= unsigned(r.op(1 downto 0));
            rin.state <= STATE_RSP_PUT;

          elsif std_match(r.op, DP_CMD_RUN) then
            rin.cycle_count <= unsigned(r.op(5 downto 0));
            rin.state <= STATE_RUN;
            rin.run_val <= r.op(6);

          elsif std_match(r.op, DP_CMD_BITBANG) then
            rin.cycle_count <= '0' & unsigned(r.op(4 downto 0));
            rin.state <= STATE_BITBANG;

          elsif std_match(r.op, DP_CMD_ABORT) then
            rin.cmd <= x"81"; -- Write to DP 0
            rin.par_in <= '0';
            rin.par_out <= '0';
            rin.cycle_count <= "000111";
            rin.state <= STATE_CMD_SHIFT;
            rin.data <= x"0000001f";
            rin.is_read <= '0';
            rin.run_val <= '0';

          elsif std_match(r.op, DP_CMD_RW) then
            rin.cmd(7 downto 6) <= "10";
            rin.cmd(5) <= r.op(0) xor r.op(1) xor r.op(4) xor r.op(5);
            rin.cmd(4 downto 3) <= std_ulogic_vector(r.op(1 downto 0));
            rin.cmd(2) <= r.op(4); -- Rnw
            rin.cmd(1) <= r.op(5); -- Apndp
            rin.cmd(0) <= '1';
            rin.is_read <= r.op(4); -- Rnw
            rin.par_in <= '0';
            rin.par_out <= '0';
            rin.cycle_count <= "000111";
            rin.state <= STATE_CMD_SHIFT;
            rin.run_val <= '0';

          else
            rin.cmd <= x"ff";
            rin.state <= STATE_RSP_PUT;
          end if;
        end if;

      when STATE_CMD_SHIFT =>
        if swclk_falling then
          rin.swdio <= r.cmd(0);
          rin.swdio_oe <= '1';
        elsif swclk_rising then
          rin.cycle_count <= r.cycle_count - 1;
          rin.cmd <= "-" & r.cmd(7 downto 1);
          if r.cycle_count = c_zero then
            rin.state <= STATE_CMD_TURNAROUND;
            rin.cycle_count <= "0000" & r.turnaround;
          end if;
        end if;

      when STATE_CMD_TURNAROUND =>
        if swclk_falling then
          rin.swdio_oe <= '0';
          rin.swdio <= '-';
        elsif swclk_rising then
          rin.cycle_count <= r.cycle_count - 1;
          if r.cycle_count = c_zero then
            rin.state <= STATE_ACK_SHIFT;
            rin.cycle_count <= "000010";
          end if;
        end if;

      when STATE_ACK_SHIFT =>
        if swclk_falling then
          rin.swdio_oe <= '0';
          rin.swdio <= '-';
        elsif swclk_rising then
          rin.cycle_count <= r.cycle_count - 1;
          rin.ack <= p_swdio_i & r.ack(2 downto 1);
          if r.cycle_count = c_zero then
            if r.is_read = '1' then -- read
              rin.state <= STATE_DATA_SHIFT_IN;
              rin.cycle_count <= "011111";
            else
              rin.state <= STATE_ACK_TURNAROUND;
              rin.cycle_count <= "0000" & r.turnaround;
            end if;
          end if;
        end if;

      when STATE_ACK_TURNAROUND =>
        if swclk_falling then
          rin.swdio_oe <= '0';
          rin.swdio <= '-';
        elsif swclk_rising then
          rin.cycle_count <= r.cycle_count - 1;
          if r.cycle_count = c_zero then
            rin.state <= STATE_DATA_SHIFT_OUT;
            rin.cycle_count <= "011111";
          end if;
        end if;

      when STATE_DATA_SHIFT_OUT =>
        if swclk_falling then
          rin.swdio_oe <= '1';
          rin.swdio <= r.data(0);
          rin.par_out <= r.par_out xor r.data(0);
        elsif swclk_rising then
          rin.cycle_count <= r.cycle_count - 1;
          rin.data <= '-' & r.data(31 downto 1);
          if r.cycle_count = c_zero then
            rin.state <= STATE_PARITY_SHIFT_OUT;
          end if;
        end if;

      when STATE_PARITY_SHIFT_OUT =>
        if swclk_falling then
          rin.swdio_oe <= '1';
          rin.swdio <= r.par_out;
        elsif swclk_rising then
          rin.state <= STATE_RUN;
          rin.cycle_count <= "000001";
        end if;

      when STATE_DATA_SHIFT_IN =>
        if swclk_falling then
          rin.swdio_oe <= '0';
          rin.swdio <= '-';
        elsif swclk_rising then
          rin.cycle_count <= r.cycle_count - 1;
          rin.data <= p_swdio_i & r.data(31 downto 1);
          rin.par_in <= r.par_in xor p_swdio_i;
          if r.cycle_count = c_zero then
            rin.state <= STATE_PARITY_SHIFT_IN;
          end if;
        end if;

      when STATE_PARITY_SHIFT_IN =>
        if swclk_falling then
          rin.swdio_oe <= '0';
          rin.swdio <= '-';
        elsif swclk_rising then
          rin.par_in <= r.par_in xor p_swdio_i;
          rin.state <= STATE_DATA_TURNAROUND;
          rin.cycle_count <= "0000" & r.turnaround;
        end if;

      when STATE_DATA_TURNAROUND =>
        if swclk_falling then
          rin.swdio_oe <= '0';
          rin.swdio <= '-';
        elsif swclk_rising then
          rin.cycle_count <= r.cycle_count - 1;
          if r.cycle_count = c_zero then
            rin.state <= STATE_RUN;
            rin.cycle_count <= "000001";
          end if;
        end if;

      when STATE_RUN =>
        if swclk_falling then
          rin.swdio_oe <= '1';
          rin.swdio <= r.run_val;
        elsif swclk_rising then
          rin.cycle_count <= r.cycle_count - 1;
          if r.cycle_count = c_zero then
            rin.state <= STATE_RSP_PUT;
          end if;
        end if;

      when STATE_BITBANG =>
        if swclk_falling then
          rin.swdio_oe <= '1';
          rin.swdio <= r.data(0);
          rin.run_val <= r.data(0);
        elsif swclk_rising then
          rin.data <= '-' & r.data(31 downto 1);
          rin.cycle_count <= r.cycle_count - 1;
          if r.cycle_count = c_zero then
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
