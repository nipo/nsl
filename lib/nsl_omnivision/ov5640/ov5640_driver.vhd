library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_i2c, nsl_math;
use nsl_data.bytestream.all;

entity ov5640_driver is
  generic(
    clock_i_hz_c : natural;
    i2c_saddr_c : unsigned(7 downto 1) := "0111100";
    width_c : positive range 1 to 640 := 640;
    height_c : positive range 1 to 480 := 480
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    i2c_divisor_i : in unsigned(4 downto 0);
    cmd_o : out nsl_bnoc.framed.framed_req;
    cmd_i : in nsl_bnoc.framed.framed_ack;
    rsp_i : in nsl_bnoc.framed.framed_req;
    rsp_o : out nsl_bnoc.framed.framed_ack;

    test_pattern_i : in std_ulogic := '0';

    sensor_reset_n_o : out std_ulogic;
    sensor_power_down_o : out std_ulogic;

    ready_o : out std_ulogic
    );
end entity;

architecture beh of ov5640_driver is

  -- Register address, then value.  An entry at address ffff is a
  -- pause, see pause_cycles_c.
  subtype entry_t is std_ulogic_vector(23 downto 0);
  type entry_vector is array(natural range <>) of entry_t;

  constant delay_addr_c : std_ulogic_vector(15 downto 0) := x"ffff";

  -- Vendor setup for VGA YUV422 from the full array, binned.
  constant vga_c : entry_vector := (
    x"310311", x"300882", x"ffff00", x"300842", x"310303", x"3017ff",
    x"3018ff", x"30341a", x"303511", x"30366a", x"303714", x"310801",
    x"303b1c", x"303d30", x"363036", x"36310e", x"3632e2", x"363312",
    x"3621e0", x"3704a0", x"37035a", x"371578", x"371701", x"370b60",
    x"37051a", x"390502", x"390610", x"39010a", x"373112", x"360008",
    x"360133", x"302d60", x"362052", x"371b20", x"471c50", x"3a1343",
    x"3a1800", x"3a19f8", x"363513", x"363603", x"363440", x"362201",
    x"3c0134", x"3c0428", x"3c0598", x"3c0600", x"3c0708", x"3c0800",
    x"3c091c", x"3c0a9c", x"3c0b40", x"382041", x"382107", x"381431",
    x"381531", x"380000", x"380100", x"380200", x"380304", x"38040a",
    x"38053f", x"380607", x"38079b", x"380802", x"380980", x"380a01",
    x"380be0", x"380c07", x"380d68", x"380e03", x"380fd8", x"381000",
    x"381110", x"381200", x"381306", x"361800", x"361229", x"370864",
    x"370952", x"370c03", x"3a0203", x"3a03d8", x"3a0801", x"3a0927",
    x"3a0a00", x"3a0bf6", x"3a0e03", x"3a0d04", x"3a1403", x"3a15d8",
    x"400102", x"400402", x"300000", x"30021c", x"3004ff", x"3006c3",
    x"300e58", x"302e00", x"430030", x"501f00", x"471303", x"440704",
    x"440e00", x"460b35", x"460c22", x"483722", x"382402", x"5000a7",
    x"5001a3", x"5180ff", x"5181f2", x"518200", x"518314", x"518425",
    x"518524", x"518609", x"518709", x"518809", x"518975", x"518a54",
    x"518be0", x"518cb2", x"518d42", x"518e3d", x"518f56", x"519046",
    x"5191f8", x"519204", x"519370", x"5194f0", x"5195f0", x"519603",
    x"519701", x"519804", x"519912", x"519a04", x"519b00", x"519c06",
    x"519d82", x"519e38", x"53811e", x"53825b", x"538308", x"53840a",
    x"53857e", x"538688", x"53877c", x"53886c", x"538910", x"538a01",
    x"538b98", x"530008", x"530130", x"530210", x"530300", x"530408",
    x"530530", x"530608", x"530716", x"530908", x"530a30", x"530b04",
    x"530c06", x"548001", x"548108", x"548214", x"548328", x"548451",
    x"548565", x"548671", x"54877d", x"548887", x"548991", x"548a9a",
    x"548baa", x"548cb8", x"548dcd", x"548edd", x"548fea", x"54901d",
    x"558002", x"558340", x"558410", x"558910", x"558a00", x"558bf8",
    x"580023", x"580114", x"58020f", x"58030f", x"580412", x"580526",
    x"58060c", x"580708", x"580805", x"580905", x"580a08", x"580b0d",
    x"580c08", x"580d03", x"580e00", x"580f00", x"581003", x"581109",
    x"581207", x"581303", x"581400", x"581501", x"581603", x"581708",
    x"58180d", x"581908", x"581a05", x"581b06", x"581c08", x"581d0e",
    x"581e29", x"581f17", x"582011", x"582111", x"582215", x"582328",
    x"582446", x"582526", x"582608", x"582726", x"582864", x"582926",
    x"582a24", x"582b22", x"582c24", x"582d24", x"582e06", x"582f22",
    x"583040", x"583142", x"583224", x"583326", x"583424", x"583522",
    x"583622", x"583726", x"583844", x"583924", x"583a26", x"583b28",
    x"583c42", x"583dce", x"502500", x"3a0f30", x"3a1028", x"3a1b30",
    x"3a1e26", x"3a1160", x"3a1f14", x"300802", x"350300", x"3c0708",
    x"382041", x"382107", x"381431", x"381531", x"380304", x"38079b",
    x"380802", x"380980", x"380a01", x"380be0", x"380c07", x"380d68",
    x"380e03", x"380fd8", x"381306", x"361800", x"361229", x"370862",
    x"370952", x"370c03", x"3a0203", x"3a03d8", x"3a0e03", x"3a0d04",
    x"3a1403", x"3a15d8", x"400402", x"471303", x"440704", x"460b35",
    x"460c22", x"382402", x"5001a3"
    );

  constant reg_test_pattern_c : std_ulogic_vector(15 downto 0) := x"503d";

  -- Changes from vendor setup, written after it.
  constant override_count_c : natural := 9;

  function override(index: natural; test_pattern: boolean) return entry_t
  is
    constant w : std_ulogic_vector(15 downto 0) := std_ulogic_vector(to_unsigned(width_c, 16));
    constant h : std_ulogic_vector(15 downto 0) := std_ulogic_vector(to_unsigned(height_c, 16));
  begin
    case index is
      -- System clock divided by 2, this halves PCLK
      when 0 => return x"303521";
      -- Output size, scaled down from the window
      when 1 => return x"3808" & w(15 downto 8);
      when 2 => return x"3809" & w(7 downto 0);
      when 3 => return x"380a" & h(15 downto 8);
      when 4 => return x"380b" & h(7 downto 0);
      -- RGB565, red first, through the RGB formatter
      when 5 => return x"430061";
      when 6 => return x"501f01";
      -- PCLK rising edge, HREF and VSYNC active high.  Both sync
      -- polarity bits behave inverted against the datasheet.
      when 7 => return x"474020";
      when others =>
        if test_pattern then
          return reg_test_pattern_c & x"80";
        else
          return reg_test_pattern_c & x"00";
        end if;
    end case;
  end function;

  constant entry_count_c : natural := vga_c'length + override_count_c;

  function entry(index: natural; test_pattern: boolean) return entry_t
  is
  begin
    if index < vga_c'length then
      return vga_c(index);
    else
      return override(index - vga_c'length, test_pattern);
    end if;
  end function;

  constant ms_cycles_c : natural := clock_i_hz_c / 1000;
  -- Power down held, then reset held, then time sensor takes before
  -- it answers on SCCB.
  constant power_down_cycles_c : natural := ms_cycles_c * 5;
  constant reset_cycles_c : natural := ms_cycles_c * 5;
  constant boot_cycles_c : natural := ms_cycles_c * 20;
  constant retry_cycles_c : natural := clock_i_hz_c;
  -- Longest pause vendor setup asks for, after soft reset, is 5ms.
  constant pause_cycles_c : natural := ms_cycles_c * 10;
  constant timer_max_c : natural := nsl_math.arith.max(retry_cycles_c, boot_cycles_c);

  constant chip_id_addr_c : unsigned(15 downto 0) := x"300a";
  constant chip_id_c : byte_string(0 to 1) := from_hex("5640");

  type state_t is (
    ST_RESET,
    ST_POWER_DOWN,
    ST_SENSOR_RESET,
    ST_BOOT,
    ST_ID_READ,
    ST_ID_CHECK,
    ST_CONFIG,
    ST_DELAY,
    ST_READY,
    ST_RETRY,
    -- A register access, going back to r.next_state once done
    ST_ACCESS_CMD,
    ST_ACCESS_RSP
    );

  type regs_t is
  record
    state, next_state: state_t;
    timer: natural range 0 to timer_max_c;
    index: natural range 0 to entry_count_c;
    test_pattern: boolean;

    write: boolean;
    count: natural range 1 to 2;
    addr: unsigned(15 downto 0);
    data: byte_string(0 to 1);
  end record;

  signal r, rin: regs_t;

  signal access_cmd_valid_s, access_rsp_ready_s, access_write_s: std_ulogic;
  signal access_ready_s, access_valid_s, access_error_s: std_ulogic;
  signal access_rdata_s: byte_string(0 to 1);

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, test_pattern_i,
                      access_ready_s, access_valid_s, access_error_s, access_rdata_s) is
    variable e: entry_t;
  begin
    rin <= r;

    case r.state is
      when ST_RESET | ST_RETRY =>
        if r.state = ST_RETRY and r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.timer <= power_down_cycles_c;
          rin.state <= ST_POWER_DOWN;
        end if;

      when ST_POWER_DOWN =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.timer <= reset_cycles_c;
          rin.state <= ST_SENSOR_RESET;
        end if;

      when ST_SENSOR_RESET =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.timer <= boot_cycles_c;
          rin.state <= ST_BOOT;
        end if;

      when ST_BOOT =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.state <= ST_ID_READ;
        end if;

      when ST_ID_READ =>
        rin.write <= false;
        rin.count <= 2;
        rin.addr <= chip_id_addr_c;
        rin.next_state <= ST_ID_CHECK;
        rin.state <= ST_ACCESS_CMD;

      when ST_ID_CHECK =>
        if r.data = chip_id_c then
          rin.index <= 0;
          rin.test_pattern <= test_pattern_i = '1';
          rin.state <= ST_CONFIG;
        else
          rin.timer <= retry_cycles_c;
          rin.state <= ST_RETRY;
        end if;

      when ST_CONFIG =>
        if r.index /= entry_count_c then
          e := entry(r.index, r.test_pattern);
          rin.index <= r.index + 1;
          if e(23 downto 8) = delay_addr_c then
            rin.timer <= pause_cycles_c;
            rin.state <= ST_DELAY;
          else
            rin.write <= true;
            rin.count <= 1;
            rin.addr <= unsigned(e(23 downto 8));
            rin.data(0) <= e(7 downto 0);
            rin.next_state <= ST_CONFIG;
            rin.state <= ST_ACCESS_CMD;
          end if;
        else
          rin.state <= ST_READY;
        end if;

      when ST_DELAY =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.state <= ST_CONFIG;
        end if;

      when ST_READY =>
        if r.test_pattern /= (test_pattern_i = '1') then
          rin.test_pattern <= test_pattern_i = '1';
          rin.index <= entry_count_c - 1;
          rin.state <= ST_CONFIG;
        end if;

      when ST_ACCESS_CMD =>
        if access_ready_s = '1' then
          rin.state <= ST_ACCESS_RSP;
        end if;

      when ST_ACCESS_RSP =>
        if access_valid_s = '1' then
          if access_error_s = '1' then
            rin.timer <= retry_cycles_c;
            rin.state <= ST_RETRY;
          else
            if not r.write then
              rin.data <= access_rdata_s;
            end if;
            rin.state <= r.next_state;
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    sensor_power_down_o <= '0';
    sensor_reset_n_o <= '1';
    ready_o <= '0';
    access_cmd_valid_s <= '0';
    access_rsp_ready_s <= '0';

    if r.write then
      access_write_s <= '1';
    else
      access_write_s <= '0';
    end if;

    case r.state is
      when ST_RESET | ST_RETRY | ST_POWER_DOWN =>
        sensor_power_down_o <= '1';
        sensor_reset_n_o <= '0';

      when ST_SENSOR_RESET =>
        sensor_reset_n_o <= '0';

      when ST_READY =>
        ready_o <= '1';

      when ST_ACCESS_CMD =>
        access_cmd_valid_s <= '1';

      when ST_ACCESS_RSP =>
        access_rsp_ready_s <= '1';

      when others =>
        null;
    end case;
  end process;

  register_access: nsl_i2c.transactor.framed_addressed_controller
    generic map(
      addr_byte_count_c => 2,
      big_endian_c => true,
      txn_byte_count_max_c => 2
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      cmd_i => cmd_i,
      cmd_o => cmd_o,
      rsp_o => rsp_o,
      rsp_i => rsp_i,

      valid_i => access_cmd_valid_s,
      ready_o => access_ready_s,
      set_divisor_i => '1',
      divisor_i => i2c_divisor_i,
      saddr_i => i2c_saddr_c,
      addr_i => r.addr,
      write_i => access_write_s,
      wdata_i => r.data,
      data_byte_count_i => r.count,

      valid_o => access_valid_s,
      ready_i => access_rsp_ready_s,
      rdata_o => access_rdata_s,
      error_o => access_error_s
      );

end architecture;
