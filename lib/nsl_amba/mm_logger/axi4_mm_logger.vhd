library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_memory, nsl_logic;
use nsl_amba.axi4_mm.all;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

entity axi4_mm_logger is
  generic(
    axi_config_c : nsl_amba.axi4_mm.config_t;
    apb_config_c : nsl_amba.apb.config_t;
    depth_l2_c : natural range 4 to 13 := 10
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    timestamp_i : in unsigned(31 downto 0);
    master_i : in nsl_amba.axi4_mm.master_t;
    slave_i : in nsl_amba.axi4_mm.slave_t;
    apb_i : in nsl_amba.apb.master_t;
    apb_o : out nsl_amba.apb.slave_t
    );
end entity;

-- Handshakes are registered with their entry in a first stage (one
-- pipeline register per channel), then written to the channel memory
-- from this register.  APB reads are served from a register captured
-- during the setup phase, or from the memory read port addressed during
-- the setup phase, both available during the access phase.
architecture beh of axi4_mm_logger is

  constant channel_count_c : natural := 5;
  constant depth_c : natural := 2 ** depth_l2_c;
  -- Byte offset bits of one region (register file or channel memory).
  constant region_lsb_c : natural := depth_l2_c + 4;

  subtype word_t is unsigned(31 downto 0);
  subtype entry_t is std_ulogic_vector(4 * 32 - 1 downto 0);
  type entry_vector is array (natural range <>) of entry_t;
  subtype count_t is integer range 0 to depth_c;
  type count_vector is array (natural range <>) of count_t;
  subtype stall_t is integer range 0 to 255;
  type stall_vector is array (natural range <>) of stall_t;
  subtype index_t is unsigned(depth_l2_c-1 downto 0);
  type index_vector is array (natural range <>) of index_t;

  type read_source_t is (
    READ_SOURCE_REGISTER,
    READ_SOURCE_MEMORY
    );

  type regs_t is
  record
    enable: boolean;
    overflow: std_ulogic_vector(0 to channel_count_c-1);
    count: count_vector(0 to channel_count_c-1);
    stall: stall_vector(0 to channel_count_c-1);

    pending: std_ulogic_vector(0 to channel_count_c-1);
    pending_index: index_vector(0 to channel_count_c-1);
    pending_entry: entry_vector(0 to channel_count_c-1);

    read_valid: boolean;
    read_source: read_source_t;
    read_channel: integer range 0 to channel_count_c-1;
    read_word: integer range 0 to 3;
    read_register: word_t;
  end record;

  signal r, rin: regs_t;

  signal apb_address_s : unsigned(apb_config_c.address_width-1 downto 2);
  signal apb_w_data_s : byte_string(0 to 3);
  signal apb_w_mask_s : std_ulogic_vector(0 to 3);
  signal apb_w_valid_s, apb_r_ready_s, apb_r_valid_s : std_ulogic;
  signal apb_r_data_s : byte_string(0 to 3);
  signal memory_read_index_s : index_t;
  signal memory_read_data_s : entry_vector(0 to channel_count_c-1);

  function fit(v: std_ulogic_vector; w: natural) return unsigned
  is
    alias xv: std_ulogic_vector(v'length-1 downto 0) is v;
    variable ret: unsigned(w-1 downto 0) := (others => '0');
  begin
    for i in ret'range
    loop
      if i < v'length then
        ret(i) := xv(i);
      end if;
    end loop;
    return ret;
  end function;

  function fit(v: unsigned; w: natural) return unsigned
  is
  begin
    return fit(std_ulogic_vector(v), w);
  end function;

  function to_u(b: boolean) return unsigned
  is
  begin
    if b then
      return "1";
    end if;
    return "0";
  end function;

  function entry(w0, w1, w2, w3: word_t) return entry_t
  is
    variable ret: entry_t;
  begin
    ret(31 downto 0) := std_ulogic_vector(w0);
    ret(63 downto 32) := std_ulogic_vector(w1);
    ret(95 downto 64) := std_ulogic_vector(w2);
    ret(127 downto 96) := std_ulogic_vector(w3);
    return ret;
  end function;

  -- Data bytes 0 to 7 of a beat, byte 0 in bits 7:0.
  function data_word(cfg: config_t; data: byte_string; first: natural) return word_t
  is
    alias xd: byte_string(0 to data'length-1) is data;
    variable ret: word_t := (others => '0');
  begin
    for i in 0 to 3
    loop
      if first + i < xd'length then
        ret(i*8+7 downto i*8) := unsigned(xd(first + i));
      end if;
    end loop;
    return ret;
  end function;

  function address_entry(cfg: config_t; ts: word_t; a: address_t; stall: stall_t) return entry_t
  is
  begin
    return entry(
      ts,
      fit(address(cfg, a), 32),
      "00" & to_u(lock(cfg, a) = LOCK_EXCLUSIVE)
      & unsigned(to_logic(cfg, burst(cfg, a))) & size_l2(cfg, a)
      & length_m1(cfg, a, 8) & fit(id(cfg, a), 16),
      to_unsigned(stall, 8) & x"00"
      & unsigned(region(cfg, a)) & unsigned(qos(cfg, a))
      & "0" & unsigned(prot(cfg, a)) & unsigned(cache(cfg, a)));
  end function;

  function write_data_entry(cfg: config_t; ts: word_t; w: write_data_t; stall: stall_t) return entry_t
  is
  begin
    return entry(
      ts,
      data_word(cfg, bytes(cfg, w), 0),
      data_word(cfg, bytes(cfg, w), 4),
      to_unsigned(stall, 8) & x"00" & "0000000" & to_u(is_last(cfg, w))
      & fit(bitswap(strb(cfg, w)), 8));
  end function;

  function write_response_entry(cfg: config_t; ts: word_t; b: write_response_t; stall: stall_t) return entry_t
  is
  begin
    return entry(
      ts,
      x"000" & "00" & unsigned(to_logic(cfg, resp(cfg, b))) & fit(id(cfg, b), 16),
      x"00000000",
      to_unsigned(stall, 8) & x"000000");
  end function;

  function read_data_entry(cfg: config_t; ts: word_t; r: read_data_t; stall: stall_t) return entry_t
  is
  begin
    return entry(
      ts,
      data_word(cfg, bytes(cfg, r), 0),
      data_word(cfg, bytes(cfg, r), 4),
      to_unsigned(stall, 8) & "00000" & to_u(is_last(cfg, r))
      & unsigned(to_logic(cfg, resp(cfg, r))) & fit(id(cfg, r), 16));
  end function;

begin

  assert axi_config_c.data_bus_width_l2 <= 3
    report "axi4_mm_logger does not support AXI data buses wider than 64 bits"
    severity failure;

  assert apb_config_c.data_bus_width_l2 = 2
    report "axi4_mm_logger requires a 32-bit APB data bus"
    severity failure;

  assert apb_config_c.address_width >= depth_l2_c + 7
    report "axi4_mm_logger requires at least depth_l2_c + 7 APB address bits"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.enable <= false;
      r.overflow <= (others => '0');
      r.count <= (others => 0);
      r.stall <= (others => 0);
      r.pending <= (others => '0');
      r.read_valid <= false;
    end if;
  end process;

  transition: process(r, timestamp_i, master_i, slave_i,
                      apb_address_s, apb_w_data_s, apb_w_mask_s,
                      apb_w_valid_s, apb_r_ready_s) is
    variable valid, ready: std_ulogic_vector(0 to channel_count_c-1);
    variable entries: entry_vector(0 to channel_count_c-1);
    variable clear: boolean;
    variable region: integer range 0 to 7;
    variable offset: integer range 0 to 2**(region_lsb_c-2)-1;
  begin
    rin <= r;

    valid := (to_logic(is_valid(axi_config_c, master_i.aw)),
              to_logic(is_valid(axi_config_c, master_i.w)),
              to_logic(is_valid(axi_config_c, slave_i.b)),
              to_logic(is_valid(axi_config_c, master_i.ar)),
              to_logic(is_valid(axi_config_c, slave_i.r)));
    ready := (to_logic(is_ready(axi_config_c, slave_i.aw)),
              to_logic(is_ready(axi_config_c, slave_i.w)),
              to_logic(is_ready(axi_config_c, master_i.b)),
              to_logic(is_ready(axi_config_c, slave_i.ar)),
              to_logic(is_ready(axi_config_c, master_i.r)));

    entries(0) := address_entry(axi_config_c, timestamp_i, master_i.aw, r.stall(0));
    entries(1) := write_data_entry(axi_config_c, timestamp_i, master_i.w, r.stall(1));
    entries(2) := write_response_entry(axi_config_c, timestamp_i, slave_i.b, r.stall(2));
    entries(3) := address_entry(axi_config_c, timestamp_i, master_i.ar, r.stall(3));
    entries(4) := read_data_entry(axi_config_c, timestamp_i, slave_i.r, r.stall(4));

    region := to_integer(apb_address_s(region_lsb_c+2 downto region_lsb_c));
    offset := to_integer(apb_address_s(region_lsb_c-1 downto 2));

    clear := apb_w_valid_s = '1' and region = 0 and offset = 0
             and apb_w_mask_s(0) = '1' and apb_w_data_s(0)(1) = '1';

    if apb_w_valid_s = '1' and region = 0 and offset = 0
      and apb_w_mask_s(0) = '1' then
      rin.enable <= apb_w_data_s(0)(0) = '1';
    end if;

    for c in 0 to channel_count_c-1
    loop
      rin.pending(c) <= '0';
      rin.pending_index(c) <= to_unsigned(r.count(c) mod depth_c, depth_l2_c);
      rin.pending_entry(c) <= entries(c);

      if valid(c) = '1' and ready(c) = '0' then
        if r.stall(c) /= 255 then
          rin.stall(c) <= r.stall(c) + 1;
        end if;
      else
        rin.stall(c) <= 0;
      end if;

      if clear then
        rin.count(c) <= 0;
        rin.overflow(c) <= '0';
      elsif r.enable and valid(c) = '1' and ready(c) = '1' then
        if r.count(c) = depth_c then
          rin.overflow(c) <= '1';
        else
          rin.pending(c) <= '1';
          rin.count(c) <= r.count(c) + 1;
        end if;
      end if;
    end loop;

    if r.read_valid then
      rin.read_valid <= false;
    elsif apb_r_ready_s = '1' then
      rin.read_valid <= true;
      rin.read_source <= READ_SOURCE_REGISTER;
      rin.read_register <= (others => '0');
      rin.read_channel <= 0;
      rin.read_word <= offset mod 4;

      case region is
        when 0 =>
          case offset is
            when 0 =>
              if r.enable then
                rin.read_register(0) <= '1';
              end if;
            when 1 =>
              for c in 0 to channel_count_c-1
              loop
                rin.read_register(c) <= r.overflow(c);
              end loop;
            when 2 =>
              rin.read_register <= timestamp_i;
            when 3 =>
              rin.read_register(4 downto 0) <= to_unsigned(depth_l2_c, 5);
              rin.read_register(11 downto 8) <= to_unsigned(axi_config_c.data_bus_width_l2, 4);
              rin.read_register(23 downto 16) <= to_unsigned(axi_config_c.id_width, 8);
            when 4 to 4 + channel_count_c - 1 =>
              rin.read_register <= to_unsigned(r.count(offset - 4), 32);
            when others =>
              null;
          end case;

        when 1 to channel_count_c =>
          rin.read_source <= READ_SOURCE_MEMORY;
          rin.read_channel <= region - 1;

        when others =>
          null;
      end case;
    end if;
  end process;

  apb_r_valid_s <= '1' when r.read_valid else '0';
  memory_read_index_s <= apb_address_s(region_lsb_c-1 downto 4);

  read_data: process(r, memory_read_data_s) is
    variable e: entry_t;
    variable value: word_t;
  begin
    e := memory_read_data_s(r.read_channel);
    value := unsigned(e(r.read_word*32+31 downto r.read_word*32));
    if r.read_source = READ_SOURCE_REGISTER then
      value := r.read_register;
    end if;
    apb_r_data_s <= to_le(value);
  end process;

  apb: nsl_amba.apb.apb_slave
    generic map(
      config_c => apb_config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      apb_i => apb_i,
      apb_o => apb_o,

      address_o => apb_address_s,

      w_data_o => apb_w_data_s,
      w_mask_o => apb_w_mask_s,
      w_ready_i => '1',
      w_valid_o => apb_w_valid_s,

      r_data_i => apb_r_data_s,
      r_ready_o => apb_r_ready_s,
      r_valid_i => apb_r_valid_s
      );

  channels: for c in 0 to channel_count_c-1
  generate
    signal write_en_s: std_ulogic_vector(3 downto 0);
  begin
    write_en_s <= (others => r.pending(c));

    memory: nsl_memory.ram.ram_auto
      generic map(
        addr_size_c => depth_l2_c,
        word_size_c => 32,
        data_word_count_c => 4,
        registered_output_c => false
        )
      port map(
        clock_i => clock_i,

        write_address_i => r.pending_index(c),
        write_en_i => write_en_s,
        write_data_i => r.pending_entry(c),

        read_address_i => memory_read_index_s,
        read_en_i => apb_r_ready_s,
        read_data_o => memory_read_data_s(c)
        );
  end generate;

end architecture;
