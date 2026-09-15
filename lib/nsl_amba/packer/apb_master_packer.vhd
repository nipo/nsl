library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_logic, nsl_data;
use nsl_amba.apb.all;
use nsl_logic.bool.all;
use nsl_data.bytestream.BYTE_ORDER_DECREASING;

entity apb_master_packer is
  generic (
    config_c: config_t
    );
  port (
    paddr : out std_logic_vector(config_c.address_width-1 downto 0);
    pprot : out std_logic_vector(2 downto 0);
    psel : out std_logic;
    penable : out std_logic;
    pwrite : out std_logic;
    pwdata : out std_logic_vector(8 * 2**config_c.data_bus_width_l2 - 1 downto 0);
    pstrb : out std_logic_vector(2**config_c.data_bus_width_l2 - 1 downto 0);
    pready : in std_logic := '1';
    prdata : in std_logic_vector(8 * 2**config_c.data_bus_width_l2 - 1 downto 0) := (others => '0');
    pslverr : in std_logic := '0';

    apb_o : out slave_t;
    apb_i : in master_t
    );
end entity;

architecture rtl of apb_master_packer is

begin

  paddr <= std_logic_vector(address(config_c, apb_i));
  pprot <= std_logic_vector(prot(config_c, apb_i));
  psel <= to_logic(is_selected(config_c, apb_i));
  penable <= to_logic(is_access(config_c, apb_i));
  pwrite <= to_logic(is_write(config_c, apb_i));
  pwdata <= std_logic_vector(value(config_c, apb_i));
  pstrb <= std_logic_vector(strb(config_c, apb_i, BYTE_ORDER_DECREASING));

  -- A configuration without ready or slverr has no wait state and no error
  -- to report, and the constructor refuses to carry one.
  apb_o <= read_response(config_c,
                         value => unsigned(prdata),
                         error => config_c.has_err and pslverr = '1',
                         ready => not config_c.has_ready or pready = '1');

end architecture;
