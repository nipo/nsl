library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;
use nsl_amba.axi4_mm.all;

entity axi4_mm_lite_adapter is
  generic(
    full_config_c : config_t;
    lite_config_c : config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    full_i : in master_t;
    full_o : out slave_t;

    lite_o : out master_t;
    lite_i : in slave_t
    );
end entity;

architecture beh of axi4_mm_lite_adapter is

begin

  assert is_lite(lite_config_c)
    report "lite_config_c must be an AXI4-Lite configuration"
    severity failure;

  assert full_config_c.address_width = lite_config_c.address_width
    report "Address widths must match"
    severity failure;

  assert full_config_c.data_bus_width_l2 = lite_config_c.data_bus_width_l2
    report "Data bus widths must match"
    severity failure;

  write_side: block is
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_BEAT,
      ST_BEAT_RESP,
      ST_RESP
      );

    type regs_t is
    record
      state: state_t;
      transaction: transaction_t;
      aw_done, w_done: boolean;
      resp: resp_enum_t;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
      end if;
    end process;

    transition: process(r, full_i, lite_i) is
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;
          rin.transaction.valid <= '0';

        when ST_IDLE =>
          if is_valid(full_config_c, full_i.aw) then
            rin.transaction <= transaction(full_config_c, full_i.aw);
            rin.resp <= RESP_OKAY;
            rin.aw_done <= false;
            rin.w_done <= false;
            rin.state <= ST_BEAT;
          end if;

        when ST_BEAT =>
          if is_ready(lite_config_c, lite_i.aw) then
            rin.aw_done <= true;
          end if;
          if is_valid(full_config_c, full_i.w) and is_ready(lite_config_c, lite_i.w) then
            rin.w_done <= true;
          end if;
          if (r.aw_done or is_ready(lite_config_c, lite_i.aw))
            and (r.w_done or (is_valid(full_config_c, full_i.w) and is_ready(lite_config_c, lite_i.w))) then
            rin.state <= ST_BEAT_RESP;
          end if;

        when ST_BEAT_RESP =>
          if is_valid(lite_config_c, lite_i.b) then
            if r.resp = RESP_OKAY then
              rin.resp <= resp(lite_config_c, lite_i.b);
            end if;

            if is_last(full_config_c, r.transaction) then
              rin.state <= ST_RESP;
            else
              rin.transaction <= step(full_config_c, r.transaction);
              rin.aw_done <= false;
              rin.w_done <= false;
              rin.state <= ST_BEAT;
            end if;
          end if;

        when ST_RESP =>
          if is_ready(full_config_c, full_i.b) then
            rin.state <= ST_IDLE;
          end if;
      end case;
    end process;

    full_o.aw <= accept(full_config_c, r.state = ST_IDLE);
    full_o.w <= accept(full_config_c, r.state = ST_BEAT and not r.w_done
                       and is_ready(lite_config_c, lite_i.w));
    full_o.b <= write_response(full_config_c,
                               id => id(full_config_c, r.transaction),
                               user => user(full_config_c, r.transaction),
                               resp => r.resp,
                               valid => r.state = ST_RESP);

    lite_o.aw <= address(lite_config_c,
                         addr => address(full_config_c, r.transaction),
                         prot => prot(full_config_c, r.transaction),
                         valid => r.state = ST_BEAT and not r.aw_done);
    lite_o.w <= write_data(lite_config_c,
                           bytes => bytes(full_config_c, full_i.w),
                           strb => strb(full_config_c, full_i.w),
                           valid => r.state = ST_BEAT and not r.w_done
                           and is_valid(full_config_c, full_i.w));
    lite_o.b <= accept(lite_config_c, r.state = ST_BEAT_RESP);
  end block;

  read_side: block is
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_ADDR,
      ST_DATA
      );

    type regs_t is
    record
      state: state_t;
      transaction: transaction_t;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
      end if;
    end process;

    transition: process(r, full_i, lite_i) is
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;
          rin.transaction.valid <= '0';

        when ST_IDLE =>
          if is_valid(full_config_c, full_i.ar) then
            rin.transaction <= transaction(full_config_c, full_i.ar);
            rin.state <= ST_ADDR;
          end if;

        when ST_ADDR =>
          if is_ready(lite_config_c, lite_i.ar) then
            rin.state <= ST_DATA;
          end if;

        when ST_DATA =>
          if is_valid(lite_config_c, lite_i.r) and is_ready(full_config_c, full_i.r) then
            if is_last(full_config_c, r.transaction) then
              rin.state <= ST_IDLE;
            else
              rin.transaction <= step(full_config_c, r.transaction);
              rin.state <= ST_ADDR;
            end if;
          end if;
      end case;
    end process;

    full_o.ar <= accept(full_config_c, r.state = ST_IDLE);
    full_o.r <= read_data(full_config_c,
                          id => id(full_config_c, r.transaction),
                          bytes => bytes(lite_config_c, lite_i.r),
                          resp => resp(lite_config_c, lite_i.r),
                          user => user(full_config_c, r.transaction),
                          last => is_last(full_config_c, r.transaction),
                          valid => r.state = ST_DATA and is_valid(lite_config_c, lite_i.r));

    lite_o.ar <= address(lite_config_c,
                         addr => address(full_config_c, r.transaction),
                         prot => prot(full_config_c, r.transaction),
                         valid => r.state = ST_ADDR);
    lite_o.r <= accept(lite_config_c, r.state = ST_DATA and is_ready(full_config_c, full_i.r));
  end block;

end architecture;
