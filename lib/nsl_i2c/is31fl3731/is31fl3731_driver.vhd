library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, work, nsl_i2c;
use nsl_bnoc.framed.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;
use work.is31fl3731.all;

entity is31fl3731_driver is
  generic(
    i2c_addr_c    : unsigned(6 downto 0) := "1110100";
    led_order_c : is31fl3731_led_vector
    );
  port(
    reset_n_i   : in std_ulogic;
    clock_i     : in std_ulogic;

    enable_i : in std_ulogic := '1';

    -- Forces refresh
    force_i : in std_ulogic := '0';

    busy_o  : out std_ulogic;

    led_i : in byte_string(0 to led_order_c'length-1);

    cmd_o  : out nsl_bnoc.framed.framed_req;
    cmd_i  : in  nsl_bnoc.framed.framed_ack;
    rsp_i  : in  nsl_bnoc.framed.framed_req;
    rsp_o  : out nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of is31fl3731_driver is

  constant order_c: is31fl3731_led_vector(0 to led_order_c'length-1) := led_order_c;

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_PUT_PAGE,
    ST_PUT_LED
    );

  type regs_t is
  record
    state: state_t;

    value: byte_string(0 to order_c'length-1);
    dirty: std_ulogic_vector(0 to order_c'length-1);
    cur: integer range 0 to order_c'length-1;

    addr, data: byte;
  end record;

  signal r, rin : regs_t;

  signal controller_valid_s, controller_ready_s : std_ulogic;
  signal controller_addr_s : unsigned(7 downto 0);
  signal controller_data_s : byte;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.value <= (others => to_byte(0));
      r.dirty <= (others => '1');
      r.cur <= 0;
    end if;
  end process;

  transition: process(r, cmd_i, rsp_i, led_i) is
  begin
    rin <= r;

    if force_i = '1' then
      rin.dirty <= (others => '1');
    end if;

    for i in order_c'range
    loop
      if r.value(i) /= led_i(i) then
        rin.dirty(i) <= '1';
        rin.value(i) <= led_i(i);
      end if;
    end loop;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if enable_i = '1' then
          if r.dirty(r.cur) = '1' then
            rin.state <= ST_PUT_PAGE;
            rin.data <= r.value(r.cur);
            rin.addr <= to_byte(16#24# + order_c(r.cur));
          elsif r.cur /= 0 then
            rin.cur <= r.cur - 1;
          else
            rin.cur <= order_c'length - 1;
          end if;
        end if;

      when ST_PUT_PAGE =>
        if controller_ready_s = '1' then
          rin.state <= ST_PUT_LED;
        end if;

      when ST_PUT_LED =>
        if controller_ready_s = '1' then
          rin.dirty(r.cur) <= '0';
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    case r.state is
      when ST_RESET | ST_IDLE =>
        controller_valid_s <= '0';
        controller_addr_s <= "--------";
        controller_data_s <= "--------";
        busy_o <= '0';

      when ST_PUT_PAGE =>
        controller_valid_s <= '1';
        controller_addr_s <= x"fd";
        controller_data_s <= x"00";
        busy_o <= '1';

      when ST_PUT_LED =>
        controller_valid_s <= '1';
        controller_addr_s <= unsigned(r.addr);
        controller_data_s <= r.data;
        busy_o <= '1';
    end case;
  end process;

  controller: nsl_i2c.transactor.framed_addressed_controller
    generic map(
      addr_byte_count_c => 1,
      big_endian_c => false,
      txn_byte_count_max_c => 1
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      cmd_i => cmd_i,
      cmd_o => cmd_o,
      rsp_i => rsp_i,
      rsp_o => rsp_o,

      valid_i => controller_valid_s,
      ready_o => controller_ready_s,
      saddr_i => i2c_addr_c,
      addr_i => controller_addr_s,
      write_i => '1',
      wdata_i(0) => controller_data_s,
      data_byte_count_i => 1,

      valid_o => open,
      ready_i => '1',
      rdata_o => open,
      error_o => open
      );

end architecture;
