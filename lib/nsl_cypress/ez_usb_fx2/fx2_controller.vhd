library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic;
library nsl_cypress;
use nsl_cypress.ez_usb_fx2.all;

entity fx2_controller is
  generic(
    axi_cfg_c : nsl_amba.axi4_stream.config_t;
    rx_ep_c : fx2_ep_t := FX2_EP2;
    tx_ep_c : fx2_ep_t := FX2_EP6;
    addr_change_delay_c : natural := 0
    );
  port(
    clock_i      : in std_ulogic;
    reset_n_i    : in std_ulogic;

    tx_i  : in nsl_amba.axi4_stream.master_t;
    tx_o  : out nsl_amba.axi4_stream.slave_t;

    rx_o  : out nsl_amba.axi4_stream.master_t;
    rx_i  : in nsl_amba.axi4_stream.slave_t;

    to_fx2_o   : out fx2_i;
    from_fx2_i : in fx2_o;

    addr_change_done_i : in std_ulogic := '1'
    );
end entity;

architecture rtl of fx2_controller is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WAIT_ADDR,
    ST_TX,
    ST_RX_WAIT_FLAG,
    ST_RX
    );

  type regs_t is record
    state : state_t;
    addr  : fx2_addr_t;
    count : natural range 0 to addr_change_delay_c;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, tx_i, rx_i, from_fx2_i, addr_change_done_i)
    variable received_bytes : nsl_data.bytestream.byte_string(0 downto 0);
  begin
    rin <= r;

    to_fx2_o.addr   <= r.addr;
    to_fx2_o.data   <= (others => '-');
    to_fx2_o.wr_n   <= '1';
    to_fx2_o.rd_n   <= '1';
    to_fx2_o.oe_n   <= '1';
    to_fx2_o.pktend <= '1';

    tx_o <= nsl_amba.axi4_stream.accept(axi_cfg_c, false);
    rx_o <= nsl_amba.axi4_stream.transfer_defaults(axi_cfg_c);

    case r.state is
      when ST_RESET =>
        rin.addr  <= get_fifoaddr(tx_ep_c);
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        -- TX has priority. Address defaults to tx_ep_c so full_n is valid.
        if from_fx2_i.full_n = '1' and nsl_amba.axi4_stream.is_valid(axi_cfg_c, tx_i) then
          -- Address already points to tx_ep_c, flag is valid
          rin.state <= ST_TX;
        elsif nsl_amba.axi4_stream.is_ready(axi_cfg_c, rx_i) then
          -- Switch to RX endpoint to check empty_n
          rin.addr  <= get_fifoaddr(rx_ep_c);
          rin.count <= addr_change_delay_c;
          rin.state <= ST_WAIT_ADDR;
        end if;

      when ST_WAIT_ADDR =>
        -- Wait for indexed flags to update after FIFO address is updated
        if r.count /= 0 then
          rin.count <= r.count - 1;
        elsif addr_change_done_i = '1' then
          if r.addr = get_fifoaddr(tx_ep_c) then
            -- Returning to TX endpoint, go to IDLE
            rin.state <= ST_IDLE;
          else
            -- Going to RX endpoint, check empty flag
            rin.state <= ST_RX_WAIT_FLAG;
          end if;
        end if;

      when ST_TX =>
        if from_fx2_i.full_n = '1' and nsl_amba.axi4_stream.is_valid(axi_cfg_c, tx_i) then
          received_bytes := nsl_amba.axi4_stream.bytes(axi_cfg_c, tx_i);
          to_fx2_o.data   <= received_bytes(0);
          to_fx2_o.wr_n   <= '0';
          to_fx2_o.pktend <= nsl_logic.bool.to_logic(
            not nsl_amba.axi4_stream.is_last(axi_cfg_c, tx_i));
          tx_o <= nsl_amba.axi4_stream.accept(axi_cfg_c, true);
        else
          -- No more data to send, go back to idle (address already at tx_ep_c)
          rin.state <= ST_IDLE;
        end if;

      when ST_RX_WAIT_FLAG =>
        -- Enable output, wait one cycle for data to appear
        to_fx2_o.oe_n <= '0';
        rin.state <= ST_RX;

      when ST_RX =>
        to_fx2_o.oe_n <= '0';
        if from_fx2_i.empty_n = '1' and nsl_amba.axi4_stream.is_ready(axi_cfg_c, rx_i) then
          rx_o <= nsl_amba.axi4_stream.transfer(
            cfg   => axi_cfg_c,
            bytes => nsl_data.bytestream.from_suv(from_fx2_i.data),
            last  => false);
          to_fx2_o.rd_n <= '0';
        elsif from_fx2_i.empty_n = '0' then
          -- RX FIFO empty, switch back to TX endpoint for idle
          rin.addr  <= get_fifoaddr(tx_ep_c);
          rin.count <= addr_change_delay_c;
          rin.state <= ST_WAIT_ADDR;
        end if;

    end case;
  end process;

end architecture;
