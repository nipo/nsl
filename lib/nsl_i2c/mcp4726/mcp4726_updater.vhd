library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_logic, nsl_bnoc, nsl_i2c;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_bnoc.framed_transactor.all;
use nsl_bnoc.framed.all;

entity mcp4726_updater is
  generic(
    i2c_addr_c : unsigned(6 downto 0)
    );
  port(
    reset_n_i   : in std_ulogic;
    clock_i     : in std_ulogic;

    -- allow transactions
    enable_i : in std_ulogic := '1';

    -- Force refresh
    force_i : in std_ulogic := '0';

    valid_i : in std_ulogic := '1';
    ready_o : out std_ulogic;
    value_i : in unsigned(11 downto 0);

    cmd_o  : out nsl_bnoc.framed.framed_req;
    cmd_i  : in  nsl_bnoc.framed.framed_ack;
    rsp_i  : in  nsl_bnoc.framed.framed_req;
    rsp_o  : out nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of mcp4726_updater is
  
  type state_t is (
    ST_RESET,
    ST_IDLE,

    ST_WRITE,
    ST_WAIT
    );

  type regs_t is
  record
    state: state_t;
    dirty: boolean;
    value: unsigned(11 downto 0);
  end record;

  signal r, rin : regs_t;

  signal cmd_valid_s, cmd_ready_s, rsp_valid_s : std_ulogic;
  signal cmd_data_s : byte_string(0 to 1);

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
  
  transition: process(r, enable_i, force_i, value_i, valid_i,
                      rsp_valid_s, cmd_ready_s) is
  begin
    rin <= r;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.value <= x"800";
        rin.dirty <= true;

      when ST_IDLE =>
        if (force_i = '1' or value_i /= r.value) and valid_i = '1' and not r.dirty then
          rin.dirty <= true;
          rin.value <= value_i;
        end if;
        
        if r.dirty and enable_i = '1' then
          rin.state <= ST_WRITE;
        end if;

      when ST_WRITE =>
        if cmd_ready_s = '1' then
          rin.state <= ST_WAIT;
        end if;

      when ST_WAIT =>
        if rsp_valid_s = '1' then
          rin.state <= ST_IDLE;
          rin.dirty <= false;
        end if;
    end case;
  end process;

  ready_o <= not to_logic(r.dirty);

  cmd_valid_s <= to_logic(r.state = ST_WRITE);
  cmd_data_s <= to_be("0000" & r.value);

  controller: nsl_i2c.transactor.framed_addressed_controller
    generic map(
      addr_byte_count_c => 0,
      big_endian_c => false,
      txn_byte_count_max_c => cmd_data_s'length
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
      write_i => '1',
      wdata_i => cmd_data_s,
      data_byte_count_i => cmd_data_s'length,

      valid_o => rsp_valid_s,
      ready_i => '1',
      rdata_o => open,
      error_o => open
      );

end architecture;
