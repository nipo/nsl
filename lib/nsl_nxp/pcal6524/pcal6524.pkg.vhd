library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_logic;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

package pcal6524 is

  -- Use routed_transactor_once for initialization of device
  component pcal6524_driver is
    generic(
      i2c_addr_c    : unsigned(6 downto 0) := "0100000";
      i2c_divisor_c : unsigned(4 downto 0);
      in_supported_c : boolean := true
      );
    port(
      reset_n_i   : in std_ulogic;
      clock_i     : in std_ulogic;

      irq_n_i     : in std_ulogic := '1';

      pin_i       : in std_ulogic_vector(23 downto 0);
      pin_o       : out std_ulogic_vector(23 downto 0);

      cmd_o  : out nsl_bnoc.framed.framed_req;
      cmd_i  : in  nsl_bnoc.framed.framed_ack;
      rsp_i  : in  nsl_bnoc.framed.framed_req;
      rsp_o  : out nsl_bnoc.framed.framed_ack
      );
  end component;

  type pcal6524_pin_config is
  record
    drive_strength: integer range 0 to 1;
    output : boolean;
    inverted : boolean;
    irq : boolean;
    pull_enable: boolean;
    pull_value : std_ulogic;
  end record;

  type pcal6524_pin_config_vector is array(integer range 0 to 23) of pcal6524_pin_config;
  
  function pcal6524_init(saddr: unsigned;
                         config: pcal6524_pin_config_vector) return byte_string;
  
end package pcal6524;

package body pcal6524 is

  function pcal6524_write_multiple(saddr: unsigned;
                                   reg_addr: byte;
                                   value: std_ulogic_vector) return byte_string
  is
    variable reg: byte_string(1 to 1);
  begin
    reg(1) := reg_addr;

    return nsl_bnoc.routed_transactor.i2c_write(saddr, reg & nsl_data.endian.to_le(unsigned(value)));
  end function;

  function pcal6524_init(saddr: unsigned;
                         config: pcal6524_pin_config_vector) return byte_string
  is
    variable inverted, hiz, pull_en, pull_val, irq_en : std_ulogic_vector(23 downto 0);
    variable strength : std_ulogic_vector(47 downto 0);
  begin
    for i in 0 to 23
    loop
      hiz(i) := to_logic(not config(i).output);
      inverted(i) := to_logic(config(i).inverted);
      pull_en(i) := to_logic(config(i).pull_enable);
      pull_val(i) := config(i).pull_value;
      irq_en(i) := to_logic(config(i).irq);
      strength(i*2+1 downto i*2) := std_ulogic_vector(to_unsigned(config(i).drive_strength, 2));
    end loop;

    return pcal6524_write_multiple(saddr, x"50", pull_val)
      & pcal6524_write_multiple(saddr, x"4c", pull_en)
      & pcal6524_write_multiple(saddr, x"40", strength)
      & pcal6524_write_multiple(saddr, x"08", inverted)
      & pcal6524_write_multiple(saddr, x"0c", hiz)
      & pcal6524_write_multiple(saddr, x"54", irq_en)
      ;    
  end function;
  
end package body pcal6524;
