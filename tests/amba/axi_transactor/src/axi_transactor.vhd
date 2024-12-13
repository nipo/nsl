library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_mm.all;
use nsl_data.prbs.all;
use nsl_data.bytestream.all;

entity axi_transactor is
  generic (
    config_c: config_t;
    ctx_length_c : natural := 11
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    done_o : out std_ulogic;
    
    axi_o: out master_t;
    axi_i: in slave_t
    );
end entity;


architecture beh of axi_transactor is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WRITE,
    ST_READ,
    ST_CHECK,
    ST_DONE
    );

  constant check_value_c : byte_string := prbs_byte_string(x"deadbee"&"111", prbs31, ctx_length_c);
  constant txn_cfg_c : transactor_config_t := transactor_config(config_c, check_value_c'length);
  
  type regs_t is
  record
    state: state_t;
    left: natural range 0 to 3;
    txn: transactor_t;
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

  transition: process(r, axi_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        rin.state <= ST_WRITE;
        rin.txn <= reset(txn_cfg_c, r.txn,
                         addr => x"8",
                         bytes => check_value_c);
        rin.left <= 3;

      when ST_WRITE =>
        rin.txn <= write_step(txn_cfg_c, r.txn, axi_i.aw, axi_i.w, axi_i.b,
                              address_rollback => true);
        if is_write_last(txn_cfg_c, r.txn, axi_i.aw, axi_i.w, axi_i.b) then
          rin.state <= ST_READ;
        end if;

      when ST_READ =>
        rin.txn <= read_step(txn_cfg_c, r.txn, axi_i.ar, axi_i.r,
                             address_rollback => true);
        if is_read_last(txn_cfg_c, r.txn, axi_i.ar, axi_i.r) then
          if r.left /= 0 then
            rin.left <= r.left - 1;
            rin.state <= ST_WRITE;
          else
            rin.state <= ST_DONE;
          end if;
        end if;

      when ST_CHECK =>
        assert bytes(txn_cfg_c, r.txn) = check_value_c
          severity failure;
        rin.state <= ST_DONE;

      when ST_DONE =>
        null;
    end case;
  end process;

  moore: process(r) is
  begin
    done_o <= '0';
    axi_o.aw <= address_defaults(config_c);
    axi_o.w <= write_data_defaults(config_c);
    axi_o.b <= handshake_defaults(config_c);
    axi_o.ar <= address_defaults(config_c);
    axi_o.r <= handshake_defaults(config_c);
    
    case r.state is
      when ST_RESET | ST_IDLE | ST_CHECK =>
        null;

      when ST_READ =>
        axi_o.ar <= address(txn_cfg_c, r.txn);
        axi_o.r <= read_data(txn_cfg_c, r.txn);

      when ST_WRITE =>
        axi_o.aw <= address(txn_cfg_c, r.txn);
        axi_o.w <= write_data(txn_cfg_c, r.txn);
        axi_o.b <= write_response(txn_cfg_c, r.txn);

      when ST_DONE =>
        done_o <= '1';
    end case;
  end process;
  
end architecture;
