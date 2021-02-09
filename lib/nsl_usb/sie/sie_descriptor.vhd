library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic, nsl_math, nsl_memory;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_data.bytestream.all;
use nsl_usb.descriptor.all;
use nsl_logic.bool.all;

entity sie_descriptor is
  generic (
    hs_supported_c : boolean := false;
    device_descriptor : byte_string;
    device_qualifier : byte_string := null_byte_string;
    fs_config_1 : byte_string;
    hs_config_1 : byte_string := null_byte_string;
    string_1 : string := "";
    string_2 : string := "";
    string_3 : string := "";
    string_4 : string := "";
    string_5 : string := "";
    string_6 : string := "";
    string_7 : string := "";
    string_8 : string := "";
    string_9 : string := ""
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    cmd_i : in descriptor_cmd;
    rsp_o : out descriptor_rsp
    );
end entity sie_descriptor;

architecture beh of sie_descriptor is

  constant string_0: byte_string(1 to 4) := language(16#0409#);

  constant device_descriptor_offset : integer := 0;
  constant device_qualifier_offset  : integer := device_descriptor_offset + device_descriptor'length;
  constant fs_config_1_offset       : integer := device_qualifier_offset + device_qualifier'length;
  constant hs_config_1_offset       : integer := fs_config_1_offset + fs_config_1'length;
  constant string_0_offset          : integer := hs_config_1_offset + hs_config_1'length;
  constant string_1_offset          : integer := string_0_offset + string_0'length;
  constant string_2_offset          : integer := string_1_offset + string_descriptor_length(string_1);
  constant string_3_offset          : integer := string_2_offset + string_descriptor_length(string_2);
  constant string_4_offset          : integer := string_3_offset + string_descriptor_length(string_3);
  constant string_5_offset          : integer := string_4_offset + string_descriptor_length(string_4);
  constant string_6_offset          : integer := string_5_offset + string_descriptor_length(string_5);
  constant string_7_offset          : integer := string_6_offset + string_descriptor_length(string_6);
  constant string_8_offset          : integer := string_7_offset + string_descriptor_length(string_7);
  constant string_9_offset          : integer := string_8_offset + string_descriptor_length(string_8);
  constant desc_total_size          : integer := string_9_offset + string_descriptor_length(string_9);
  
  constant desc_blob: byte_string(0 to desc_total_size-1) :=
    device_descriptor & device_qualifier
    & fs_config_1 & hs_config_1
    & string_0
    & string_from_ascii(string_1)
    & string_from_ascii(string_2)
    & string_from_ascii(string_3)
    & string_from_ascii(string_4)
    & string_from_ascii(string_5)
    & string_from_ascii(string_6)
    & string_from_ascii(string_7)
    & string_from_ascii(string_8)
    & string_from_ascii(string_9)
    ;

  type desc_info_t is
  record
    address: integer range 0 to desc_total_size;
    length: integer range 0 to 255;
    exists: boolean;
  end record;

  function min_1(i:integer) return integer is
  begin
    if i /= 0 then
      return i - 1;
    else
      return 0;
    end if;
  end function;

  function rr(address, length : integer) return desc_info_t is
  begin
    return desc_info_t'(address => address,
                        length => length,
                        exists => length /= 0);
  end function;

  function desc_info_get(dtype  : descriptor_type_t;
                         index  : unsigned;
                         hs : std_ulogic)
    return desc_info_t
  is
  begin
    case dtype is
      when DESCRIPTOR_TYPE_DEVICE =>
        return rr(device_descriptor_offset,
                  device_descriptor'length);

      when DESCRIPTOR_TYPE_CONFIGURATION =>
        if index = 0 then
          if hs_supported_c and hs = '1' then
            return rr(hs_config_1_offset, hs_config_1'length);
          else
            return rr(fs_config_1_offset, fs_config_1'length);
          end if;
        end if;

      when DESCRIPTOR_TYPE_STRING =>
        case to_integer(index) is
          when 0 => return rr(string_0_offset, string_0'length);
          when 1 => return rr(string_1_offset, string_descriptor_length(string_1));
          when 2 => return rr(string_2_offset, string_descriptor_length(string_2));
          when 3 => return rr(string_3_offset, string_descriptor_length(string_3));
          when 4 => return rr(string_4_offset, string_descriptor_length(string_4));
          when 5 => return rr(string_5_offset, string_descriptor_length(string_5));
          when 6 => return rr(string_6_offset, string_descriptor_length(string_6));
          when 7 => return rr(string_7_offset, string_descriptor_length(string_7));
          when 8 => return rr(string_8_offset, string_descriptor_length(string_8));
          when 9 => return rr(string_9_offset, string_descriptor_length(string_9));
          when others =>
            null;
        end case;

      when DESCRIPTOR_TYPE_DEVICE_QUALIFIER =>
        if hs_supported_c then
          return rr(device_qualifier_offset, device_qualifier'length);
        end if;

      when DESCRIPTOR_TYPE_OTHER_SPEED_CONFIGURATION =>
        if hs_supported_c and index = 0 then
          if hs = '1' then
            return rr(fs_config_1_offset, fs_config_1'length);
          else
            return rr(hs_config_1_offset, hs_config_1'length);
          end if;
        end if;

      when others =>
        null;
    end case;

    return rr(0, 0);
  end function;

  constant desc_blob_size_l2 : natural := nsl_math.arith.log2(desc_total_size);

  constant desc_blob_padding : byte_string(1 to 2**desc_blob_size_l2-desc_blob'length) :=
    (others => byte'(x"00"));

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_READ_FILL,
    ST_SEARCH_SEEK
    );
  
  type regs_t is
  record
    state : state_t;

    dtype  : descriptor_type_t;
    index  : unsigned(5 downto 0);

    hs : std_ulogic;
    start, size_last, rptr : unsigned(desc_blob_size_l2-1 downto 0);

    exists : std_ulogic;
  end record;

  signal r, rin : regs_t;
  signal s_do_read : std_ulogic;
  signal s_rom_rdata : byte;
  
begin

  regs: process(reset_n_i, clock_i) is
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, cmd_i, s_rom_rdata)
    variable di : desc_info_t;
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.exists <= '0';
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if cmd_i.lookup = '1' then
          -- Initialize with exists, cleared if any comparison fails
          rin.exists <= '1';
          rin.rptr <= (others => '0');
          rin.hs <= cmd_i.hs;
          rin.dtype <= cmd_i.dtype;
          rin.index <= cmd_i.index;
          rin.state <= ST_SEARCH_SEEK;
        elsif cmd_i.seek = '1' then
          rin.rptr <= r.start + cmd_i.offset;
          rin.state <= ST_READ_FILL;
        elsif cmd_i.read = '1' and r.rptr /= r.size_last then
          rin.rptr <= r.rptr + 1;
        end if;

      when ST_READ_FILL =>
        if r.rptr >= r.size_last then
          rin.rptr <= r.size_last;
        else
          rin.rptr <= r.rptr + 1;
        end if;
        rin.state <= ST_IDLE;
        
      when ST_SEARCH_SEEK =>
        di := desc_info_get(r.dtype, r.index, r.hs);
        rin.start <= to_unsigned(di.address, rin.start'length);
        rin.size_last <= to_unsigned(di.address + di.length, rin.start'length);
        rin.exists <= to_logic(di.exists);
        rin.state <= ST_IDLE;

    end case;
  end process;

  mealy: process(r, cmd_i, s_rom_rdata)
  begin
    s_do_read <= '0';

    rsp_o.last <= to_logic(r.rptr = r.size_last);
    rsp_o.exists <= r.exists;
    rsp_o.lookup_done <= '0';
    rsp_o.data <= s_rom_rdata;

    case r.state is
      when ST_IDLE =>
        s_do_read <= cmd_i.read;
        rsp_o.lookup_done <= '1';

      when ST_READ_FILL =>
        s_do_read <= '1';
        rsp_o.lookup_done <= '1';

      when others =>
        null;
    end case;
  end process;

  rom: nsl_memory.rom.rom_bytes
    generic map(
      word_addr_size_c => r.rptr'length,
      word_byte_count_c => 1,
      contents_c => desc_blob & desc_blob_padding
      )
    port map(
      clock_i => clock_i,
      read_i => s_do_read,
      address_i => r.rptr,
      data_o => s_rom_rdata
      );

end architecture beh;
