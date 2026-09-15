library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_logic;
use nsl_amba.apb.all;
use nsl_logic.bool.all;

entity apb_slave_packer is
  generic (
    config_c: config_t
    );
  port (
    paddr : in std_logic_vector(config_c.address_width-1 downto 0);
    pprot : in std_logic_vector(2 downto 0) := (others => '0');
    psel : in std_logic;
    penable : in std_logic;
    pwrite : in std_logic;
    pwdata : in std_logic_vector(8 * 2**config_c.data_bus_width_l2 - 1 downto 0) := (others => '0');
    pstrb : in std_logic_vector(2**config_c.data_bus_width_l2 - 1 downto 0) := (others => '1');
    pready : out std_logic;
    prdata : out std_logic_vector(8 * 2**config_c.data_bus_width_l2 - 1 downto 0);
    pslverr : out std_logic;

    apb_i : in slave_t;
    apb_o : out master_t
    );
end entity;

architecture rtl of apb_slave_packer is

  signal phase_s : phase_t;

begin

  phase_s <= PHASE_ACCESS when penable = '1' else PHASE_SETUP;

  apb_o <= write_transfer(config_c,
                          addr => unsigned(paddr),
                          value => unsigned(pwdata),
                          strb => std_ulogic_vector(pstrb),
                          prot => std_ulogic_vector(pprot),
                          phase => phase_s,
                          valid => psel = '1')
           when pwrite = '1'
           else read_transfer(config_c,
                              addr => unsigned(paddr),
                              prot => std_ulogic_vector(pprot),
                              phase => phase_s,
                              valid => psel = '1');

  pready <= to_logic(is_ready(config_c, apb_i));
  prdata <= std_logic_vector(value(config_c, apb_i));
  pslverr <= to_logic(is_error(config_c, apb_i));

end architecture;
