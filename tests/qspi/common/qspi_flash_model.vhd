library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_test_support.all;

-- Expectations are latched at CS assertion. The model deliberately knows
-- nothing about the framed command encoding or the controller state machine.
entity qspi_flash_model is
  port(
    cs_n_i, sck_i: in std_ulogic;
    dq_i, enable_i: in std_ulogic_vector(3 downto 0);
    dq_o: out std_ulogic_vector(3 downto 0);
    opcode_i: in std_ulogic_vector(7 downto 0);
    address_i: in unsigned(31 downto 0);
    address_bytes_i: in positive;
    address_lanes_i, data_lanes_i: in positive;
    dummy_cycles_i: in natural;
    data_bytes_i: in positive;
    half_period_i: in time;
    completed_o: out natural
    );
end entity;

architecture behavioral of qspi_flash_model is
begin
  flash: process
    variable address_v, received_address_v: unsigned(31 downto 0);
    variable opcode_v, received_v, data_v: std_ulogic_vector(7 downto 0);
    variable address_bytes_v, address_lanes_v, data_lanes_v, data_bytes_v: positive;
    variable dummy_v, count_v: natural := 0;
    variable half_period_v, edge_v: time;

    procedure rise is
    begin
      wait on sck_i, cs_n_i until sck_i = '1' or cs_n_i = '1';
      assert cs_n_i = '0' report "Flash: CS released before expected transfer end" severity failure;
      assert now - edge_v >= half_period_v report "Flash: SCK low/setup period too short" severity failure;
      edge_v := now;
    end procedure;

    procedure fall is
    begin
      wait on sck_i, cs_n_i until sck_i = '0' or cs_n_i = '1';
      assert cs_n_i = '0' report "Flash: CS released during SCK high phase" severity failure;
      assert now - edge_v = half_period_v report "Flash: SCK high period differs from divider" severity failure;
      edge_v := now;
    end procedure;

    procedure receive_byte(lanes: positive; variable value: out std_ulogic_vector(7 downto 0)) is
      variable shift_v: std_ulogic_vector(7 downto 0) := (others => '0');
    begin
      for i in 0 to 8 / lanes - 1 loop
        rise;
        if lanes = 1 then
          assert enable_i = "1101" and dq_i(3 downto 2) = "11"
            report "Flash: x1 TX must drive DQ0 and hold WP/HOLD high" severity failure;
          shift_v := shift_v(6 downto 0) & dq_i(0);
        else
          assert enable_i = "1111" report "Flash: x4 TX must drive all DQ" severity failure;
          shift_v := shift_v(3 downto 0) & dq_i;
        end if;
        fall;
      end loop;
      value := shift_v;
    end procedure;
  begin
    dq_o <= (others => '1');
    completed_o <= 0;
    loop
      wait until falling_edge(cs_n_i);
      assert sck_i = '0' report "Flash: mode 0 requires idle SCK low" severity failure;
      address_v := address_i;
      opcode_v := opcode_i;
      address_bytes_v := address_bytes_i;
      address_lanes_v := address_lanes_i;
      data_lanes_v := data_lanes_i;
      dummy_v := dummy_cycles_i;
      data_bytes_v := data_bytes_i;
      half_period_v := half_period_i;
      edge_v := now;
      assert address_bytes_v = 3 or address_bytes_v = 4 severity failure;
      assert address_lanes_v = 1 or address_lanes_v = 4 severity failure;
      assert data_lanes_v = 1 or data_lanes_v = 4 severity failure;
      receive_byte(1, received_v);
      assert received_v = opcode_v report "Flash: wrong opcode or serial bit ordering" severity failure;
      assert opcode_v = x"03" or opcode_v = x"0b" or opcode_v = x"6b" or opcode_v = x"eb"
        report "Flash: unexpected read command" severity failure;
      received_address_v := (others => '0');
      for i in 1 to address_bytes_v loop
        receive_byte(address_lanes_v, received_v);
        received_address_v := received_address_v(23 downto 0) & unsigned(received_v);
      end loop;
      assert received_address_v = address_v report "Flash: wrong address, address width, or nibble ordering" severity failure;
      for i in 1 to dummy_v loop
        rise;
        assert enable_i = "0000" report "Flash: dummy clocks must release all DQ" severity failure;
        fall;
      end loop;
      for i in 0 to data_bytes_v - 1 loop
        data_v := memory_byte(address_v + i);
        for j in 0 to 8 / data_lanes_v - 1 loop
          if data_lanes_v = 1 then
            dq_o <= "11" & data_v(7) & '1';
            data_v := data_v(6 downto 0) & '0';
          else
            dq_o <= data_v(7 downto 4);
            data_v := data_v(3 downto 0) & x"0";
          end if;
          rise;
          if data_lanes_v = 1 then
            assert enable_i = "1100" and dq_i(3 downto 2) = "11"
              report "Flash: x1 RX must release DQ0/DQ1 and hold WP/HOLD high" severity failure;
          else
            assert enable_i = "0000" report "Flash: controller drives DQ during RX" severity failure;
          end if;
          fall;
        end loop;
      end loop;
      wait on cs_n_i, sck_i until cs_n_i = '1' or sck_i = '1';
      assert cs_n_i = '1' and sck_i = '0' report "Flash: extra clock after expected data" severity failure;
      dq_o <= (others => '1');
      count_v := count_v + 1;
      completed_o <= count_v;
    end loop;
  end process;
end architecture;
