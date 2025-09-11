library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_mm.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

entity smi_axi_bridge is
  generic(
    config_c: config_t;
    block_offset_c: integer range 0 to 31-5+1
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    smi_reg_i: in integer range 0 to 31;
    smi_wen_i: in std_ulogic;
    smi_wdata_i: in unsigned(15 downto 0);
    smi_rdata_o: out unsigned(15 downto 0);

    axi_o: out nsl_amba.axi4_mm.master_t;
    axi_i: in nsl_amba.axi4_mm.slave_t
    );
end entity;
    
architecture beh of smi_axi_bridge is

  constant txn_cfg_c: transactor_config_t := transactor_config(config_c, 4);
  constant reg_ah : integer range 0 to 31 := block_offset_c + 0;
  constant reg_al : integer range 0 to 31 := block_offset_c + 1;
  constant reg_dh : integer range 0 to 31 := block_offset_c + 2;
  constant reg_dl : integer range 0 to 31 := block_offset_c + 3;
  constant reg_cmd : integer range 0 to 31 := block_offset_c + 4;
  
  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WRITE,
    ST_READ,
    ST_READ_COMPLETE
    );
  
  type regs_t is
  record
    state: state_t;
    txn: transactor_t;
    ah, al, dh, dl: unsigned(15 downto 0);
  end record;
  
  signal r, rin: regs_t;
  signal status_s : unsigned(15 downto 0);

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

  transition: process(r, smi_reg_i, smi_wen_i, smi_wdata_i, axi_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if smi_wen_i = '1' then
          case smi_reg_i is
            when reg_ah => rin.ah <= smi_wdata_i;
            when reg_al => rin.al <= smi_wdata_i;
            when reg_dh => rin.dh <= smi_wdata_i;
            when reg_dl => rin.dl <= smi_wdata_i;
            when reg_cmd =>
              if smi_wdata_i(0) = '1' then
                rin.txn <= reset(txn_cfg_c, r.txn, r.ah & r.al, to_le(r.dh & r.dl));

                if smi_wdata_i(1) = '1' then
                  rin.state <= ST_READ;
                else
                  rin.state <= ST_WRITE;
                end if;
              end if;
            when others => null;
          end case;
        end if;

      when ST_WRITE =>
        rin.txn <= write_step(txn_cfg_c, r.txn, axi_i.aw, axi_i.w, axi_i.b);
        if is_write_last(txn_cfg_c, r.txn, axi_i.aw, axi_i.w, axi_i.b) then
          rin.state <= ST_IDLE;
        end if;

      when ST_READ =>
        rin.txn <= read_step(txn_cfg_c, r.txn, axi_i.ar, axi_i.r);
        if is_read_last(txn_cfg_c, r.txn, axi_i.ar, axi_i.r) then
          rin.state <= ST_READ_COMPLETE;
        end if;

      when ST_READ_COMPLETE =>
        rin.dh <= from_le(bytes(txn_cfg_c, r.txn))(31 downto 16);
        rin.dl <= from_le(bytes(txn_cfg_c, r.txn))(15 downto 0);
        rin.state <= ST_IDLE;
    end case;
  end process;

  moore: process(r) is
  begin
    axi_o.aw <= address_defaults(config_c);
    axi_o.w <= write_data_defaults(config_c);
    axi_o.b <= handshake_defaults(config_c);
    axi_o.ar <= address_defaults(config_c);
    axi_o.r <= handshake_defaults(config_c);
    status_s <= (others => '0');

    case r.state is
      when ST_RESET | ST_IDLE | ST_READ_COMPLETE =>
        null;

      when ST_WRITE =>
        axi_o.aw <= address(txn_cfg_c, r.txn);
        axi_o.w <= write_data(txn_cfg_c, r.txn);
        axi_o.b <= write_response(txn_cfg_c, r.txn);
        status_s(1) <= '0';
        status_s(0) <= '1';

      when ST_READ =>
        axi_o.ar <= address(txn_cfg_c, r.txn);
        axi_o.r <= read_data(txn_cfg_c, r.txn);
        status_s(1) <= '1';
        status_s(0) <= '1';
    end case;
  end process;

  with smi_reg_i select smi_rdata_o <=
    r.ah when reg_ah,
    r.al when reg_al,
    r.dh when reg_dh,
    r.dl when reg_dl,
    status_s when reg_cmd,
    "----------------" when others;
  
end architecture;
