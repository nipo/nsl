library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb;
use nsl_usb.sie.all;

entity device_ep_in_noop is
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    transaction_i : in  transaction_cmd;
    transaction_o : out transaction_rsp
    );
end entity;

architecture beh of device_ep_in_noop is
begin

  transaction_o <= TRANSACTION_RSP_ERROR;
  
end architecture;
