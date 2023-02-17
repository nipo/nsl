library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, work;
use work.jtag.all;
use nsl_io.io.all;

entity jtag_ate_pin_driver is
  generic(
    use_rtck_c: boolean := false
    );
  port(
    enable_i: in std_ulogic := '1';

    ate_i: in jtag_ate_o;
    ate_o: out jtag_ate_i;

    trst_io: inout std_logic;
    tdi_io: inout std_logic;
    tck_io: inout std_logic;
    tms_io: inout std_logic;
    tdo_i: in std_logic;
    rtck_i: in std_logic := '0'
    );
end entity;

architecture beh of jtag_ate_pin_driver is

begin

  trst_io <= ate_i.trst.v when ate_i.trst.en = '1' and enable_i = '1' else 'Z';
  tdi_io <= ate_i.tdi.v when ate_i.tdi.en = '1' and enable_i = '1' else 'Z';
  tck_io <= ate_i.tck.v when ate_i.tck.en = '1' and enable_i = '1' else 'Z';
  tms_io <= ate_i.tms.v when ate_i.tms.en = '1' and enable_i = '1' else 'Z';
  ate_o.rtck <= rtck_i when use_rtck_c else ate_i.tck.v;
  ate_o.tdo <= tdo_i;

end architecture;
  
