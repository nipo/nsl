library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

entity framed_frame_capturer is
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    cmd_i : in  nsl_bnoc.framed.framed_req;
    cmd_o : out nsl_bnoc.framed.framed_ack;
    rsp_o : out nsl_bnoc.framed.framed_req;
    rsp_i : in  nsl_bnoc.framed.framed_ack;

    capture_valid_i : in std_ulogic;
    capture_i : in  nsl_bnoc.framed.framed_req;
    transmit_o : out  nsl_bnoc.framed.framed_req;
    transmit_i : in   nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of framed_frame_capturer is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_CAPTURE_RSP,
    ST_CAPTURE_SYNC,
    ST_CAPTURE_FORWARD,
    ST_CAPTURE_END,
    ST_TRANSMIT_RSP,
    ST_TRANSMIT_FORWARD
    );
  
  type regs_t is record
    state      : state_t;
    timeout    : natural range 0 to 125000000;
    valid      : std_ulogic;
    cmd        : nsl_bnoc.framed.framed_data_t;
  end record;

  signal r, rin: regs_t;

  attribute keep_hierarchy : string;
  attribute keep_hierarchy of beh: architecture is "TRUE";

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

  transition: process(r, cmd_i, rsp_i, capture_i, transmit_i, capture_valid_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if cmd_i.valid = '1' then
          if std_match(cmd_i.data, nsl_bnoc.frame_capturer.CMD_CAPTURE)
            and cmd_i.last = '1' then
            rin.state <= ST_CAPTURE_RSP;
          elsif cmd_i.last = '0' then
            rin.state <= ST_TRANSMIT_FORWARD;
          end if;
        end if;

      when ST_CAPTURE_RSP =>
        if rsp_i.ready = '1' then
          rin.state <= ST_CAPTURE_SYNC;
          rin.timeout <= 125000000 / 4;
        end if;

      when ST_CAPTURE_SYNC =>
        if r.timeout /= 0 then
          rin.timeout <= r.timeout - 1;
        else
          rin.state <= ST_CAPTURE_END;
        end if;

        if (capture_i.valid = '1' and capture_i.last = '1') or capture_i.valid = '0' then
          rin.valid <= '0';
          rin.state <= ST_CAPTURE_FORWARD;
          rin.timeout <= 125000000 / 4;
        end if;

      when ST_CAPTURE_FORWARD =>
        if r.timeout /= 0 then
          rin.timeout <= r.timeout - 1;
        elsif r.valid = '0' then
          rin.state <= ST_CAPTURE_END;
        end if;

        if capture_i.valid = '1' then
          rin.valid <= '1';
          if capture_i.last = '1' then
            rin.state <= ST_CAPTURE_END;
            rin.valid <= capture_valid_i;
          end if;
        end if;

      when ST_CAPTURE_END =>
        if rsp_i.ready = '1' then
          rin.state <= ST_IDLE;
        end if;

      when ST_TRANSMIT_FORWARD =>
        if cmd_i.valid = '1' and cmd_i.last = '1' and transmit_i.ready = '1' then
          rin.state <= ST_TRANSMIT_RSP;
        end if;

      when ST_TRANSMIT_RSP =>
        if rsp_i.ready = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
      
  end process;

  mealy: process(r, capture_i, cmd_i, transmit_i)
  begin
    cmd_o.ready <= '0';
    rsp_o.valid <= '0';
    rsp_o.last <= '-';
    rsp_o.data <= (others => '-');
    transmit_o.valid <= '0';
    transmit_o.last <= '-';
    transmit_o.data <= (others => '-');

    case r.state is
      when ST_RESET | ST_CAPTURE_SYNC =>
        null;

      when ST_IDLE =>
        cmd_o.ready <= '1';

      when ST_CAPTURE_RSP =>
        rsp_o.valid <= '1';
        rsp_o.last <= '0';
        rsp_o.data <= x"99";

      when ST_CAPTURE_FORWARD =>
        rsp_o.valid <= capture_i.valid;
        rsp_o.data <= capture_i.data;
        rsp_o.last <= '0';

      when ST_CAPTURE_END =>
        rsp_o.valid <= '1';
        rsp_o.last <= '1';
        if r.valid = '1' then
          rsp_o.data <= x"e1";
        else
          rsp_o.data <= x"e0";
        end if;

      when ST_TRANSMIT_RSP =>
        rsp_o.valid <= '1';
        rsp_o.last <= '1';
        rsp_o.data <= x"dd";

      when ST_TRANSMIT_FORWARD =>
        transmit_o <= cmd_i;
        cmd_o <= transmit_i;
    end case;
    
  end process;

end architecture;

