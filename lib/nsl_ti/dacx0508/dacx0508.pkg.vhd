library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

package dacx0508 is

  -- Followed by 2 words (big endian) of current value
  -- 3 LSBs of command byte are the target channel number
  -- [CUR_SET(x)] [VAL_8_15] [VAL_0_7]
  -- Overrides target value to match current
  constant DACX0508_CMD_CURRENT_SET   : nsl_bnoc.framed.framed_data_t := "00000---";
  -- Followed by 2 words (big endian) of target value
  -- [TGT_SET] [VAL_8_15] [VAL_0_7]
  constant DACX0508_CMD_TARGET_SET    : nsl_bnoc.framed.framed_data_t := "00001000";
  -- Followed by 4 words (big endian) of fractional increment
  -- [TGT_SET] [VAL_8_15] [VAL_0_7] [VAL_-8_-1] [VAL_-16_-9]
  constant DACX0508_CMD_INCREMENT_SET : nsl_bnoc.framed.framed_data_t := "00001001";

  -- This component generates slopes for DACx0508 connected through a SPI
  -- master transactor.
  --
  -- As long as internal target value does not match internal current
  -- value, increment is added to current value on each clock_i cycle,
  -- and SPI write transaction to DAC is generated as often as
  -- possible.
  component dacx0508_slope_controller is
    generic(
      -- DAC actual resolution (DAC80508: 16, DAC70508: 14, DAC60508: 12)
      dac_resolution_c : integer range 12 to 16 := 16;
      -- Increment register span
      increment_msb_c : integer range 0 to 15 := 7;
      increment_lsb_c : integer range -16 to 0 := -8
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      div_i       : in unsigned(4 downto 0);
      cs_id_i     : in unsigned(2 downto 0);

      slave_cmd_i : in  nsl_bnoc.framed.framed_req;
      slave_cmd_o : out nsl_bnoc.framed.framed_ack;
      slave_rsp_o : out nsl_bnoc.framed.framed_req;
      slave_rsp_i : in  nsl_bnoc.framed.framed_ack;

      master_cmd_o : out nsl_bnoc.framed.framed_req;
      master_cmd_i : in  nsl_bnoc.framed.framed_ack;
      master_rsp_i : in  nsl_bnoc.framed.framed_req;
      master_rsp_o : out nsl_bnoc.framed.framed_ack
      );
  end component;

end package dacx0508;
