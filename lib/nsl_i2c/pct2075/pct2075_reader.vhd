library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_data, nsl_math, nsl_logic, nsl_bnoc, nsl_i2c, work;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_bnoc.framed_transactor.all;
use nsl_bnoc.framed.all;
use nsl_math.fixed.all;
use work.pct2075.all;

entity pct2075_reader is
  generic(
    i2c_addr_c    : unsigned(6 downto 0) := "0100000";
    irq_backoff_timeout_c : integer := 0;
    temp_threshold_c: real := 0.0
    );
  port(
    reset_n_i   : in std_ulogic;
    clock_i     : in std_ulogic;

    enable_i : in std_ulogic := '1';
    force_i : in std_ulogic := '0';
    busy_o  : out std_ulogic;
    irq_n_i     : in std_ulogic := '1';

    temp_o       : out sfixed(7 downto -3);

    cmd_o  : out nsl_bnoc.framed.framed_req;
    cmd_i  : in  nsl_bnoc.framed.framed_ack;
    rsp_i  : in  nsl_bnoc.framed.framed_req;
    rsp_o  : out nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of pct2075_reader is
  
  type state_t is (
    ST_RESET,
    ST_IDLE,

    ST_TEMP_READ,
    ST_TEMP_WAIT,
    ST_TEMP_CALC,
    ST_TOTS_SET,
    ST_THYS_SET,
    ST_TEMP_READ2
    );

  signal controller_cvalid_s, controller_cready_s, controller_write_s : std_ulogic;
  signal controller_rvalid_s, controller_rready_s : std_ulogic;
  signal controller_addr_s : unsigned(7 downto 0);
  signal controller_wdata_s, controller_rdata_s : byte_string(0 to 1);

  type regs_t is
  record
    state: state_t;
    backoff: integer range 0 to irq_backoff_timeout_c;
    dirty: boolean;
    temperature: sfixed(7 downto -3);
    tots, thys: sfixed(7 downto -1);
  end record;

  signal r, rin : regs_t;
  
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
  
  transition: process(r, enable_i, force_i, irq_n_i,
                      controller_rvalid_s, controller_cready_s,
                      controller_rdata_s) is
  begin
    rin <= r;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.dirty <= true;
        rin.backoff <= 0;

      when ST_IDLE =>
        if force_i = '1' then
          rin.dirty <= true;
        end if;

        if irq_n_i = '0' and r.backoff = 0 then
          rin.dirty <= true;
        end if;

        if r.backoff /= 0 then
          rin.backoff <= r.backoff - 1;
        end if;
        
        if r.dirty and enable_i = '1' then
          rin.state <= ST_TEMP_READ;
        end if;

      when ST_TEMP_READ =>
        if controller_cready_s = '1' then
          rin.state <= ST_TEMP_WAIT;
        end if;

      when ST_TEMP_WAIT =>
        if controller_rvalid_s = '1' then
          rin.state <= ST_TEMP_CALC;
          rin.temperature <= sfixed(from_be(controller_rdata_s)(15 downto 5));
        end if;

      when ST_TEMP_CALC =>
        rin.state <= ST_TOTS_SET;
        rin.tots <= resize(r.temperature + to_sfixed(temp_threshold_c + 0.375, r.temperature'left, r.temperature'right), rin.tots'left, rin.tots'right);
        rin.thys <= resize(r.temperature - to_sfixed(temp_threshold_c - 0.375, r.temperature'left, r.temperature'right), rin.thys'left, rin.thys'right);

      when ST_TOTS_SET =>
        if controller_cready_s = '1' then
          rin.state <= ST_THYS_SET;
        end if;

      when ST_THYS_SET =>
        if controller_cready_s = '1' then
          rin.state <= ST_TEMP_READ2;
        end if;

      when ST_TEMP_READ2 =>
        if controller_cready_s = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    controller_cvalid_s <= '0';
    controller_rready_s <= '1';
    controller_wdata_s <= (others => "--------");
    controller_addr_s <= "--------";
    controller_write_s <= '-';
    busy_o <= to_logic(r.dirty);
    temp_o <= r.temperature;

    case r.state is
      when ST_RESET | ST_IDLE | ST_TEMP_CALC | ST_TEMP_WAIT =>
        null;

      when ST_TEMP_READ | ST_TEMP_READ2 =>
        controller_cvalid_s <= '1';
        controller_write_s <= '0';
        controller_addr_s <= x"00";

      when ST_THYS_SET =>
        controller_cvalid_s <= '1';
        controller_write_s <= '1';
        controller_addr_s <= x"02";
        controller_wdata_s <= to_be(unsigned(to_suv(r.thys)) & "0000000");

      when ST_TOTS_SET =>
        controller_cvalid_s <= '1';
        controller_write_s <= '1';
        controller_addr_s <= x"03";
        controller_wdata_s <= to_be(unsigned(to_suv(r.tots)) & "0000000");
    end case;
  end process;

  controller: nsl_i2c.transactor.framed_addressed_controller
    generic map(
      addr_byte_count_c => 1,
      big_endian_c => false,
      txn_byte_count_max_c => controller_rdata_s'length
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      cmd_i => cmd_i,
      cmd_o => cmd_o,
      rsp_i => rsp_i,
      rsp_o => rsp_o,

      valid_i => controller_cvalid_s,
      ready_o => controller_cready_s,
      saddr_i => i2c_addr_c,
      addr_i => controller_addr_s,
      write_i => controller_write_s,
      wdata_i => controller_wdata_s,
      data_byte_count_i => 2,

      valid_o => controller_rvalid_s,
      ready_i => controller_rready_s,
      rdata_o => controller_rdata_s,
      error_o => open
      );
  
end architecture;
