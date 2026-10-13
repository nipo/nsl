library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_clocking, work, nsl_smi, nsl_amba, nsl_logic, nsl_io;
use work.flit.all;
use work.gmii.all;
use nsl_bnoc.committed.all;
use nsl_amba.axi4_mm.all;
use nsl_logic.bool.all;

entity gmii_z7_phy is
  generic(
    ipg_c : natural := 96;
    indep_rx_clock_c : boolean := false;
    has_mdio_c : boolean := false;
    phy_addr_c : unsigned(4 downto 0) := (others => '0')
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;
    rx_clock_i : in std_ulogic := '0';

    gmii_tx_i : in gmii_io_group_t;
    gmii_tx_clk_o : out std_ulogic;
    gmii_col_o : out std_ulogic;

    gmii_crs_o : out std_ulogic;
    gmii_rx_clk_o : out std_logic;
    gmii_rx_o : out gmii_io_group_t;
    
    from_mac_o : out committed_req;
    from_mac_i : in committed_ack;

    to_mac_i : in committed_req;
    to_mac_o : out committed_ack;

    smi_i : in nsl_smi.smi.smi_slave_i := (mdc => '1', mdio => '1');
    smi_o : out nsl_smi.smi.smi_slave_o;

    link_up_i : in std_ulogic := '0';
    mdio_resetn : out std_ulogic
    );
end entity;

architecture beh of gmii_z7_phy is

  type regs_t is
  record
    reset: boolean;
    autoneg_enable : boolean;
    full_duplex : boolean;
    speed_1000 : boolean;
    extended_status : boolean;
    autoneg_complete : boolean;
    autoneg_ability : boolean;
    link_up : boolean;
    base_1000_x_full_duplex : boolean;
  end record;

  signal r, rin: regs_t;

  signal s_flit_to_mac : mii_flit_t;

begin

  gen_mdio : if has_mdio_c generate
    signal bus_s: bus_t;
    signal w_value_s, r_value_s, axi_r_value_s : unsigned(15 downto 0);
    signal w_value_msb_s, r_value_msb_s : unsigned(15 downto 0);
    signal w_strobe_s : std_ulogic;
    signal reg_no_s: natural range 0 to 31;

    constant config_c : config_t := config(address_width => 8,
                                           data_bus_width => 32);

    -- Reg 2/3, PHY identifier. Any value but all zeros or all ones.
    constant phy_id_c : unsigned(31 downto 0) := x"f00dd00d";

    function reg0(regs: regs_t) return unsigned
    is
      variable ret: unsigned(15 downto 0) := (others => '0');
    begin
      ret(15) := to_logic(regs.reset);
      ret(12) := to_logic(regs.autoneg_enable);
      ret(8) := to_logic(regs.full_duplex);
      ret(6) := to_logic(regs.speed_1000);
      ret(6) := '1'; -- force to 1Gb/s
      return ret;
    end function;

    function reg1(regs: regs_t) return unsigned
    is
      variable ret: unsigned(15 downto 0) := (others => '0');
    begin
      ret(8) := to_logic(regs.extended_status);
      ret(5) := to_logic(regs.autoneg_complete);
      ret(3) := to_logic(regs.autoneg_ability);
      ret(2) := to_logic(regs.link_up);
      return ret;
    end function;

    function reg15(regs: regs_t) return unsigned
    is
      variable ret: unsigned(15 downto 0) := (others => '0');
    begin
      ret(15) := to_logic(regs.base_1000_x_full_duplex);
      return ret;
    end function;

  begin

    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;
      
      if reset_n_i = '0' then
        r.reset <= true;
        r.autoneg_enable <= true;
        r.full_duplex <= true;
        r.speed_1000 <= true;
        r.extended_status <= true;
        r.autoneg_complete <= false;
        r.autoneg_ability <= true;
        r.base_1000_x_full_duplex <= true;
        r.link_up <= false;
      end if;
    end process;

    transition: process(r, w_strobe_s, w_value_s, reg_no_s, link_up_i) is
    begin
      rin <= r;
      
      if r.reset then
        rin.reset <= false;
      end if;

      if w_strobe_s = '1' then
        case reg_no_s is
          when 0 =>
            rin.reset <= w_value_s(15) = '1';
            
          when others =>
            null;
        end case;
      end if;

      rin.link_up <= to_boolean(link_up_i);
      rin.autoneg_complete <= to_boolean(link_up_i);
    end process;

    smi_slave: nsl_smi.slave.smi_c22_slave_axi_master
      generic map(
        phy_addr_c => phy_addr_c,
        config_c => config_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        smi_i => smi_i,
        smi_o => smi_o,

        regmap_i => bus_s.s,
        regmap_o => bus_s.m
        );

    regmap: nsl_amba.axi4_mm.axi4_mm_lite_regmap
      generic map(
        config_c => config_c,
        reg_count_l2_c => 5
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        axi_i => bus_s.m,
        axi_o => bus_s.s,

        reg_no_o => reg_no_s,
        w_value_o(31 downto 16) => w_value_msb_s,
        w_value_o(15 downto 0) => w_value_s,
        w_strobe_o => w_strobe_s,
        r_value_i(31 downto 16) => r_value_msb_s,
        r_value_i(15 downto 0) => r_value_s
        );

      r_value_msb_s <= (others => '0');

      with reg_no_s select r_value_s <=
        reg0(r) when 0,
        reg1(r) when 1,
        phy_id_c(31 downto 16) when 2,
        phy_id_c(15 downto 0) when 3,
        reg15(r) when 15,
        x"0000" when others;

      mdio_resetn <= not to_logic(r.reset);
        
  end generate;

  no_gen_mdio : if not has_mdio_c generate
  begin
    smi_o.mdio <= nsl_io.io.directed_z;
    mdio_resetn <= '1';
  end generate;

  phy_bridge: block
  begin 
    async_tx_path : if indep_rx_clock_c generate
      signal s_rx_reset_n : std_ulogic;
    begin

      -- reset_n_i belongs to clock_i: assert it at once, release it on
      -- rx_clock_i so the whole tx_path leaves reset on the same edge.
      rx_reset_sync: nsl_clocking.async.async_edge
        port map(
          clock_i => rx_clock_i,
          data_i => reset_n_i,
          data_o => s_rx_reset_n
          );

      tx_path: work.flit.mii_flit_from_committed
        generic map(
          ipg_c => ipg_c
          )
        port map(
          clock_i => rx_clock_i,
          reset_n_i => s_rx_reset_n,

          committed_i => to_mac_i,
          committed_o => to_mac_o,

          packet_o => gmii_crs_o,
          flit_o => s_flit_to_mac,
          ready_i => '1'
          );

      gmii_rx_clk_o <= rx_clock_i;
    end generate;

    sync_tx_path : if not indep_rx_clock_c generate
    begin

      tx_path: work.flit.mii_flit_from_committed
        generic map(
          ipg_c => ipg_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          committed_i => to_mac_i,
          committed_o => to_mac_o,

          packet_o => gmii_crs_o,
          flit_o => s_flit_to_mac,
          ready_i => '1'
          );

      gmii_rx_clk_o <= clock_i;
    end generate;

    gmii_rx_o.data <= s_flit_to_mac.data;
    gmii_rx_o.en <= s_flit_to_mac.valid;
    gmii_rx_o.er <= s_flit_to_mac.error;

    rx_path: work.flit.mii_flit_to_committed
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        valid_i => '1',
        flit_i.data => gmii_tx_i.data,
        flit_i.valid => gmii_tx_i.en,
        flit_i.error => gmii_tx_i.er,

        committed_o => from_mac_o,
        committed_i => from_mac_i
        );

    gmii_col_o <= '0';
    gmii_tx_clk_o <= clock_i;
  end block;
  
end architecture;
