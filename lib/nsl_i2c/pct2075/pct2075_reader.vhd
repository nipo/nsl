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
    period_c : integer := 1e6
    );
  port(
    reset_n_i   : in std_ulogic;
    clock_i     : in std_ulogic;

    enable_i : in std_ulogic := '1';
    force_i : in std_ulogic := '0';
    busy_o  : out std_ulogic;

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
    ST_TEMP_WAIT
    );

  signal cmd_valid_s, cmd_ready_s : std_ulogic;
  signal rsp_valid_s : std_ulogic;
  signal rsp_data_s : byte_string(0 to 1);

  type regs_t is
  record
    state: state_t;
    timeout: integer range 0 to period_c;
    dirty: boolean;
    temperature: sfixed(7 downto -3);
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
  
  transition: process(r, enable_i, force_i,
                      rsp_valid_s, cmd_ready_s,
                      rsp_data_s) is
  begin
    rin <= r;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.dirty <= true;
        rin.timeout <= 0;

      when ST_IDLE =>
        if force_i = '1' or r.timeout = 0 then
          rin.dirty <= true;
        end if;

        if r.timeout /= 0 then
          rin.timeout <= r.timeout - 1;
        end if;
        
        if r.dirty and enable_i = '1' then
          rin.timeout <= period_c;
          rin.state <= ST_TEMP_READ;
        end if;

      when ST_TEMP_READ =>
        if cmd_ready_s = '1' then
          rin.state <= ST_TEMP_WAIT;
        end if;

      when ST_TEMP_WAIT =>
        if rsp_valid_s = '1' then
          rin.state <= ST_IDLE;
          rin.dirty <= false;
          rin.temperature <= sfixed(from_be(rsp_data_s)(15 downto 5));
        end if;
    end case;
  end process;

  busy_o <= to_logic(r.dirty);
  temp_o <= r.temperature;
  cmd_valid_s <= to_logic(r.state = ST_TEMP_READ);

  controller: nsl_i2c.transactor.framed_addressed_controller
    generic map(
      addr_byte_count_c => 1,
      big_endian_c => false,
      txn_byte_count_max_c => rsp_data_s'length
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      cmd_i => cmd_i,
      cmd_o => cmd_o,
      rsp_i => rsp_i,
      rsp_o => rsp_o,

      valid_i => cmd_valid_s,
      ready_o => cmd_ready_s,
      saddr_i => i2c_addr_c,
      addr_i => x"00",
      write_i => '0',
      wdata_i => (others => x"00"),
      data_byte_count_i => 2,

      valid_o => rsp_valid_s,
      ready_i => '1',
      rdata_o => rsp_data_s,
      error_o => open
      );
  
end architecture;
