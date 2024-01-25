library nsl_data;
use nsl_data.bytestream.all;

library work;

package neorv32_init is

  constant neorv32_imem_init : byte_string := work.neorv32_bootrom.init;
  constant neorv32_bootrom_init : byte_string := work.neorv32_bootrom.init;

end package neorv32_init;
