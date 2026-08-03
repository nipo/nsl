from crobe.util import crc
import re

print("""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

  procedure assert_equal(ctxt: string;
                         prefix: string;
                         params: crc_params_t;
                         a, b : crc_state_t;
                         sev: severity_level)
  is
    constant as: std_ulogic_vector := crc_spill_vector(params, a);
    constant bs: std_ulogic_vector := crc_spill_vector(params, b);
  begin
    if as /= bs then
      log_info(ctxt&" "&to_string(params, a));
      log_info(ctxt&" "&to_string(params, b));
    end if;
    assert_equal(ctxt, prefix, as, bs, sev);
  end procedure;

begin
""")

for name, info in crc.Crc.db.items():
    pname = re.sub(r'[^a-zA-Z0-9]+', '_', name)
    if not info.order0_at_lsb:
        info = info.order_swapped()
    
    print(f"      test_{pname}: process is")
    print(f"        constant cfg_c : crc_params_t := crc_params(")
    print(f'          poly => x"{info.poly:x}",')
    print(f'          init => x"{info.init:x}",')
    print(f'          complement_input => {str(info.complement_input).lower()},')
    print(f'          complement_state => {str(info.complement_state).lower()},')
    print(f'          byte_bit_order => BIT_ORDER_{"ASCENDING" if info.pop_lsb else "DESCENDING"},')
    print(f'          spill_order => EXP_ORDER_{"ASCENDING" if not info.spill_bitswap else "DESCENDING"},')
    print(f'          byte_order => BYTE_ORDER_{"INCREASING" if info.spill_byte_order else "DECREASING"}')
    print(f"        );")
    print(f'        constant ctxt: string := "{name}";')
    print(f"      begin")
    print(f'        assert_equal(ctxt, "123..",')
    print(f'                     cfg_c,')
    print(f'                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),')
    print(f'                     crc_load(cfg_c, from_hex("{info.calc_bytes(b"123456789").hex()}")),')
    print(f"                     failure")
    print(f"                     );")
    print(f'        assert_equal(ctxt, "has_check",')
    print(f'                     crc_has_constant_check(cfg_c),')
    print(f'                     {str(info.has_valid_state).lower()},')
    print(f"                     failure")
    print(f"                     );")
    print(f'        assert_equal(ctxt, "pre_00",')
    print(f'                     crc_is_pre_zero_transparent(cfg_c),')
    print(f'                     {str(info.is_pre_zero_transparent).lower()},')
    print(f"                     failure")
    print(f"                     );")
    print(f'        assert_equal(ctxt, "pre_ff",')
    print(f'                     crc_is_pre_ones_transparent(cfg_c),')
    print(f'                     {str(info.is_pre_ff_transparent).lower()},')
    print(f"                     failure")
    print(f"                     );")
    print(f'        assert_equal(ctxt, "post_00",')
    print(f'                     crc_is_post_zero_transparent(cfg_c),')
    print(f'                     {str(info.is_post_zero_transparent).lower()},')
    print(f"                     failure")
    print(f"                     );")
    print(f'        assert_equal(ctxt, "post_ff",')
    print(f'                     crc_is_post_ones_transparent(cfg_c),')
    print(f'                     {str(info.is_post_ff_transparent).lower()},')
    print(f"                     failure")
    print(f"                     );")
    print(f'        log_info(ctxt, "OK");')
    print(f'        wait;')
    print(f"      end process;")
    print(f"")

print("""
end;
""")
