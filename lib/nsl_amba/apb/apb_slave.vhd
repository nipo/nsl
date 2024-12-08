library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic;
use nsl_amba.apb.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity apb_slave is
  generic (
    config_c: config_t
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic := '1';

    apb_i: in master_t;
    apb_o: out slave_t;

    address_o : out unsigned(config_c.address_width-1 downto config_c.data_bus_width_l2);

    w_data_o : out byte_string(0 to 2**config_c.data_bus_width_l2-1);
    w_mask_o : out std_ulogic_vector(0 to 2**config_c.data_bus_width_l2-1);
    w_ready_i : in std_ulogic := '1';
    w_error_i : in std_ulogic := '0';
    w_valid_o : out std_ulogic;

    r_data_i : in byte_string(0 to 2**config_c.data_bus_width_l2-1);
    r_ready_o : out std_ulogic;
    r_valid_i : in std_ulogic := '1'
    );
end entity;

architecture rtl of apb_slave is

  type regs_t is
  record
    access_phase: boolean;
    write_transaction: boolean;
    serviced_early: boolean;
    werror: boolean;
    rdata: byte_string(0 to 2**config_c.data_bus_width_l2-1);
  end record;

  signal r, rin: regs_t;
  
begin
  
  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.serviced_early <= false;
    end if;
  end process;

  transition: process(r, apb_i, r_data_i, r_valid_i, w_ready_i, w_error_i, r_data_i)
  begin
    rin <= r;

    if is_setup(config_c, apb_i) then
      rin.access_phase <= true;
      if is_write(config_c, apb_i) then
        rin.write_transaction <= true;
        if w_ready_i = '1' then
          rin.serviced_early <= true;
          rin.werror <= w_error_i = '1';
        end if;
      else
        rin.write_transaction <= false;
        if r_valid_i = '1' then
          rin.serviced_early <= true;
          rin.rdata <= r_data_i;
        end if;
      end if;
    elsif is_access(config_c, apb_i) then
      if is_write(config_c, apb_i) then
        if r.serviced_early or w_ready_i = '1' then
          rin.access_phase <= false;
          rin.serviced_early <= false;
        end if;
      else
        if r.serviced_early or r_valid_i = '1' then
          rin.access_phase <= false;
          rin.serviced_early <= false;
        end if;
      end if;
    else
      rin.access_phase <= false;
      rin.serviced_early <= false;
      rin.werror <= false;
      rin.rdata <= (others => dontcare_byte_c);
    end if;
  end process;

  mealy: process(r, apb_i, r_data_i, r_valid_i, w_ready_i, w_error_i, r_data_i) is
  begin
    address_o <= resize(address(config_c, apb_i, config_c.data_bus_width_l2), address_o'length);
    w_data_o <= bytes(config_c, apb_i);
    w_mask_o <= strb(config_c, apb_i);
    w_valid_o <= to_logic(is_setup(config_c, apb_i)
                          and is_write(config_c, apb_i));
    r_ready_o <= to_logic(is_setup(config_c, apb_i)
                          and is_read(config_c, apb_i));

    apb_o <= response_idle(config_c);

    if r.access_phase then
      if not r.write_transaction then
        if r.serviced_early then
          apb_o <= read_response(config_c, bytes => r.rdata, ready => true);
          r_ready_o <= '0';
        else
          apb_o <= read_response(config_c, bytes => r_data_i, ready => r_valid_i = '1');
          r_ready_o <= '1';
        end if;
      else
        if r.serviced_early then
          apb_o <= write_response(config_c, error => r.werror, ready => true);
          w_valid_o <= '0';
        else
          apb_o <= write_response(config_c,
                                  error => w_error_i = '1',
                                  ready => w_ready_i = '1');
          w_valid_o <= '1';
        end if;
      end if;
    end if;
  end process;
  
end architecture;
