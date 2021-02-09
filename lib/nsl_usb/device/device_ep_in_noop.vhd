library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb;
use nsl_usb.sie.all;

entity device_ep_in_noop is
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    transfer_i : in  transfer_cmd;
    transfer_o : out transfer_rsp
    );
end entity;

architecture beh of device_ep_in_noop is
begin

  transfer_o <= TRANSFER_RSP_ERROR;
  
end architecture;
