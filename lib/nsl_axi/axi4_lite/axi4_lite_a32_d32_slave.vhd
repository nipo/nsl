library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi;

entity axi4_lite_a32_d32_slave is
  generic (
    addr_size : natural range 3 to 32
    );
  port (
    aclk: in std_ulogic;
    aresetn: in std_ulogic := '1';

    p_axi_ms: in nsl_axi.axi4_lite.a32_d32_ms;
    p_axi_sm: out nsl_axi.axi4_lite.a32_d32_sm;

    p_addr : out unsigned(addr_size-1 downto 2);

    p_w_data : out std_ulogic_vector(31 downto 0);
    p_w_mask : out std_ulogic_vector(3 downto 0);
    p_w_ready : in std_ulogic := '1';
    p_w_valid : out std_ulogic;

    p_r_data : in std_ulogic_vector(31 downto 0);
    p_r_ready : out std_ulogic;
    p_r_valid : in std_ulogic := '1'
    );
end entity;

architecture rtl of axi4_lite_a32_d32_slave is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WCMD,
    ST_WEXEC,
    ST_WRSP,
    ST_RCMD,
    ST_REXEC,
    ST_RRSP
    );

  type regs_t is
  record
    addr : unsigned(addr_size-1 downto 2);
    data : std_ulogic_vector(31 downto 0);
    mask : std_ulogic_vector(3 downto 0);
    state: state_t;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(aclk, aresetn)
  begin
    if rising_edge(aclk) then
      r <= rin;
    end if;
    if aresetn = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(p_axi_ms, p_r_data, p_r_valid, p_w_ready, r)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if p_axi_ms.awvalid = '1' and p_axi_ms.wvalid = '1' then
          rin.state <= ST_WCMD;
        elsif p_axi_ms.arvalid = '1' then
          rin.state <= ST_RCMD;
        end if;

      when ST_WCMD =>
        if p_axi_ms.awvalid = '1' and p_axi_ms.wvalid = '1' then
          rin.state <= ST_WEXEC;
          rin.data <= p_axi_ms.wdata;
          rin.addr <= unsigned(p_axi_ms.awaddr(rin.addr'range));
          rin.mask <= p_axi_ms.wstrb;
        end if;

      when ST_WEXEC =>
        if p_w_ready = '1' then
          rin.state <= ST_WRSP;
        end if;

      when ST_WRSP =>
        if p_axi_ms.bready = '1' then
          rin.state <= ST_IDLE;
        end if;

      when ST_RCMD =>
        if p_axi_ms.arvalid = '1' then
          rin.addr <= unsigned(p_axi_ms.araddr(rin.addr'range));
          rin.state <= ST_REXEC;
        end if;

      when ST_REXEC =>
        if p_r_valid = '1' then
          rin.state <= ST_RRSP;
          rin.data <= p_r_data;
        end if;

      when ST_RRSP =>
        if p_axi_ms.rready = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    p_addr <= (others => '-');
    p_w_data <= (others => '-');
    p_w_mask <= (others => '-');
    p_w_valid <= '0';
    p_r_ready <= '0';

    p_axi_sm <= nsl_axi.axi4_lite.a32_d32_sm_idle;

    case r.state is
      when ST_WCMD =>
        p_axi_sm.awready <= '1';
        p_axi_sm.wready <= '1';

      when ST_WEXEC =>
        p_addr <= r.addr;
        p_w_valid <= '1';
        p_w_data <= r.data;
        p_w_mask <= r.mask;

      when ST_WRSP =>
        p_axi_sm.bvalid <= '1';
        p_axi_sm.bresp <= "00";

      when ST_RCMD =>
        p_axi_sm.arready <= '1';

      when ST_REXEC =>
        p_addr <= r.addr;
        p_r_ready <= '1';

      when ST_RRSP =>
        p_axi_sm.rvalid <= '1';
        p_axi_sm.rresp <= "00";
        p_axi_sm.rdata <= r.data;

      when others =>
        null;
    end case;
  end process;

end architecture;
