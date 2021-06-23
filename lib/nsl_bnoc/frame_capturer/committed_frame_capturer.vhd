library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

entity committed_frame_gateway is
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    cmd_i : in  nsl_bnoc.framed.framed_req;
    cmd_o : out nsl_bnoc.framed.framed_ack;
    rsp_o : out nsl_bnoc.framed.framed_req;
    rsp_i : in  nsl_bnoc.framed.framed_ack;

    rx_i : in  nsl_bnoc.committed.committed_req;
    rx_o : out nsl_bnoc.committed.committed_ack;
    tx_o : out nsl_bnoc.committed.committed_req;
    tx_i : in  nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of framed_frame_capturer is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_CAPTURE_SYNC,
    ST_CAPTURE_FORWARD,
    ST_CAPTURE_FAIL,
    ST_TRANSMIT_RSP,
    ST_TRANSMIT_FORWARD,
    ST_TRANSMIT_COMMIT
    );
  
  type regs_t is record
    state      : state_t;
    timeout    : natural range 0 to 125000000;
    in_txn     : boolean;
  end record;

  signal r, rin: regs_t;

begin
  
  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, cmd_i, rsp_i, rx_i, tx_i)
  begin
    rin <= r;

    if rx_i.valid = '1' then
      rin.in_txn <= rx_i.last = '0';
    end if;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if cmd_i.valid = '1' then
          if std_match(cmd_i.data, nsl_bnoc.frame_capturer.CMD_CAPTURE)
            and cmd_i.last = '1' then
            if not r.in_txn and rx_i.valid = '0' then
              rin.state <= ST_CAPTURE_FORWARD;
              rin.timeout <= 125000000 / 4;
            else
              rin.state <= ST_CAPTURE_SYNC;
              rin.timeout <= 125000000;
            end if;
          elsif cmd_i.last = '0' then
            rin.state <= ST_TRANSMIT_FORWARD;
          end if;
        end if;

      when ST_CAPTURE_SYNC =>
        if r.timeout /= 0 then
          rin.timeout <= r.timeout - 1;
        else
          rin.state <= ST_CAPTURE_FAIL;
        end if;

        if rx_i.valid = '1' and rx_i.last = '1' then
          rin.state <= ST_CAPTURE_FORWARD;
          rin.timeout <= 125000000 / 4;
        end if;

      when ST_CAPTURE_FORWARD =>
        if rx_i.valid = '1' then
          rin.timeout <= 125000000;
          if rx_i.last and rsp_i.ready = '1' then
            rin.state <= ST_IDLE;
          end if;
        elsif r.timeout /= 0 then
          rin.timeout <= r.timeout - 1;
        else
          rin.state <= ST_CAPTURE_FAIL;
        end if;

      when ST_CAPTURE_FAIL =>
        if rsp_i.ready = '1' then
          rin.state <= ST_IDLE;
        end if;

      when ST_TRANSMIT_FORWARD =>
        if cmd_i.valid = '1' and cmd_i.last = '1' and tx_i.ready = '1' then
          rin.state <= ST_TRANSMIT_RSP;
        end if;

      when ST_TRANSMIT_RSP =>
        if rsp_i.ready = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
      
  end process;

  mealy: process(r, rx_i, cmd_i, tx_i, rsp_i)
  begin
    cmd_o.ready <= '0';
    rsp_o.valid <= '0';
    rsp_o.last <= '-';
    rsp_o.data <= (others => '-');
    tx_o.valid <= '0';
    tx_o.last <= '-';
    tx_o.data <= (others => '-');
    rx_o.ready <= '1';

    case r.state is
      when ST_RESET | ST_CAPTURE_SYNC =>
        null;

      when ST_IDLE =>
        cmd_o.ready <= '1';

      when ST_CAPTURE_FORWARD =>
        rsp_o <= rx_i;
        rx_o <= rsp_i;

      when ST_CAPTURE_FAIL =>
        rsp_o.valid <= '1';
        rsp_o.last <= '1';
        rsp_o.data <= x"e1";

      when ST_TRANSMIT_RSP =>
        rsp_o.valid <= '1';
        rsp_o.last <= '1';
        rsp_o.data <= x"dd";

      when ST_TRANSMIT_FORWARD =>
        tx_o <= cmd_i;
        cmd_o <= tx_i;
    end case;
    
  end process;

end architecture;

