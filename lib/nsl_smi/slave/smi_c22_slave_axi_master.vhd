library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_data, work, nsl_amba, nsl_io;
use nsl_clocking.async.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_amba.axi4_mm.all;
use work.smi.all;

entity smi_c22_slave_axi_master is
  generic (
    phy_addr_c      : unsigned(4 downto 0);
    config_c        : config_t
    );
  port (
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    smi_i           : in smi_slave_i;
    smi_o           : out smi_slave_o;

    regmap_i        : in slave_t;
    regmap_o        : out master_t
    );
end entity smi_c22_slave_axi_master;

architecture rtl of smi_c22_slave_axi_master is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_READ_TX_INFO,
    ST_DECISION,

    ST_WAIT_DONE,

    ST_READ_AXI,
    ST_READ_WAIT,
    ST_READ_DATA,

    ST_WRITE_WAIT,
    ST_WRITE_DATA,
    ST_WRITE_PREPARE,
    ST_WRITE_AXI
    );
  
  type regs_t is record
    state: state_t;
    mdio_last: std_ulogic;
    tx_info: std_ulogic_vector(11 downto 0);
    left: integer range 0 to 64;
    data: std_ulogic_vector(15 downto 0);
    txn: transactor_t;
    read_timeout: boolean;
  end record;
  
  constant txn_cfg_c : transactor_config_t := transactor_config(config_c, 4);

  signal rin, r: regs_t;

  signal mdc_rising_s, mdc_falling_s, mdio_s: std_ulogic;

begin

  mdc_sampler: nsl_clocking.async.async_input
    port map(
      clock_i     => clock_i,
      reset_n_i   => reset_n_i,
      data_i      => smi_i.mdc,
      rising_o    => mdc_rising_s,
      falling_o   => mdc_falling_s
      );

  mdio_sampler: nsl_clocking.async.async_input
    port map(
      clock_i     => clock_i,
      reset_n_i   => reset_n_i,
      data_i      => smi_i.mdio,
      data_o      => mdio_s
      );

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;
  
  transition: process(r, mdc_rising_s, mdc_falling_s, mdio_s, regmap_i)
  begin
    rin <= r;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if mdc_rising_s = '1' then
          rin.mdio_last <= mdio_s;
          if r.mdio_last = '0' and mdio_s = '1' then
            rin.left <= 11;
            rin.tx_info <= (others => '-');
            rin.state <= ST_READ_TX_INFO;
          end if;
        end if;

      when ST_READ_TX_INFO => 
        if mdc_rising_s = '1' then
          rin.tx_info <= r.tx_info(10 downto 0) & mdio_s;
          if r.left = 0 then
            rin.state <= ST_DECISION;
          else
            rin.left <= r.left - 1;
          end if;
        end if;
        
      when ST_DECISION =>
        if r.tx_info(9 downto 5) /= std_ulogic_vector(phy_addr_c) then
          rin.state <= ST_WAIT_DONE;
          rin.left <= 18;
        else
          rin.left <= 1;
          if r.tx_info(11 downto 10) = read_opcode_c then
            rin.read_timeout <= false;
            rin.state <= ST_READ_AXI;
            rin.txn <= reset(txn_cfg_c, r.txn, unsigned(r.tx_info(4 downto 0)) & "00");
          elsif r.tx_info(11 downto 10) = write_opcode_c then
            rin.state <= ST_WRITE_WAIT;
          else
            rin.state <= ST_WAIT_DONE;
            rin.left <= 18;
          end if;
        end if;

      when ST_READ_AXI => 
        if mdc_rising_s = '1' then
          if r.left /= 0 then
            rin.left <= r.left - 1;
          else
            rin.read_timeout <= true;
          end if;
        end if;
          
        rin.txn <= read_step(txn_cfg_c, r.txn, regmap_i.ar, regmap_i.r);
        if is_read_last(txn_cfg_c, r.txn, regmap_i.ar, regmap_i.r) then
          if r.read_timeout
            or resp(txn_cfg_c, r.txn) = RESP_DECERR
            or resp(txn_cfg_c, r.txn) = RESP_SLVERR then
            rin.state <= ST_WAIT_DONE;
            rin.left <= r.left + 16;
          else
            rin.state <= ST_READ_WAIT;
          end if;
        end if;

      when ST_READ_WAIT =>
        if mdc_rising_s = '1' then
          if r.left /= 0 then
            rin.left <= r.left - 1;
          else
            rin.state <= ST_READ_DATA;
            rin.data <= std_ulogic_vector(from_le(bytes(txn_cfg_c, r.txn))(15 downto 0));
            rin.left <= 15;
          end if;
        end if;

      when ST_READ_DATA => 
        if mdc_rising_s = '1' then
          if r.left = 0 then
            rin.state <= ST_IDLE;
          else
            rin.left <= r.left - 1;
            rin.data <= r.data(14 downto 0) & '-';
          end if;
        end if;

      when ST_WRITE_WAIT => 
        if mdc_rising_s = '1' then
          if r.left = 0 then
            rin.state <= ST_WRITE_DATA;
            rin.left <= 15;
          else
            rin.left <= r.left - 1;
          end if;
        end if;

      when ST_WRITE_DATA =>
        if mdc_rising_s = '1' then
          rin.data <= r.data(14 downto 0) & mdio_s;
          if r.left = 0 then
            rin.state <= ST_WRITE_PREPARE;
          else
            rin.left <= r.left - 1;
          end if; 
        end if;

      when ST_WRITE_PREPARE =>
        rin.txn <= reset(txn_cfg_c, r.txn, unsigned(r.tx_info(4 downto 0)) & "00", to_le(unsigned(r.data)));
        rin.state <= ST_WRITE_AXI;
        
      when ST_WRITE_AXI =>
        rin.txn <= write_step(txn_cfg_c, r.txn, regmap_i.aw, regmap_i.w, regmap_i.b);
        if is_write_last(txn_cfg_c, r.txn, regmap_i.aw, regmap_i.w, regmap_i.b) then
          rin.state <= ST_IDLE;
        end if;

      when ST_WAIT_DONE => 
        if mdc_rising_s = '1' then
          if r.left /= 0 then
            rin.left <= r.left - 1;
          else
            rin.state <= ST_IDLE;
          end if;
        end if;
    end case ;
  end process;
  
  fsm_moore_proc: process(r)
  begin
    smi_o.mdio <= nsl_io.io.directed_z;
    regmap_o.aw <= address_defaults(config_c);
    regmap_o.w <= write_data_defaults(config_c);
    regmap_o.b <= handshake_defaults(config_c);
    regmap_o.ar <= address_defaults(config_c);
    regmap_o.r <= handshake_defaults(config_c);

    case r.state is
      when ST_READ_AXI =>
        regmap_o.ar <= address(txn_cfg_c, r.txn);
        regmap_o.r <= read_data(txn_cfg_c, r.txn);

      when ST_READ_WAIT =>
        smi_o.mdio <= nsl_io.io.to_directed('0');

      when ST_READ_DATA =>
        smi_o.mdio <= nsl_io.io.to_directed(r.data(15));

      when ST_WRITE_AXI => 
        regmap_o.aw <= address(txn_cfg_c, r.txn);
        regmap_o.w <= write_data(txn_cfg_c, r.txn);
        regmap_o.b <= write_response(txn_cfg_c, r.txn);

      when others =>
        null;
    end case ;
  end process;

end architecture;
