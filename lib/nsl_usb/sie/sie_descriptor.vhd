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
    string_9 : string := "";
    raw_0 : byte_string := null_byte_string;
    raw_1 : byte_string := null_byte_string;
    raw_2 : byte_string := null_byte_string;
    raw_3 : byte_string := null_byte_string;
    raw_4 : byte_string := null_byte_string;
    raw_5 : byte_string := null_byte_string;
    raw_6 : byte_string := null_byte_string;
    raw_7 : byte_string := null_byte_string
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    string_10_i : in string := "";

    cmd_i : in descriptor_cmd;
    rsp_o : out descriptor_rsp
    );
end entity sie_descriptor;

architecture beh of sie_descriptor is
  
  function desc_item_fs_hs(dtype  : descriptor_type_t;
                           index  : integer;
                           fs_data, hs_data : byte_string) return byte_string
  is
  begin
    if fs_data'length = 0 or hs_data'length = 0 then
      return null_byte_string;
    end if;

    if not hs_supported_c then
      return sie_descriptor_entry(dtype, index, fs_data);
    end if;
    
    return sie_descriptor_entry(dtype, index, fs_data, true, false)
         & sie_descriptor_entry(dtype, index, hs_data, true, true);
  end function;

  constant desc_blob: byte_string :=
    sie_descriptor_entry(DESCRIPTOR_TYPE_DEVICE, 0, device_descriptor)
    & desc_item_fs_hs(DESCRIPTOR_TYPE_CONFIGURATION, 0, fs_config_1, hs_config_1)
    & sie_descriptor_entry(DESCRIPTOR_TYPE_STRING, 0, language(16#0409#))
    & sie_descriptor_entry(DESCRIPTOR_TYPE_STRING, 1, string_from_ascii(string_1))
    & sie_descriptor_entry(DESCRIPTOR_TYPE_STRING, 2, string_from_ascii(string_2))
    & sie_descriptor_entry(DESCRIPTOR_TYPE_STRING, 3, string_from_ascii(string_3))
    & sie_descriptor_entry(DESCRIPTOR_TYPE_STRING, 4, string_from_ascii(string_4))
    & sie_descriptor_entry(DESCRIPTOR_TYPE_STRING, 5, string_from_ascii(string_5))
    & sie_descriptor_entry(DESCRIPTOR_TYPE_STRING, 6, string_from_ascii(string_6))
    & sie_descriptor_entry(DESCRIPTOR_TYPE_STRING, 7, string_from_ascii(string_7))
    & sie_descriptor_entry(DESCRIPTOR_TYPE_STRING, 8, string_from_ascii(string_8))
    & sie_descriptor_entry(DESCRIPTOR_TYPE_STRING, 9, string_from_ascii(string_9))
    & sie_descriptor_entry(DESCRIPTOR_TYPE_DEVICE_QUALIFIER, 0, device_qualifier)
    & raw_0 & raw_1 & raw_2 & raw_3 & raw_4 & raw_5 & raw_6 & raw_7;

  constant desc_blob_size_l2 : natural := nsl_math.arith.log2(desc_blob'length);

  constant desc_blob_padding : byte_string(1 to 2**desc_blob_size_l2-desc_blob'length) :=
    (others => byte'(x"00"));

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_READ_FILL,
    ST_SEARCH_SEEK,
    ST_SEARCH_CMP_SIZE,
    ST_SEARCH_CMP_TYPE,
    ST_SEARCH_CMP_INDEX,
    ST_SEARCH_DECIDE
    );
  
  type regs_t is
  record
    state : state_t;

    dtype  : descriptor_type_t;
    index  : unsigned(5 downto 0);

    hs : std_ulogic;
    start, size_last, rptr : unsigned(desc_blob_size_l2-1 downto 0);

    exists : std_ulogic;

    vstring_byte : byte;
    vstring_mode : boolean;
  end record;

  signal r, rin : regs_t;
  signal s_do_read : std_ulogic;
  signal s_rom_rdata : byte;

  alias vstring_value : string(1 to string_10_i'length) is string_10_i;
  
begin

  regs: process(reset_n_i, clock_i) is
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, cmd_i, s_rom_rdata, vstring_value)
    variable do_vstring_read : boolean;
  begin
    rin <= r;
    do_vstring_read := false;

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
          rin.rptr <= r.start + resize(cmd_i.offset, r.rptr'length);
          rin.state <= ST_READ_FILL;
        elsif cmd_i.read = '1' and r.rptr /= r.size_last then
          rin.rptr <= r.rptr + 1;
          do_vstring_read := true;
        end if;

      when ST_READ_FILL =>
        if r.rptr >= r.size_last then
          rin.rptr <= r.size_last;
        else
          rin.rptr <= r.rptr + 1;
        end if;
        do_vstring_read := true;
        rin.state <= ST_IDLE;
        
      when ST_SEARCH_SEEK =>
        rin.vstring_mode <= false;
        rin.rptr <= r.rptr + 1;
        rin.state <= ST_SEARCH_CMP_SIZE;

        if hs_supported_c
          and r.dtype = DESCRIPTOR_TYPE_OTHER_SPEED_CONFIGURATION then
          rin.hs <= not r.hs;
          rin.dtype <= DESCRIPTOR_TYPE_CONFIGURATION;
        end if;

        if vstring_value'length /= 0
          and r.dtype = DESCRIPTOR_TYPE_STRING
          and r.index = 10 then
          rin.exists <= '1';
          rin.vstring_mode <= true;
          rin.size_last <= to_unsigned(vstring_value'length * 2 + 2, rin.size_last'length);
          rin.start <= (others => '0');
          rin.rptr <= (others => '0');
          rin.state <= ST_IDLE;
        end if;

      when ST_SEARCH_CMP_SIZE =>
        rin.rptr <= r.rptr + 1;
        rin.state <= ST_SEARCH_CMP_TYPE;
        if s_rom_rdata = (s_rom_rdata'range => '0') then
          -- Search over
          rin.state <= ST_IDLE;
          rin.size_last <= (others => '0');
          rin.rptr <= (others => '0');
          rin.exists <= '0';
        else
          rin.size_last <= resize(unsigned(s_rom_rdata), rin.size_last'length);
        end if;

      when ST_SEARCH_CMP_TYPE =>
        rin.rptr <= r.rptr + 1;
        rin.state <= ST_SEARCH_CMP_INDEX;
        if descriptor_type_t(s_rom_rdata) /= r.dtype then
          rin.exists <= '0';
        end if;

      when ST_SEARCH_CMP_INDEX =>
        rin.state <= ST_SEARCH_DECIDE;
        if unsigned(s_rom_rdata(5 downto 0)) /= r.index
          or (s_rom_rdata(7) = '1' and s_rom_rdata(6) /= r.hs) then
          rin.exists <= '0';
        end if;

      when ST_SEARCH_DECIDE =>
        if r.exists = '1' then
          rin.start <= r.rptr;
          rin.state <= ST_IDLE;
          rin.size_last <= r.rptr + r.size_last;
          rin.rptr <= (others => '0');
        else
          rin.exists <= '1';
          rin.state <= ST_SEARCH_SEEK;
          rin.rptr <= r.rptr + r.size_last;
        end if;
    end case;

    if vstring_value'length /= 0 and r.vstring_mode and do_vstring_read then
      if r.rptr = 0 then
        rin.vstring_byte <= byte(to_unsigned(vstring_value'length * 2 + 2, 8));
      elsif r.rptr = 1 then
        rin.vstring_byte <= byte(DESCRIPTOR_TYPE_STRING);
      elsif r.rptr(0) = '1' then
        rin.vstring_byte <= (others => '0');
      else
        rin.vstring_byte <= byte(to_unsigned(character'pos(vstring_value(to_integer(r.rptr(r.rptr'left downto 1)))), 8));
      end if;
    end if;

  end process;

  mealy: process(r, cmd_i, s_rom_rdata)
  begin
    s_do_read <= '0';

    rsp_o.exists <= r.exists;
    rsp_o.lookup_done <= '0';

    rsp_o.last <= to_logic(r.rptr = r.size_last);

    if vstring_value'length /= 0 and r.vstring_mode then
      rsp_o.data <= r.vstring_byte;
    else
      rsp_o.data <= s_rom_rdata;
    end if;

    case r.state is
      when ST_IDLE =>
        s_do_read <= cmd_i.read;
        rsp_o.lookup_done <= '1';

      when ST_READ_FILL =>
        s_do_read <= '1';
        rsp_o.lookup_done <= '1';

      when ST_SEARCH_SEEK
        | ST_SEARCH_CMP_INDEX | ST_SEARCH_CMP_TYPE | ST_SEARCH_CMP_SIZE =>
        s_do_read <= '1';

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
