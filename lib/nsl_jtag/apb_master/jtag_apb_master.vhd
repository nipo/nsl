library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_clocking, nsl_jtag, nsl_data, nsl_logic;
use nsl_amba.apb.all;
use nsl_jtag.apb_master.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;

entity jtag_apb_master is
  generic(
    config_c : nsl_amba.apb.config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    tck_i : in std_ulogic;
    tdi_i : in std_ulogic;
    tdo_o : out std_ulogic;
    selected_i : in std_ulogic;
    capture_i : in std_ulogic;
    shift_i : in std_ulogic;
    update_i : in std_ulogic;

    apb_o : out nsl_amba.apb.master_t;
    apb_i : in nsl_amba.apb.slave_t
    );
end entity;

architecture beh of jtag_apb_master is

  constant width_c : natural := register_width(config_c);
  constant address_width_c : natural := config_c.address_width;
  constant data_width_c : natural := 8 * 2 ** config_c.data_bus_width_l2;

  -- TCK domain. An operation is pending while req differs from the
  -- acknowledge seen back.
  signal shreg_s : std_ulogic_vector(width_c-1 downto 0) := (others => '0');
  signal req_s : std_ulogic := '0';
  -- Command, only read by the bus domain while an operation is
  -- pending, its timing toward it is ignored.
  signal tig_static_reg_write_s : std_ulogic := '0';
  signal tig_static_reg_address_s : unsigned(address_width_c-1 downto 0) := (others => '0');
  signal tig_static_reg_wdata_s : unsigned(data_width_c-1 downto 0) := (others => '0');
  signal ack_tck_s : std_ulogic;
  -- Done was captured by the scan: its command is taken.
  signal taken_s : boolean := false;

  -- Bus domain.
  type state_t is (ST_IDLE, ST_SETUP, ST_ACCESS);

  type regs_t is
  record
    state : state_t;
    ack : std_ulogic;
  end record;

  signal r, rin : regs_t;
  -- Outcome, only changing while an operation is pending: the TCK
  -- domain reads it once the acknowledge is back, its timing toward it
  -- is ignored.
  signal tig_static_reg_error_s : std_ulogic := '0';
  signal tig_static_reg_rdata_s : unsigned(data_width_c-1 downto 0) := (others => '0');
  signal req_bus_s : std_ulogic;

begin

  tck_side: process(tck_i) is
    variable outcome : std_ulogic_vector(width_c-1 downto 0);
    variable command : std_ulogic_vector(width_c-1 downto 0);
    variable done : boolean;
  begin
    if rising_edge(tck_i) then
      done := req_s = ack_tck_s;

      if selected_i = '1' then
        if shift_i = '1' then
          shreg_s <= tdi_i & shreg_s(width_c-1 downto 1);
        end if;

        if capture_i = '1' then
          outcome := (others => '0');
          outcome(7 downto 0) := sync_c;
          if done then
            outcome(8) := '1';
          end if;
          outcome(9) := tig_static_reg_error_s;
          outcome(10 + data_width_c - 1 downto 10) := std_ulogic_vector(tig_static_reg_rdata_s);
          shreg_s <= outcome;
          taken_s <= done;
        end if;

        if update_i = '1' and taken_s then
          taken_s <= false;
          command := shreg_s;
          if command(1 downto 0) = op_read_c or command(1 downto 0) = op_write_c then
            tig_static_reg_write_s <= command(1);
            tig_static_reg_address_s <= unsigned(command(2 + address_width_c - 1 downto 2));
            tig_static_reg_wdata_s <= unsigned(command(2 + address_width_c + data_width_c - 1 downto 2 + address_width_c));
            req_s <= not req_s;
          end if;
        end if;
      end if;
    end if;
  end process;

  tdo_o <= shreg_s(0);

  ack_sync: nsl_clocking.async.async_input
    port map(
      clock_i => tck_i,
      reset_n_i => '1',
      data_i => r.ack,
      data_o => ack_tck_s
      );

  req_sync: nsl_clocking.async.async_input
    port map(
      clock_i => clock_i,
      reset_n_i => '1',
      data_i => req_s,
      data_o => req_bus_s
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
      if r.state = ST_ACCESS and is_ready(config_c, apb_i) then
        tig_static_reg_error_s <= to_logic(is_error(config_c, apb_i));
        if tig_static_reg_write_s = '0' then
          tig_static_reg_rdata_s <= value(config_c, apb_i, ENDIAN_LITTLE);
        end if;
      end if;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_IDLE;
      -- Drops the operation pending, if any.
      r.ack <= req_bus_s;
    end if;
  end process;

  transition: process(r, req_bus_s, apb_i) is
  begin
    rin <= r;

    case r.state is
      when ST_IDLE =>
        if req_bus_s /= r.ack then
          rin.state <= ST_SETUP;
        end if;

      when ST_SETUP =>
        rin.state <= ST_ACCESS;

      when ST_ACCESS =>
        if is_ready(config_c, apb_i) then
          rin.state <= ST_IDLE;
          rin.ack <= req_bus_s;
        end if;
    end case;
  end process;

  moore: process(r, tig_static_reg_write_s, tig_static_reg_address_s, tig_static_reg_wdata_s) is
    variable phase : phase_t;
  begin
    phase := PHASE_SETUP;
    if r.state = ST_ACCESS then
      phase := PHASE_ACCESS;
    end if;

    if r.state = ST_IDLE then
      apb_o <= transfer_idle(config_c);
    elsif tig_static_reg_write_s = '1' then
      apb_o <= write_transfer(config_c,
                              addr => tig_static_reg_address_s,
                              value => tig_static_reg_wdata_s,
                              endian => ENDIAN_LITTLE,
                              phase => phase);
    else
      apb_o <= read_transfer(config_c,
                             addr => tig_static_reg_address_s,
                             phase => phase);
    end if;
  end process;

end architecture;
