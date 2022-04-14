library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_logic;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

package pcal6524 is

  -- PCAL6524 GPIO extender reflector.
  --
  -- Takes a bit vector and forwards it to the remote enterder ASAP when it
  -- changes. There is no guarantee on delivery latency. It depends on the
  -- internal transactor usage and bus traffic.
  --
  -- If IRQ is available, reads the inputs as long as IRQ is asserted.
  --
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

      -- Forces refresh
      force_i : in std_ulogic := '0';

      busy_o  : out std_ulogic;

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
    drive_strength: integer range 0 to 3;
    output : boolean;
    value : std_ulogic;
    in_inverted : boolean;
    irq : boolean;
    pull_enable: boolean;
    pull_value : std_ulogic;
  end record;

  type pcal6524_pin_config_vector is array(integer range 0 to 23) of pcal6524_pin_config;
  
  -- Spawn a byte string suitable for
  -- nsl_bnoc.framed_transactor.framed_transactor_once for
  -- proper initialization of device.
  function pcal6524_init(saddr: unsigned;
                         config: pcal6524_pin_config_vector) return byte_string;

  constant pcal6524_in          : pcal6524_pin_config := (drive_strength => 0, output => false, in_inverted => false, irq => false, pull_enable => false, pull_value => '0', value => '0');
  constant pcal6524_out0        : pcal6524_pin_config := (drive_strength => 0, output =>  true, in_inverted => false, irq => false, pull_enable => false, pull_value => '0', value => '0');
  constant pcal6524_out0_3      : pcal6524_pin_config := (drive_strength => 3, output =>  true, in_inverted => false, irq => false, pull_enable => false, pull_value => '0', value => '0');
  constant pcal6524_in_irq      : pcal6524_pin_config := (drive_strength => 0, output => false, in_inverted => false, irq =>  true, pull_enable => false, pull_value => '0', value => '0');
  constant pcal6524_in_irq_pu   : pcal6524_pin_config := (drive_strength => 0, output => false, in_inverted => false, irq =>  true, pull_enable =>  true, pull_value => '1', value => '0');
  constant pcal6524_in_irq_pd   : pcal6524_pin_config := (drive_strength => 0, output => false, in_inverted => false, irq =>  true, pull_enable =>  true, pull_value => '0', value => '0');
  constant pcal6524_in_irq_inv  : pcal6524_pin_config := (drive_strength => 0, output => false, in_inverted =>  true, irq =>  true, pull_enable => false, pull_value => '0', value => '0');
  
end package pcal6524;

package body pcal6524 is

  function pcal6524_write_multiple(saddr: unsigned;
                                   reg_addr: byte;
                                   value: std_ulogic_vector) return byte_string
  is
    variable reg: byte_string(1 to 1);
  begin
    reg(1) := reg_addr;

    return nsl_bnoc.framed_transactor.i2c_write(saddr, reg & nsl_data.endian.to_le(unsigned(value)));
  end function;

  function pcal6524_init(saddr: unsigned;
                         config: pcal6524_pin_config_vector) return byte_string
  is
    variable value, in_inverted, hiz, pull_en, pull_val, irq_en : std_ulogic_vector(23 downto 0);
    variable strength : std_ulogic_vector(47 downto 0);
  begin
    for i in 0 to 23
    loop
      value(i) := config(i).value;
      hiz(i) := to_logic(not config(i).output);
      in_inverted(i) := to_logic(config(i).in_inverted);
      pull_en(i) := to_logic(config(i).pull_enable);
      pull_val(i) := config(i).pull_value;
      irq_en(i) := to_logic(config(i).irq);
      strength(i*2+1 downto i*2) := std_ulogic_vector(to_unsigned(config(i).drive_strength, 2));
    end loop;

    return pcal6524_write_multiple(saddr, x"50", pull_val)
      & pcal6524_write_multiple(saddr, x"4c", pull_en)
      & pcal6524_write_multiple(saddr, x"40", strength)
      & pcal6524_write_multiple(saddr, x"08", in_inverted)
      & pcal6524_write_multiple(saddr, x"04", value)
      & pcal6524_write_multiple(saddr, x"0c", hiz)
      & pcal6524_write_multiple(saddr, x"54", irq_en)
      ;    
  end function;
  
end package body pcal6524;
