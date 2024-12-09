library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_mm.all;
use nsl_amba.apb.all;

entity axi4_apb_bridge_dispatch is
  generic (
    axi_config_c : nsl_amba.axi4_mm.config_t;
    apb_config_c : nsl_amba.apb.config_t;
    routing_table_c : nsl_amba.address.address_vector
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    irq_n_o : out std_ulogic;

    axi_i : in nsl_amba.axi4_mm.master_t;
    axi_o : out nsl_amba.axi4_mm.slave_t;
    
    apb_o : out nsl_amba.apb.master_vector(0 to routing_table_c'length-1);
    apb_i : in nsl_amba.apb.slave_vector(0 to routing_table_c'length-1)
    );
end entity;

architecture beh of axi4_apb_bridge_dispatch is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WRITE_CMD,
    ST_WRITE_DATA,
    ST_WRITE_SETUP,
    ST_WRITE_ACCESS,
    ST_WRITE_RSP,
    ST_READ_CMD,
    ST_READ_SETUP,
    ST_READ_ACCESS,
    ST_READ_RSP
    );

  type regs_t is
  record
    state: state_t;
    transaction: nsl_amba.axi4_mm.transaction_t;
    resp: nsl_amba.axi4_mm.resp_enum_t;
    data: nsl_data.bytestream.byte_string(0 to 2**apb_config_c.data_bus_width_l2-1);
    axi_w: nsl_amba.axi4_mm.write_data_t;
    sel_index: natural range 0 to routing_table_c'length-1;
  end record;

  signal r, rin: regs_t;

  alias rt_c: nsl_amba.address.address_vector(0 to routing_table_c'length-1) is routing_table_c;

begin

  assert axi_config_c.address_width = apb_config_c.address_width
    report "AXI and APB Configurations should have same address widths"
    severity failure;

  assert axi_config_c.data_bus_width_l2 = apb_config_c.data_bus_width_l2
    report "AXI and APB Configurations should have same data widths"
    severity failure;

  assert apb_config_c.has_strb
    report "APB Configurations does not feature STRB, partial writes will produce invalid results"
    severity warning;

  assert axi_config_c.user_width = apb_config_c.auser_width
    report "AXI and APB Configurations should have matching user widths"
    severity error;

  assert axi_config_c.user_width = apb_config_c.wuser_width
    report "AXI and APB Configurations should have matching user widths"
    severity error;

  assert axi_config_c.user_width = apb_config_c.ruser_width
    report "AXI and APB Configurations should have matching user widths"
    severity error;

  assert axi_config_c.user_width = apb_config_c.buser_width
    report "AXI and APB Configurations should have matching user widths"
    severity error;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, axi_i, apb_i) is
    variable apb_i_v: nsl_amba.apb.slave_t;
  begin
    rin <= r;

    apb_i_v := apb_i(r.sel_index);
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        rin.resp <= RESP_OKAY;

        if is_valid(axi_config_c, axi_i.ar) then
          rin.state <= ST_READ_CMD;
        end if;

        if is_valid(axi_config_c, axi_i.aw) then
          rin.state <= ST_WRITE_CMD;
        end if;

      when ST_WRITE_CMD =>
        rin.transaction <= transaction(axi_config_c, axi_i.aw);
        rin.sel_index <= nsl_amba.address.routing_table_lookup(
          apb_config_c.address_width, rt_c, address(axi_config_c, axi_i.aw));
        rin.state <= ST_WRITE_DATA;

      when ST_WRITE_DATA =>
        if is_valid(axi_config_c, axi_i.w) then
          rin.axi_w <= axi_i.w;
          rin.state <= ST_WRITE_SETUP;
        end if;

      when ST_WRITE_SETUP =>
        rin.state <= ST_WRITE_ACCESS;

      when ST_WRITE_ACCESS =>
        if is_ready(apb_config_c, apb_i_v) then
          rin.transaction <= step(axi_config_c, r.transaction);

          if is_error(apb_config_c, apb_i_v) then
            rin.resp <= RESP_SLVERR;
          end if;

          if is_last(axi_config_c, r.transaction) then
            rin.state <= ST_WRITE_RSP;
          else
            rin.state <= ST_WRITE_DATA;
          end if;
        end if;

      when ST_WRITE_RSP =>
        if is_ready(axi_config_c, axi_i.b) then
          rin.state <= ST_IDLE;
        end if;

      when ST_READ_CMD =>
        rin.transaction <= transaction(axi_config_c, axi_i.ar);
        rin.sel_index <= nsl_amba.address.routing_table_lookup(
          apb_config_c.address_width, rt_c, address(axi_config_c, axi_i.ar));
        rin.state <= ST_READ_SETUP;
        
      when ST_READ_SETUP =>
        rin.state <= ST_READ_ACCESS;

      when ST_READ_ACCESS =>
        if is_ready(apb_config_c, apb_i_v) then
          if is_error(apb_config_c, apb_i_v) then
            rin.resp <= RESP_SLVERR;
          end if;

          rin.data <= bytes(apb_config_c, apb_i_v);
          rin.state <= ST_READ_RSP;
        end if;

      when ST_READ_RSP =>
        rin.transaction <= step(axi_config_c, r.transaction);
        if is_last(axi_config_c, r.transaction) then
          rin.state <= ST_IDLE;
        else
          rin.state <= ST_READ_SETUP;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    for i in apb_o'range
    loop
      apb_o(i) <= transfer_idle(apb_config_c);
    end loop;

    axi_o.aw <= handshake_defaults(axi_config_c);
    axi_o.w <= handshake_defaults(axi_config_c);
    axi_o.b <= write_response_defaults(axi_config_c);
    axi_o.ar <= handshake_defaults(axi_config_c);
    axi_o.r <= read_data_defaults(axi_config_c);

    case r.state is
      when ST_RESET | ST_IDLE =>
        null;

      when ST_WRITE_CMD =>
        axi_o.aw <= accept(axi_config_c, true);
        
      when ST_WRITE_DATA =>
        axi_o.w <= accept(axi_config_c, true);

      when ST_WRITE_SETUP =>
        apb_o(r.sel_index) <= write_transfer(cfg => apb_config_c,
                                             addr => address(axi_config_c, r.transaction),
                                             bytes => bytes(axi_config_c, r.axi_w),
                                             strb => strb(axi_config_c, r.axi_w),
                                             prot => prot(axi_config_c, r.transaction),
                                             auser => user(axi_config_c, r.transaction),
                                             wuser => user(axi_config_c, r.axi_w),
                                             phase => PHASE_SETUP,
                                             valid => true);

      when ST_WRITE_ACCESS =>
        apb_o(r.sel_index) <= write_transfer(cfg => apb_config_c,
                                             addr => address(axi_config_c, r.transaction),
                                             bytes => bytes(axi_config_c, r.axi_w),
                                             strb => strb(axi_config_c, r.axi_w),
                                             prot => prot(axi_config_c, r.transaction),
                                             auser => user(axi_config_c, r.transaction),
                                             wuser => user(axi_config_c, r.axi_w),
                                             phase => PHASE_ACCESS,
                                             valid => true);

      when ST_WRITE_RSP =>
        axi_o.b <= write_response(axi_config_c,
                                  id => id(axi_config_c, r.transaction),
                                  resp => r.resp,
                                  user => user(axi_config_c, r.transaction),
                                  valid => true);

      when ST_READ_CMD =>
        axi_o.ar <= accept(axi_config_c, true);

      when ST_READ_SETUP =>
        apb_o(r.sel_index) <= read_transfer(cfg => apb_config_c,
                                            addr => address(axi_config_c, r.transaction),
                                            prot => prot(axi_config_c, r.transaction),
                                            auser => user(axi_config_c, r.transaction),
                                            phase => PHASE_SETUP,
                                            valid => true);

      when ST_READ_ACCESS =>
        apb_o(r.sel_index) <= read_transfer(cfg => apb_config_c,
                                            addr => address(axi_config_c, r.transaction),
                                            prot => prot(axi_config_c, r.transaction),
                                            auser => user(axi_config_c, r.transaction),
                                            phase => PHASE_ACCESS,
                                            valid => true);

      when ST_READ_RSP =>
        axi_o.r <= read_data(cfg => axi_config_c,
                             id => id(axi_config_c, r.transaction),
                             bytes => r.data,
                             resp => r.resp,
                             last => is_last(axi_config_c, r.transaction),
                             valid => true);
    end case;      
    
  end process;

  
end architecture;
