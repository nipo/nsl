library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight, nsl_axi;

entity axi4_lite_a32_d32_ap is
  generic(
    idr : unsigned(31 downto 0) := X"03000004";
    rom_base : unsigned(31 downto 0)
    );
  port(
    clk_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    dbgen_i : in std_ulogic;
    spiden_i : in std_ulogic;

    dap_i : in nsl_coresight.dapbus.dapbus_m_o;
    dap_o : out nsl_coresight.dapbus.dapbus_m_i;

    mem_o : out nsl_axi.axi4_lite.a32_d32_ms;
    mem_i : in  nsl_axi.axi4_lite.a32_d32_sm
    );
end entity;

architecture beh of axi4_lite_a32_d32_ap is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_READ_CMD,
    ST_READ_RSP,
    ST_WRITE_PREPARE,
    ST_WRITE_CMD,
    ST_WRITE_RSP
    );
  
  type regs_t is
  record
    state : state_t;
    aw_pending, w_pending : boolean;
    error_pending, tar_autoinc : boolean;
    last_enable: std_ulogic;
    addr : std_ulogic_vector(31 downto 0);
    tar  : std_ulogic_vector(31 downto 0);
    data : std_ulogic_vector(31 downto 0);
    csw_size : std_ulogic_vector(2 downto 0);
    csw_inc  : std_ulogic_vector(4 downto 4);
  end record;

  signal r, rin : regs_t;

  constant reg_csw       : std_ulogic_vector(7 downto 2) := "000000";
  constant reg_tar       : std_ulogic_vector(7 downto 2) := "000001";
  constant reg_tarh      : std_ulogic_vector(7 downto 2) := "000010";
  constant reg_drw       : std_ulogic_vector(7 downto 2) := "000011";
  constant reg_bd        : std_ulogic_vector(7 downto 2) := "0001--";
  constant reg_ace_barr  : std_ulogic_vector(7 downto 2) := "111100";
  constant reg_cfg       : std_ulogic_vector(7 downto 2) := "111101";
  constant reg_base      : std_ulogic_vector(7 downto 2) := "111110";
  constant reg_baseh     : std_ulogic_vector(7 downto 2) := "111100";
  constant reg_idr       : std_ulogic_vector(7 downto 2) := "111111";

  constant reg_cfg_value : std_ulogic_vector(31 downto 0) := (
    0 => '0', -- Big endian ?
    1 => '0', -- Large address ?
    2 => '0', -- Large data ?
    others => '-'
    );

  signal drw_increment : integer range 0 to 4;

begin

  regs: process(clk_i, reset_n_i)
  begin
    if rising_edge(clk_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  csw_decode: process(r)
  begin
    drw_increment <= 0;
    if r.csw_inc = "1" then
      case r.csw_size is
        when "000" =>
          drw_increment <= 1;
        when "001" =>
          drw_increment <= 2;
        when "010" =>
          drw_increment <= 4;
        when others =>
          drw_increment <= 0;
      end case;
    end if;
  end process;

  transition: process(r, dbgen_i, spiden_i, dap_i, mem_i, drw_increment)
  begin
    rin <= r;

    rin.last_enable<= dap_i.enable;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if dap_i.sel = '1' and dap_i.enable = '1' and r.last_enable = '0' then
          if dap_i.abort = '1' then
            rin.error_pending <= false;
          elsif dap_i.write = '1' then
            if std_match(dap_i.addr(7 downto 2), reg_csw) then
              rin.csw_size <= dap_i.wdata(rin.csw_size'range);
              rin.csw_inc <= dap_i.wdata(rin.csw_inc'range);
            elsif std_match(dap_i.addr(7 downto 2), reg_tar) then
              rin.tar <= dap_i.wdata;
            elsif std_match(dap_i.addr(7 downto 2), reg_drw) then
              rin.data <= dap_i.wdata;
              rin.state <= ST_WRITE_PREPARE;
              rin.addr <= r.tar;
              rin.tar_autoinc <= true;
            elsif std_match(dap_i.addr(7 downto 2), reg_bd) then
              rin.data <= dap_i.wdata;
              rin.addr <= r.tar(31 downto 4) & dap_i.addr(3 downto 2) & "00";
              rin.state <= ST_WRITE_PREPARE;
              rin.tar_autoinc <= false;
            end if;
          else
            if std_match(dap_i.addr(7 downto 2), reg_csw) then
              rin.data <= (others => '0');
              rin.data(r.csw_size'range) <= r.csw_size;
              rin.data(r.csw_inc'range) <= r.csw_inc;
              rin.data(6) <= dbgen_i;
              rin.data(23) <= spiden_i;
            elsif std_match(dap_i.addr(7 downto 2), reg_tar) then
              rin.data <= r.tar;
            elsif std_match(dap_i.addr(7 downto 2), reg_drw) then
              rin.data <= (others => '-');
              rin.state <= ST_READ_CMD;
              rin.addr <= r.tar;
              rin.tar_autoinc <= true;
            elsif std_match(dap_i.addr(7 downto 2), reg_bd) then
              rin.addr <= r.tar(31 downto 4) & dap_i.addr(3 downto 2) & "00";
              rin.data <= (others => '-');
              rin.state <= ST_READ_CMD;
              rin.tar_autoinc <= false;
            elsif std_match(dap_i.addr(7 downto 2), reg_cfg) then
              rin.data <= reg_cfg_value;
            elsif std_match(dap_i.addr(7 downto 2), reg_base) then
              rin.data <= std_ulogic_vector(rom_base);
            elsif std_match(dap_i.addr(7 downto 2), reg_idr) then
              rin.data <= std_ulogic_vector(idr);
            else
              rin.data <= (others => '-');
            end if;
          end if;
        end if;

      when ST_WRITE_PREPARE =>
        rin.aw_pending <= true;
        rin.w_pending <= true;
        rin.state <= ST_WRITE_CMD;

      when ST_WRITE_CMD =>
        if mem_i.awready = '1' then
          rin.aw_pending <= false;
        end if;
        if mem_i.wready = '1' then
          rin.w_pending <= false;
        end if;
        if not r.w_pending and not r.aw_pending then
          rin.state <= ST_WRITE_RSP;
        end if;

      when ST_WRITE_RSP =>
        if mem_i.bvalid = '1' then
          rin.state <= ST_IDLE;
          if mem_i.bresp /= "00" then
            rin.error_pending <= true;
          elsif r.tar_autoinc then
            rin.tar <= std_ulogic_vector(unsigned(r.addr) + drw_increment);
          end if;
        end if;
        
      when ST_READ_CMD =>
        if mem_i.arready = '1' then
          rin.state <= ST_READ_RSP;
        end if;

      when ST_READ_RSP =>
        if mem_i.rvalid = '1' then
          rin.state <= ST_IDLE;
          if mem_i.rresp /= "00" then
            rin.error_pending <= true;
          elsif r.tar_autoinc then
            rin.tar <= std_ulogic_vector(unsigned(r.addr) + drw_increment);
          end if;
          rin.data <= mem_i.rdata;
        end if;

    end case;
    
  end process;

  moore: process(r)
  begin
    dap_o <= nsl_coresight.dapbus.dapbus_m_i_idle;
    if r.error_pending then
      dap_o.slverr <= '1';
    else
      dap_o.slverr <= '0';
    end if;
    if r.state = ST_IDLE then
      dap_o.ready <= '1';
      dap_o.rdata <= r.data;
    end if;

    mem_o <= nsl_axi.axi4_lite.a32_d32_ms_idle;
    case r.state is
      when ST_WRITE_CMD =>
        if r.aw_pending then
          mem_o.awvalid <= '1';
          mem_o.awaddr <= r.addr;
        end if;
        
        if r.w_pending then
          mem_o.wvalid <= '1';
          case r.csw_size is
            when "000" =>
              mem_o.wstrb <= (others => '0');
              mem_o.wstrb(to_integer(unsigned(r.addr(1 downto 0)))) <= '1';
            when "001" =>
              if r.tar(1) = '0' then
                mem_o.wstrb <= "0011";
              else
                mem_o.wstrb <= "1100";
              end if;
            when "010" =>
              mem_o.wstrb <= "1111";
            when others =>
              mem_o.wstrb <= "0000";
          end case;
          mem_o.wdata <= r.data;
        end if;

      when ST_WRITE_RSP =>
        mem_o.bready <= '1';

      when ST_READ_CMD =>
        mem_o.arvalid <= '1';
        mem_o.araddr <= r.addr;

      when ST_READ_RSP =>
        mem_o.rready <= '1';

      when others =>
        null;
    end case;
        
  end process;
  
end architecture;
