library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.ti.all;

entity ti_framed_cc is
  port(
    p_clk    : in std_ulogic;
    p_resetn : in std_ulogic;

    p_cc_resetn : out std_ulogic;
    p_cc_dc     : out std_ulogic;
    p_cc_ddo    : out std_ulogic;
    p_cc_ddi    : in  std_ulogic;
    p_cc_ddoe   : out std_ulogic;

    p_cmd_val  : in nsl.framed.framed_req;
    p_cmd_ack  : out nsl.framed.framed_ack;
    p_rsp_val  : out nsl.framed.framed_req;
    p_rsp_ack  : in nsl.framed.framed_ack
    );
end entity;

architecture rtl of ti_framed_cc is
  
  type state_t is (
    ST_RESET,
    ST_CMD_GET,
    ST_CMD_ROUTE,
    ST_RSP_PUT,
    ST_DATA_DITCH,
    ST_DATA_PUT,
    ST_DATA_GET,
    ST_READ,
    ST_WRITE,
    ST_ACQUIRE,
    ST_RELEASE,
    ST_WAIT
    );
  
  type regs_t is record
    state                : state_t;
    last                 : std_ulogic;
    ack                  : std_ulogic;
    cmd, data            : std_ulogic_vector(7 downto 0);
    wait_ready           : boolean;
    out_count            : natural range 0 to 4;
    in_count             : natural range 0 to 2;
    divisor              : std_ulogic_vector(5 downto 0);
  end record;

  signal r, rin : regs_t;

  signal s_rdata    :  std_ulogic_vector(7 downto 0);
  signal s_ready    :  std_ulogic;
  signal s_cmd      :  cc_cmd_t;
  signal s_busy     :  std_ulogic;
  signal s_done     :  std_ulogic;

begin

  ck : process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition : process (r, p_cmd_val, p_rsp_ack, s_busy, s_done, s_rdata)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.divisor <= (others => '1');
        rin.state <= ST_CMD_GET;

      when ST_CMD_GET =>
        if p_cmd_val.valid = '1' then
          rin.last <= p_cmd_val.last;
          rin.cmd <= p_cmd_val.data;
          rin.state <= ST_CMD_ROUTE;
        end if;

      when ST_CMD_ROUTE =>
        rin.in_count <= 0;
        rin.out_count <= 0;

        if std_match(r.cmd, TI_CC_CMD_CMD) then
          rin.state <= ST_DATA_GET;
          rin.in_count <= to_integer(unsigned(r.cmd(1 downto 0)));
          rin.out_count <= to_integer(unsigned(r.cmd(3 downto 2)));
          rin.wait_ready <= r.cmd(4) = '1';

        elsif std_match(r.cmd, TI_CC_CMD_ACQUIRE) then
          rin.state <= ST_ACQUIRE;

        elsif std_match(r.cmd, TI_CC_CMD_RESET) then
          rin.state <= ST_RELEASE;

        elsif std_match(r.cmd, TI_CC_CMD_DIV) then
          rin.state <= ST_RSP_PUT;
          rin.divisor <= r.cmd(rin.divisor'range);

        elsif std_match(r.cmd, TI_CC_CMD_WAIT) then
          rin.state <= ST_WAIT;
          rin.data <= "00" & r.cmd(5 downto 0);

        else
          rin.state <= ST_RSP_PUT;
        end if;
        
      when ST_RSP_PUT =>
        if p_rsp_ack.ready = '1' then
          if r.in_count = 0 then
            rin.state <= ST_CMD_GET;
          else
            rin.in_count <= r.in_count - 1;
            rin.state <= ST_READ;
          end if;
        end if;

      when ST_DATA_GET =>
        if p_cmd_val.valid = '1' then
          rin.state <= ST_WRITE;
          rin.data <= p_cmd_val.data;
          rin.last <= p_cmd_val.last;
        end if;

      when ST_ACQUIRE | ST_RELEASE | ST_WAIT =>
        if s_done = '1' then
          rin.state <= ST_RSP_PUT;
        end if;

      when ST_WRITE =>
        if s_done = '1' then
          if r.out_count = 0 then
            rin.state <= ST_RSP_PUT;
          else
            rin.state <= ST_DATA_GET;
            rin.out_count <= r.out_count - 1;
          end if;
        end if;

      when ST_READ =>
        if s_done = '1' then
          rin.data <= s_rdata;
          if not r.wait_ready or s_ready = '1' then
            rin.state <= ST_DATA_PUT;
            rin.wait_ready <= false;
          else
            rin.state <= ST_DATA_DITCH;
          end if;
        end if;

      when ST_DATA_DITCH =>
        rin.state <= ST_READ;

      when ST_DATA_PUT =>
        if p_rsp_ack.ready = '1' then
          if r.in_count = 0 then
            rin.state <= ST_CMD_GET;
          else
            rin.state <= ST_READ;
            rin.in_count <= r.in_count - 1;
          end if;
        end if;
    end case;
  end process;

  moore : process (r)
  begin
    case r.state is
      when ST_ACQUIRE =>
        s_cmd <= CC_RESET_ACQUIRE;

      when ST_RELEASE =>
        s_cmd <= CC_RESET_RELEASE;

      when ST_WAIT =>
        s_cmd <= CC_WAIT;

      when ST_READ =>
        s_cmd <= CC_READ;

      when ST_WRITE =>
        s_cmd <= CC_WRITE;

      when others =>
        s_cmd <= CC_NOOP;
    end case;

    case r.state is
      when ST_DATA_PUT =>
        p_rsp_val.valid <= '1';
        p_rsp_val.data <= r.data;
        if r.in_count = 0 then
          p_rsp_val.last <= r.last;
        else
          p_rsp_val.last <= '0';
        end if;

      when ST_RSP_PUT =>
        p_rsp_val.valid <= '1';
        p_rsp_val.data <= r.cmd;
        if r.in_count = 0 then
          p_rsp_val.last <= r.last;
        else
          p_rsp_val.last <= '0';
        end if;

      when others =>
        p_rsp_val.valid <= '0';
        p_rsp_val.data <= (others => '-');
        p_rsp_val.last <= '-';
    end case;

    case r.state is
      when ST_DATA_GET | ST_CMD_GET =>
        p_cmd_ack.ready <= '1';

      when others =>
        p_cmd_ack.ready <= '0';
    end case;
  end process;

  master: ti_cc_master
    generic map(
      divisor_width => r.divisor'length
      )
    port map(
      p_clk => p_clk,
      p_resetn => p_resetn,
      p_divisor => r.divisor,

      p_cc_resetn => p_cc_resetn,
      p_cc_dc => p_cc_dc,
      p_cc_ddoe => p_cc_ddoe,
      p_cc_ddi => p_cc_ddi,
      p_cc_ddo => p_cc_ddo,

      p_ready => s_ready,
      p_rdata => s_rdata,
      p_wdata => r.data,

      p_cmd => s_cmd,
      p_busy => s_busy,
      p_done => s_done
      );
  
end architecture;
