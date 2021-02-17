library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

begin

  prbs9_seek: process
    constant context: log_context := "Seeking";
    variable state : prbs_state(8 downto 0);
    constant init : prbs_state(8 downto 0) := "111100001";
  begin

    for i in 1 to 1024
    loop
      state := prbs_forward(init, prbs9, i);
      state := prbs_backward(state, prbs9, i);
      
      assert_equal(context, "fw/bw " & to_string(i),
                 std_ulogic_vector(state),
                 std_ulogic_vector(init),
                 failure);
    end loop;

    log_info(context, "done");
    wait;
  end process;

  prbs9_test: process
    constant prbs9_ref : byte_string := from_hex("ffc1fbe84c90728be7b3518963ab232302841872aa612f3b51a8e53749fbc9ca0c18532cfd45e39ae6f15db0b61bb4be2a50eae90e9c4b5e5724cca1b759b887ffe07d742648b9c5f3d9a8c4b1d5911101420c39d5b0979d28d4f29ba4fd6465068c2996fea2714df3f82e58db0d5a5f1528f57407ce25af2b12e6d0db2cdcc37ff03e3a13a4dce2f96c54e2d8eac8880021869c6ad8cb4e146af94dd27eb23203c6144b7fd1b8a6797c17aced06adaf0a947aba03e792d7150973e86d16eee13f781f9d09526ef17c362a716c7564448010434e35ec65270ab5fc26693f599901638aa5bf685cd33cbe0bd67683d657054a3ddd8173c9eb8a8439f4360bf7f0");
    constant context: log_context := "PRBS9";

  begin
    
    assert_equal(context, "ours vs ref",
                 prbs9_ref,
                 prbs_byte_string("111111111", prbs9, 256),
                 failure);

    log_info(context, "done");
    wait;
  end process;

  prbs_test: process
    constant prbs15_ref : byte_string := from_hex("55d5ff1f000800068002e001880066802ae01f0808068682e2e1898866e6aacaff17000e800460036801ee804c6035e8170e8e8464636b69ef6ecc2c55ddff19800ae00708028681a2e0798822e6998aeae70f0a8407234299f1aac47f13600de8058e832461db685b6ebb6c736de5ed8b0da745bab33335d5d71f1e88086686aae2ff098006e002c80196806ee02c481df68986e6e2cac99716ee8ecc6455eb7f0f600428035e81f86042a831be94706f642c2b5ddf799822ea998f2ae41f0b48077682a6e1bac87316a5cefb14434f71f424475b72bb65b36b35ef570c3e85d0631c29c9ded6d85edab85b32bb55b37f35e017080e868462e36989eee6cc4a");
    constant context: log_context := "PRBS15";

  begin
    
    assert_equal(context, "ours vs ref",
                 prbs15_ref,
                 prbs_byte_string("101010101010101", prbs15, prbs15_ref'length),
                 failure);

    log_info(context, "done");
    wait;
  end process;
  
end;
