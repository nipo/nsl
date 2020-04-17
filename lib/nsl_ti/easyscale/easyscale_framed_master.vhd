library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_ti, nsl_io;

entity easyscale_framed_master is
  generic(
    clock_rate_c : natural
    );
  port(
    reset_n_i    : in std_ulogic;
    clock_i       : in std_ulogic;

    easyscale_o: out nsl_io.io.tristated;
    easyscale_i: in std_ulogic;

    cmd_i  : in  nsl_bnoc.framed.framed_req;
    cmd_o  : out nsl_bnoc.framed.framed_ack;

    rsp_o : out nsl_bnoc.framed.framed_req;
    rsp_i : in  nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of easyscale_framed_master is

  type state_e is (
    STATE_RESET,
    STATE_DADDR_GET,
    STATE_DATA_GET,
    STATE_EXECUTE,
    STATE_WAIT,
    STATE_ACK_PUT
    );
  
  type regs_t is record
    state : state_e;
    daddr : nsl_bnoc.framed.framed_data_t;
    data  : nsl_bnoc.framed.framed_data_t;
    ack   : std_ulogic;
    last  : std_ulogic;
  end record;

  signal r, rin: regs_t;

  signal s_busy, s_start, s_ack : std_ulogic;
  
begin

  ez: nsl_ti.easyscale.easyscale_master
    generic map(
      clock_rate_c => clock_rate_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,
      easyscale_o => easyscale_o,
      easyscale_i => easyscale_i,
      dev_addr_i => r.daddr,
      ack_req_i => '1',
      reg_addr_i => r.data(6 downto 5),
      data_i => r.data(4 downto 0),
      start_i => s_start,
      busy_o => s_busy,
      dev_ack_o => s_ack
      );
  
  regs: process (reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      r.state <= STATE_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, s_busy, s_ack, cmd_i, rsp_i)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_DADDR_GET;

      when STATE_DADDR_GET =>
        if cmd_i.valid = '1' then
          rin.state <= STATE_DATA_GET;
          rin.daddr <= cmd_i.data;
        end if;

      when STATE_DATA_GET =>
        if cmd_i.valid = '1' then
          rin.last <= cmd_i.last;
          rin.state <= STATE_EXECUTE;
          rin.data <= cmd_i.data;
        end if;

      when STATE_EXECUTE =>
        if s_busy = '1' then
          rin.state <= STATE_WAIT;
        end if;

      when STATE_WAIT =>
        if s_busy = '0' then
          rin.state <= STATE_ACK_PUT;
          rin.ack <= s_ack;
        end if;

      when STATE_ACK_PUT =>
        if rsp_i.ready = '1' then
          rin.state <= STATE_DADDR_GET;
        end if;

    end case;
  end process;

  moore: process(r)
  begin
    cmd_o.ready <= '0';
    rsp_o.valid <= '0';
    rsp_o.data <= (others => '-');
    rsp_o.last <= '-';
    s_start <= '0';
    
    case r.state is
      when STATE_RESET | STATE_WAIT =>
        null;

      when STATE_DADDR_GET | STATE_DATA_GET =>
        cmd_o.ready <= '1';

      when STATE_EXECUTE =>
        s_start <= '1';

      when STATE_ACK_PUT =>
        rsp_o.valid <= '1';
        rsp_o.data <= "0000000" & r.ack;
        rsp_o.last <= r.last;
    end case;
  end process;
  
end;
