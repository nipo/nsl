library ieee;
use ieee.std_logic_1164.all;

library nsl_smi, nsl_bnoc;

package transactor is

  constant SMI_C45_ADDR      : nsl_bnoc.framed.framed_data_t := "000-----";
  constant SMI_C45_WRITE     : nsl_bnoc.framed.framed_data_t := "001-----";
  constant SMI_C45_READINC   : nsl_bnoc.framed.framed_data_t := "010-----";
  constant SMI_C45_READ      : nsl_bnoc.framed.framed_data_t := "011-----";
  constant SMI_C22_READ      : nsl_bnoc.framed.framed_data_t := "100-----";
  constant SMI_C22_WRITE     : nsl_bnoc.framed.framed_data_t := "101-----";

  constant SMI_STATUS_OK     : nsl_bnoc.framed.framed_data_t := "-------0";
  constant SMI_STATUS_ERROR  : nsl_bnoc.framed.framed_data_t := "-------1";

  -- Command structure:
  -- [C22_READ    | PHYAD] [000 |  ADDR] -> [DATA_H] [DATA_L] [STATUS]
  -- [C22_WRITE   | PHYAD] [000 |  ADDR] [DATA_H] [DATA_L] -> [STATUS]
  -- [C45_ADDR    | PRTAD] [000 | DEVAD] [ADDR_H] [ADDR_L] -> [STATUS]
  -- [C45_WRITE   | PRTAD] [000 | DEVAD] [DATA_H] [DATA_L] -> [STATUS]
  -- [C45_READ    | PRTAD] [000 | DEVAD] -> [DATA_H] [DATA_L] [STATUS]
  -- [C45_READINC | PRTAD] [000 | DEVAD] -> [DATA_H] [DATA_L] [STATUS]
  
  component smi_framed_transactor
    generic(
      clock_freq_c : natural := 150000000;
      mdc_freq_c : natural := 25000000
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      smi_o  : out nsl_smi.smi.smi_master_o;
      smi_i  : in  nsl_smi.smi.smi_master_i;

      cmd_i  : in nsl_bnoc.framed.framed_req;
      cmd_o  : out nsl_bnoc.framed.framed_ack;
      rsp_o  : out nsl_bnoc.framed.framed_req;
      rsp_i  : in nsl_bnoc.framed.framed_ack
      );
  end component;

end package transactor;
