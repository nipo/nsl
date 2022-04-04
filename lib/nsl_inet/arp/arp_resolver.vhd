library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet, nsl_math, nsl_logic;
use nsl_bnoc.framed.all;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_inet.arp.all;

entity arp_resolver is
  generic(
    header_length_c : natural := 0;
    ha_length_c : natural;
    pa_length_c : positive
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    tx_in_i : in committed_req;
    tx_in_o : out committed_ack;
    tx_out_o : out committed_req;
    tx_out_i : in committed_ack;

    rx_in_i : in committed_req;
    rx_in_o : out committed_ack;
    rx_out_o : out committed_req;
    rx_out_i : in committed_ack;

    request_o : out framed_req;
    request_i : in framed_ack;

    response_i : in framed_req;
    response_o : out framed_ack
    );
end entity;

architecture beh of arp_resolver is

begin

  tx: block
    type in_state_t is (
      IN_RESET,
      IN_HEADER,
      IN_PA,
      IN_DECIDE,
      IN_REQUEST,
      IN_RESPONSE,
      IN_HA,
      IN_DATA,
      IN_COMMIT,
      IN_CANCEL,
      IN_DROP
      );

    type out_state_t is (
      OUT_IDLE,
      OUT_HEADER,
      OUT_HA,
      OUT_PA,
      OUT_DATA,
      OUT_COMMIT,
      OUT_CANCEL
      );

    constant fifo_depth_c : integer := 2;
    constant max_step_c : integer := nsl_math.arith.max(
      pa_length_c, nsl_math.arith.max(
      ha_length_c, header_length_c));

    type regs_t is
    record
      in_state : in_state_t;
      in_left : integer range 0 to max_step_c-1;

      header : byte_string(0 to header_length_c-1);
      pa, last_pa : byte_string(0 to pa_length_c-1);
      ha : byte_string(0 to ha_length_c-1);

      fifo: byte_string(0 to fifo_depth_c-1);
      fifo_fillness: integer range 0 to fifo_depth_c;

      out_state : out_state_t;
      out_left : integer range 0 to max_step_c-1;
    end record;

    signal r, rin: regs_t;
    
  begin

    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.in_state <= IN_RESET;
        r.out_state <= OUT_IDLE;
      end if;
    end process;

    transition: process(r, tx_in_i, tx_out_i, request_i, response_i) is
      variable fifo_push, fifo_pop: boolean;
      variable fifo_data : byte;
    begin
      rin <= r;

      fifo_pop := false;
      fifo_push := false;
      fifo_data := "--------";

      case r.in_state is
        when IN_RESET =>
          rin.fifo_fillness <= 0;
          if tx_in_i.valid = '1' then
            if header_length_c /= 0 then
              rin.in_state <= IN_HEADER;
              rin.in_left <= header_length_c - 1;
            else
              rin.in_state <= IN_PA;
              rin.in_left <= pa_length_c - 1;
            end if;
          end if;

        when IN_HEADER =>
          if tx_in_i.valid = '1' then
            rin.header <= shift_left(r.header, tx_in_i.data);
            if tx_in_i.last = '1' then
              rin.in_state <= IN_RESET;
            elsif r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_state <= IN_PA;
              rin.in_left <= pa_length_c - 1;
            end if;
          end if;

        when IN_PA =>
          if tx_in_i.valid = '1' then
            rin.pa <= shift_left(r.pa, tx_in_i.data);
            if tx_in_i.last = '1' then
              rin.in_state <= IN_RESET;
            elsif r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_state <= IN_DECIDE;
              rin.in_left <= pa_length_c - 1;
            end if;
          end if;

        when IN_DECIDE =>
          if r.pa = r.last_pa then
            rin.in_state <= IN_DATA;
          else
            rin.in_state <= IN_REQUEST;
            rin.in_left <= pa_length_c - 1;
          end if;
          
        when IN_REQUEST =>
          if request_i.ready = '1' then
            rin.pa <= rot_left(r.pa);
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_state <= IN_RESPONSE;
            end if;
          end if;

        when IN_RESPONSE =>
          if response_i.valid = '1' then
            if response_i.last = '1' then
              rin.in_state <= IN_DROP;
            else
              rin.in_state <= IN_HA;
              rin.last_pa <= r.pa;
            end if;
          end if;

        when IN_HA =>
          if response_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
            rin.ha <= shift_left(r.ha, response_i.data);
            if response_i.last = '1' then
              rin.in_state <= IN_DATA;
            end if;
          end if;

        when IN_DATA =>
          if tx_in_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
            fifo_push := true;
            if tx_in_i.last = '1' then
              if tx_in_i.data(0) = '1' then
                rin.in_state <= IN_COMMIT;
              else
                rin.in_state <= IN_CANCEL;
              end if;
            end if;
          end if;

        when IN_COMMIT | IN_CANCEL =>
          if r.out_state = OUT_COMMIT or r.out_state = OUT_CANCEL then
            rin.in_state <= IN_RESET;
          end if;

        when IN_DROP =>
          if tx_in_i.valid = '1' and tx_in_i.last = '1' then
            rin.in_state <= IN_RESET;
          end if;
      end case;

      case r.out_state is
        when OUT_IDLE =>
          if r.in_state = IN_DATA then
            if header_length_c /= 0 then
              rin.out_state <= OUT_HEADER;
              rin.out_left <= header_length_c - 1;
            else
              rin.out_left <= ha_length_c - 1;
              rin.out_state <= OUT_HA;
            end if;
          end if;

        when OUT_HEADER =>
          if tx_out_i.ready = '1' then
            rin.header <= shift_left(r.header);
            if r.out_left /= 0 then
              rin.out_left <= r.out_left - 1;
            else
              rin.out_left <= ha_length_c - 1;
              rin.out_state <= OUT_HA;
            end if;
          end if;

        when OUT_HA =>
          if tx_out_i.ready = '1' then
            rin.ha <= rot_left(r.ha);
            if r.out_left /= 0 then
              rin.out_left <= r.out_left - 1;
            else
              rin.out_left <= pa_length_c - 1;
              rin.out_state <= OUT_PA;
            end if;
          end if;

        when OUT_PA =>
          if tx_out_i.ready = '1' then
            rin.pa <= shift_left(r.pa);
            if r.out_left /= 0 then
              rin.out_left <= r.out_left - 1;
            else
              rin.out_state <= OUT_DATA;
            end if;
          end if;

        when OUT_DATA =>
          if tx_out_i.ready = '1' and r.fifo_fillness > 0 then
            fifo_pop := true;
          end if;

          if r.fifo_fillness = 0
            or (r.fifo_fillness = 1 and tx_out_i.ready = '1') then
            if r.in_state = IN_COMMIT then
              rin.out_state <= OUT_COMMIT;
            end if;
            if r.in_state = IN_CANCEL then
              rin.out_state <= OUT_CANCEL;
            end if;
          end if;

        when OUT_COMMIT | OUT_CANCEL =>
          if tx_out_i.ready = '1' then
            rin.out_state <= OUT_IDLE;
          end if;
      end case;

      if fifo_push and fifo_pop then
        rin.fifo <= shift_left(r.fifo);
        rin.fifo(r.fifo_fillness-1) <= tx_in_i.data;
      elsif fifo_push then
        rin.fifo(r.fifo_fillness) <= tx_in_i.data;
        rin.fifo_fillness <= r.fifo_fillness + 1;
      elsif fifo_pop then
        rin.fifo <= shift_left(r.fifo);
        rin.fifo_fillness <= r.fifo_fillness - 1;
      end if;
    end process;

    moore: process(r) is
    begin
      tx_in_o <= committed_ack_idle_c;
      request_o <= framed_req_idle_c;
      response_o <= framed_ack_idle_c;

      case r.in_state is
        when IN_RESET | IN_COMMIT | IN_CANCEL | IN_DECIDE =>
          null;

        when IN_PA | IN_DROP | IN_HEADER =>
          tx_in_o <= committed_accept(true);

        when IN_REQUEST =>
          request_o <= framed_flit(data => r.pa(0), last => r.in_left = 0);

        when IN_RESPONSE | IN_HA =>
          response_o <= framed_accept(true);

        when IN_DATA =>
          tx_in_o <= committed_accept(r.fifo_fillness < fifo_depth_c);
      end case;

      case r.out_state is
        when OUT_IDLE =>
          tx_out_o <= committed_req_idle_c;

        when OUT_HEADER =>
          tx_out_o <= committed_flit(first_left(r.header));

        when OUT_PA =>
          tx_out_o <= committed_flit(r.pa(0));

        when OUT_HA =>
          tx_out_o <= committed_flit(r.ha(0));

        when OUT_DATA =>
          tx_out_o <= committed_flit(data => r.fifo(0),
                                     valid => r.fifo_fillness /= 0);

        when OUT_COMMIT =>
          tx_out_o <= committed_commit(true);

        when OUT_CANCEL =>
          tx_out_o <= committed_commit(false);
      end case;
    end process;
  end block;

  rx: block
    type in_state_t is (
      IN_RESET,
      IN_HEADER,
      IN_DATA,
      IN_COMMIT,
      IN_CANCEL
      );

    type out_state_t is (
      OUT_DATA,
      OUT_COMMIT,
      OUT_CANCEL
      );

    constant fifo_depth_c : integer := 2;

    type regs_t is
    record
      in_state : in_state_t;
      in_left : integer range 0 to header_length_c + ha_length_c - 1;

      fifo: byte_string(0 to fifo_depth_c-1);
      fifo_fillness: integer range 0 to fifo_depth_c;

      out_state : out_state_t;
    end record;

    signal r, rin: regs_t;
    
  begin

    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.in_state <= IN_RESET;
        r.out_state <= OUT_DATA;
      end if;
    end process;

    transition: process(r, rx_in_i, rx_out_i) is
      variable fifo_push, fifo_pop: boolean;
      variable fifo_data : byte;
    begin
      rin <= r;

      fifo_pop := false;
      fifo_push := false;

      case r.in_state is
        when IN_RESET =>
          rin.fifo_fillness <= 0;
          if header_length_c + ha_length_c /= 0 then
            rin.in_state <= IN_HEADER;
            rin.in_left <= header_length_c + ha_length_c - 1;
          else
            rin.in_state <= IN_DATA;
          end if;

        when IN_HEADER =>
          if rx_in_i.valid = '1' then
            if rx_in_i.last = '1' then
              rin.in_state <= IN_RESET;
            elsif r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_state <= IN_DATA;
            end if;
          end if;

        when IN_DATA =>
          if rx_in_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
            fifo_push := true;
            if rx_in_i.last = '1' then
              if rx_in_i.data(0) = '1' then
                rin.in_state <= IN_COMMIT;
              else
                rin.in_state <= IN_CANCEL;
              end if;
            end if;
          end if;

        when IN_COMMIT | IN_CANCEL =>
          if r.out_state = OUT_COMMIT or r.out_state = OUT_CANCEL then
            rin.in_state <= IN_RESET;
          end if;
      end case;

      case r.out_state is
        when OUT_DATA =>
          if rx_out_i.ready = '1' and r.fifo_fillness > 0 then
            fifo_pop := true;
          end if;

          if r.fifo_fillness = 0
            or (r.fifo_fillness = 1 and rx_out_i.ready = '1') then
            if r.in_state = IN_COMMIT then
              rin.out_state <= OUT_COMMIT;
            end if;
            if r.in_state = IN_CANCEL then
              rin.out_state <= OUT_CANCEL;
            end if;
          end if;

        when OUT_COMMIT | OUT_CANCEL =>
          if rx_out_i.ready = '1' then
            rin.out_state <= OUT_DATA;
          end if;
      end case;

      if fifo_push and fifo_pop then
        rin.fifo <= shift_left(r.fifo);
        rin.fifo(r.fifo_fillness-1) <= rx_in_i.data;
      elsif fifo_push then
        rin.fifo(r.fifo_fillness) <= rx_in_i.data;
        rin.fifo_fillness <= r.fifo_fillness + 1;
      elsif fifo_pop then
        rin.fifo <= shift_left(r.fifo);
        rin.fifo_fillness <= r.fifo_fillness - 1;
      end if;
    end process;

    moore: process(r) is
    begin
      case r.in_state is
        when IN_RESET | IN_COMMIT | IN_CANCEL =>
          rx_in_o <= committed_ack_idle_c;

        when IN_HEADER =>
          rx_in_o <= committed_accept(true);

        when IN_DATA =>
          rx_in_o <= committed_accept(r.fifo_fillness < fifo_depth_c);
      end case;

      case r.out_state is
        when OUT_DATA =>
          rx_out_o <= committed_flit(data => r.fifo(0),
                                     valid => r.fifo_fillness /= 0);

        when OUT_COMMIT =>
          rx_out_o <= committed_commit(true);

        when OUT_CANCEL =>
          rx_out_o <= committed_commit(false);
      end case;
    end process;
  end block;
  
end architecture;
