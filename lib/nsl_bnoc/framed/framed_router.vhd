library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data, nsl_logic, nsl_math;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use nsl_data.fifo.all;

entity framed_router is
  generic(
    in_count_c : natural;
    out_count_c : natural;
    in_header_count_c : natural := 0;
    out_header_count_c : natural := 0
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i   : in  std_ulogic;

    in_i      : in framed_req_array(0 to in_count_c-1);
    in_o      : out framed_ack_array(0 to in_count_c-1);

    out_o     : out framed_req_array(0 to out_count_c-1);
    out_i     : in framed_ack_array(0 to out_count_c-1);

    route_valid_o       : out std_ulogic;
    route_header_o      : out byte_string(0 to in_header_count_c-1);
    route_source_o      : out natural range 0 to in_count_c-1;

    route_ready_i       : in  std_ulogic := '1';
    route_header_i      : in  byte_string(0 to out_header_count_c-1) := (others => x"00");
    route_destination_i : in  natural range 0 to out_count_c-1;
    route_drop_i        : in std_ulogic := '0'
    );
end entity;

architecture rtl of framed_router is

  type input_port_state_t is (
    IS_RESET,
    IS_HEADER,
    IS_ROUTE_REQ,
    IS_DATA,
    IS_DONE,
    IS_DROP
    );
  
  type input_port_regs_t is
  record
    state : input_port_state_t;
    left : natural range 0 to in_header_count_c-1;
    header : byte_string(0 to in_header_count_c-1);
    fifo: byte_string(0 to 1);
    fifo_fillness: natural range 0 to 2;
    out_index: natural range 0 to out_count_c-1;
  end record;

  type output_port_state_t is (
    OS_RESET,
    OS_IDLE,
    OS_HEADER,
    OS_DATA,
    OS_FLUSH
    );
  
  type output_port_regs_t is
  record
    state : output_port_state_t;
    left : natural range 0 to out_header_count_c-1;
    header : byte_string(0 to out_header_count_c-1);
    fifo: byte_string(0 to 1);
    fifo_fillness: natural range 0 to 2;
    in_index: natural range 0 to in_count_c-1;
  end record;

  type input_port_regs_vector is array (natural range <>) of input_port_regs_t;
  type output_port_regs_vector is array (natural range <>) of output_port_regs_t;

  type state_t is (
    ST_RESET,
    ST_IN_SELECT,
    ST_ROUTE_REQ,
    ST_OUT_SELECT,
    ST_OUT_GRANT,
    ST_OUT_DROP
    );
  
  type regs_t is
  record
    ip : input_port_regs_vector(0 to in_count_c-1);
    op : output_port_regs_vector(0 to out_count_c-1);
    state: state_t;
    in_index: natural range 0 to in_count_c-1;
    out_index: natural range 0 to out_count_c-1;
    in_header : byte_string(0 to in_header_count_c-1);
    out_header : byte_string(0 to out_header_count_c-1);
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      for i in r.ip'range
      loop
        r.ip(i).state <= IS_RESET;
      end loop;

      for i in r.op'range
      loop
        r.op(i).state <= OS_RESET;
      end loop;

      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, in_i, out_i,
                      route_ready_i, route_header_i,
                      route_destination_i, route_drop_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IN_SELECT;
        rin.in_index <= 0;

      when ST_IN_SELECT =>
        if r.ip(r.in_index).state = IS_ROUTE_REQ then
          rin.state <= ST_ROUTE_REQ;
          rin.in_header <= r.ip(r.in_index).header;
        elsif r.in_index = in_count_c-1 then
          rin.in_index <= 0;
        else
          rin.in_index <= r.in_index + 1;
        end if;

      when ST_ROUTE_REQ =>
        if route_ready_i = '1' then
          if route_drop_i = '1' then
            rin.state <= ST_OUT_DROP;
          else
            rin.state <= ST_OUT_SELECT;
            rin.out_index <= route_destination_i;
            rin.out_header <= route_header_i;
          end if;
        end if;

      when ST_OUT_SELECT =>
        if r.op(r.out_index).state = OS_IDLE then
          rin.state <= ST_OUT_GRANT;
        else
          rin.state <= ST_IN_SELECT;
        end if;

      when ST_OUT_GRANT | ST_OUT_DROP =>
        rin.state <= ST_IN_SELECT;
    end case;

    for i in r.ip'range
    loop
      case r.ip(i).state is
        when IS_RESET =>
          if in_header_count_c /= 0 then
            rin.ip(i).state <= IS_HEADER;
            rin.ip(i).left <= in_header_count_c-1;
          elsif in_i(i).valid = '1' then
            rin.ip(i).state <= IS_ROUTE_REQ;
          end if;
          rin.ip(i).fifo_fillness <= 0;

        when IS_HEADER =>
          if in_i(i).valid = '1' then
            rin.ip(i).header <= shift_left(r.ip(i).header, in_i(i).data);
            if r.ip(i).left /= 0 then
              rin.ip(i).left <= r.ip(i).left - 1;
            else
              rin.ip(i).state <= IS_ROUTE_REQ;
            end if;

            if in_i(i).last = '1' then
              rin.ip(i).state <= IS_RESET;
            end if;
          end if;

        when IS_ROUTE_REQ =>
          if r.in_index = i then
            case r.state is
              when ST_OUT_GRANT =>
                rin.ip(i).state <= IS_DATA;
                rin.ip(i).out_index <= r.out_index;

              when ST_OUT_DROP =>
                rin.ip(i).state <= IS_DROP;

              when others =>
                null;
            end case;
          end if;

        when IS_DROP =>
          if in_i(i).valid = '1' and in_i(i).last = '1' then
            rin.ip(i).state <= IS_RESET;
          end if;

        when IS_DATA =>
          if fifo_can_push(r.ip(i).fifo, r.ip(i).fifo_fillness)
            and in_i(i).valid = '1'
            and in_i(i).last = '1'
            and (r.op(r.ip(i).out_index).state = OS_FLUSH
                 or r.op(r.ip(i).out_index).state = OS_DATA) then
            rin.ip(i).state <= IS_DONE;
          end if;

          rin.ip(i).fifo <= fifo_shift_data(
            storage => r.ip(i).fifo,
            fillness => r.ip(i).fifo_fillness,

            valid => in_i(i).valid = '1',
            data => in_i(i).data,

            ready => fifo_can_push(
              r.op(r.ip(i).out_index).fifo,
              r.op(r.ip(i).out_index).fifo_fillness)
            and (r.op(r.ip(i).out_index).state = OS_FLUSH
                 or r.op(r.ip(i).out_index).state = OS_DATA)
            );
          rin.ip(i).fifo_fillness <= fifo_shift_fillness(
            storage => r.ip(i).fifo,
            fillness => r.ip(i).fifo_fillness,

            valid => in_i(i).valid = '1',
            data => in_i(i).data,

            ready => fifo_can_push(
              r.op(r.ip(i).out_index).fifo,
              r.op(r.ip(i).out_index).fifo_fillness)
            and (r.op(r.ip(i).out_index).state = OS_FLUSH
                 or r.op(r.ip(i).out_index).state = OS_DATA)
            );

        when IS_DONE =>
          if r.op(r.ip(i).out_index).state = OS_FLUSH then
            rin.ip(i).state <= IS_RESET;
          end if;
      end case;
    end loop;

    for i in r.op'range
    loop
      case r.op(i).state is
        when OS_RESET =>
          rin.op(i).state <= OS_IDLE;
          rin.op(i).fifo_fillness <= 0;

        when OS_IDLE =>
          if r.state = ST_OUT_SELECT and r.out_index = i then
            if out_header_count_c /= 0 then
              rin.op(i).state <= OS_HEADER;
              rin.op(i).left <= out_header_count_c-1;
              rin.op(i).header <= r.out_header;
            else
              rin.op(i).state <= OS_DATA;
            end if;
            rin.op(i).in_index <= r.in_index;
          end if;

        when OS_HEADER =>
          if out_i(i).ready = '1' then
            rin.op(i).header <= shift_left(r.op(i).header);
            if r.op(i).left /= 0 then
              rin.op(i).left <= r.op(i).left - 1;
            else
              rin.op(i).state <= OS_DATA;
            end if;
          end if;

        when OS_DATA =>
          if r.ip(r.op(i).in_index).state = IS_DONE then
            rin.op(i).state <= OS_FLUSH;
          end if;

          rin.op(i).fifo <= fifo_shift_data(
            storage => r.op(i).fifo,
            fillness => r.op(i).fifo_fillness,

            valid => fifo_can_pop(
              r.ip(r.op(i).in_index).fifo,
              r.ip(r.op(i).in_index).fifo_fillness),
            data => r.ip(r.op(i).in_index).fifo(0),

            ready => out_i(i).ready = '1'
            );
          rin.op(i).fifo_fillness <= fifo_shift_fillness(
            storage => r.op(i).fifo,
            fillness => r.op(i).fifo_fillness,

            valid => fifo_can_pop(
              r.ip(r.op(i).in_index).fifo,
              r.ip(r.op(i).in_index).fifo_fillness),
            data => r.ip(r.op(i).in_index).fifo(0),

            ready => out_i(i).ready = '1'
            );

        when OS_FLUSH =>
          if r.op(i).state = OS_FLUSH and r.op(i).fifo_fillness = 0 then
            rin.op(i).state <= OS_IDLE;
          end if;

          rin.op(i).fifo <= fifo_shift_data(
            storage => r.op(i).fifo,
            fillness => r.op(i).fifo_fillness,

            valid => false,
            data => "--------",

            ready => out_i(i).ready = '1'
            );
          rin.op(i).fifo_fillness <= fifo_shift_fillness(
            storage => r.op(i).fifo,
            fillness => r.op(i).fifo_fillness,

            valid => false,
            data => "--------",

            ready => out_i(i).ready = '1'
            );
          
      end case;
    end loop;
  end process;

  moore: process(r) is
  begin
    route_valid_o <= to_logic(r.state = ST_ROUTE_REQ);
    route_header_o <= r.in_header;
    route_source_o <= r.in_index;

    for i in r.ip'range
    loop
      case r.ip(i).state is
        when IS_RESET | IS_ROUTE_REQ | IS_DONE =>
          in_o(i).ready <= '0';
        when IS_HEADER | IS_DROP =>
          in_o(i).ready <= '1';
        when IS_DATA =>
          in_o(i).ready <= fifo_ready(r.ip(i).fifo, r.ip(i).fifo_fillness);
      end case;
    end loop;

    for i in r.op'range
    loop
      case r.op(i).state is
        when OS_RESET | OS_IDLE =>
          out_o(i).valid <= '0';
          out_o(i).last <= '-';
          out_o(i).data <= "--------";

        when OS_HEADER =>
          out_o(i).valid <= '1';
          out_o(i).last <= '0';
          out_o(i).data <= first_left(r.op(i).header);

        when OS_DATA =>
          out_o(i).valid <= fifo_valid(r.op(i).fifo, r.op(i).fifo_fillness);
          out_o(i).last <= '0';
          out_o(i).data <= r.op(i).fifo(0);

        when OS_FLUSH =>
          out_o(i).valid <= fifo_valid(r.op(i).fifo, r.op(i).fifo_fillness);
          out_o(i).last <= to_logic(r.op(i).fifo_fillness = 1);
          out_o(i).data <= r.op(i).fifo(0);
      end case;
    end loop;
  end process;

end architecture;
