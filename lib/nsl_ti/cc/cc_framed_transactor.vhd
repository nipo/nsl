library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_ti, nsl_bnoc;
use nsl_ti.cc.all;

entity cc_framed_transactor is
  generic(
    divisor_shift : natural := 0
    );
  port(
    clock_i    : in std_ulogic;
    reset_n_i : in std_ulogic;

    cc_o : out cc_m_o;
    cc_i : in cc_m_i;

    cmd_i  : in nsl_bnoc.framed.framed_req;
    cmd_o  : out nsl_bnoc.framed.framed_ack;
    rsp_o  : out nsl_bnoc.framed.framed_req;
    rsp_i  : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of cc_framed_transactor is
  
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

  constant divisor_width : integer := r.divisor'length + divisor_shift;
  signal divisor : std_ulogic_vector(divisor_width-1 downto 0);
  
begin

  ck : process (clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition : process (r, cmd_i, rsp_i, s_busy, s_done, s_rdata, s_ready)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.divisor <= (others => '1');
        rin.state <= ST_CMD_GET;

      when ST_CMD_GET =>
        if cmd_i.valid = '1' then
          rin.last <= cmd_i.last;
          rin.cmd <= cmd_i.data;
          rin.state <= ST_CMD_ROUTE;
        end if;

      when ST_CMD_ROUTE =>
        rin.in_count <= 0;
        rin.out_count <= 0;

        if std_match(r.cmd, CC_CMD_CMD) then
          rin.state <= ST_DATA_GET;
          rin.in_count <= to_integer(unsigned(r.cmd(1 downto 0)));
          rin.out_count <= to_integer(unsigned(r.cmd(3 downto 2)));
          rin.wait_ready <= r.cmd(4) = '1';

        elsif std_match(r.cmd, CC_CMD_ACQUIRE) then
          rin.state <= ST_ACQUIRE;

        elsif std_match(r.cmd, CC_CMD_RESET) then
          rin.state <= ST_RELEASE;

        elsif std_match(r.cmd, CC_CMD_DIV) then
          rin.state <= ST_RSP_PUT;
          rin.divisor <= r.cmd(rin.divisor'range);

        elsif std_match(r.cmd, CC_CMD_WAIT) then
          rin.state <= ST_WAIT;
          rin.data <= "00" & r.cmd(5 downto 0);

        else
          rin.state <= ST_RSP_PUT;
        end if;
        
      when ST_RSP_PUT =>
        if rsp_i.ready = '1' then
          if r.in_count = 0 then
            rin.state <= ST_CMD_GET;
          else
            rin.in_count <= r.in_count - 1;
            rin.state <= ST_READ;
          end if;
        end if;

      when ST_DATA_GET =>
        if cmd_i.valid = '1' then
          rin.state <= ST_WRITE;
          rin.data <= cmd_i.data;
          rin.last <= cmd_i.last;
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
        if rsp_i.ready = '1' then
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
        rsp_o.valid <= '1';
        rsp_o.data <= r.data;
        if r.in_count = 0 then
          rsp_o.last <= r.last;
        else
          rsp_o.last <= '0';
        end if;

      when ST_RSP_PUT =>
        rsp_o.valid <= '1';
        rsp_o.data <= r.cmd;
        if r.in_count = 0 then
          rsp_o.last <= r.last;
        else
          rsp_o.last <= '0';
        end if;

      when others =>
        rsp_o.valid <= '0';
        rsp_o.data <= (others => '-');
        rsp_o.last <= '-';
    end case;

    case r.state is
      when ST_DATA_GET | ST_CMD_GET =>
        cmd_o.ready <= '1';

      when others =>
        cmd_o.ready <= '0';
    end case;
  end process;

  divisor(r.divisor'length+divisor_shift-1 downto divisor_shift) <= r.divisor;
  divisor(divisor_shift-1 downto 0) <= (others => '1');

  master: nsl_ti.cc.cc_master
    generic map(
      divisor_width => r.divisor'length + divisor_shift
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      divisor_i => divisor,

      cc_o => cc_o,
      cc_i => cc_i,

      ready_o => s_ready,
      rdata_o => s_rdata,
      wdata_i => r.data,

      cmd_i => s_cmd,
      busy_o => s_busy,
      done_o => s_done
      );
  
end architecture;
