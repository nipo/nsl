library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math;
use nsl_amba.apb.all;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;

entity apb_stream_bridge is
  generic (
    apb_config_c : nsl_amba.apb.config_t;
    stream_config_c : nsl_amba.axi4_stream.config_t;
    burst_length_l2_c : natural;
    identify_c : byte_string
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    rx_i : in nsl_amba.axi4_stream.master_t;
    rx_o : out nsl_amba.axi4_stream.slave_t;

    tx_o : out nsl_amba.axi4_stream.master_t;
    tx_i : in nsl_amba.axi4_stream.slave_t;

    apb_o : out nsl_amba.apb.master_t;
    apb_i : in nsl_amba.apb.slave_t
    );
begin

  assert stream_config_c.data_width = 1
    report "stream must be one byte wide"
    severity failure;

  assert stream_config_c.has_last
    report "stream must have last"
    severity failure;

  assert stream_config_c.has_ready
    report "stream must have ready"
    severity failure;

end entity;

architecture rtl of apb_stream_bridge is

  constant data_bytes_c : natural := 2**apb_config_c.data_bus_width_l2;
  constant addr_bytes_c : natural := (apb_config_c.address_width + 7) / 8;
  constant count_bytes_c : natural := nsl_math.arith.max(1, (burst_length_l2_c + 7) / 8);
  constant words_width_c : natural := nsl_math.arith.max(1, burst_length_l2_c);
  constant identify_len_c : natural := identify_c'length;

  constant ones_strb_c : std_ulogic_vector(0 to data_bytes_c-1) := (others => '1');

  constant OPCODE_IDENTIFY_C : byte := x"ff";
  constant OPCODE_READ_C : byte := x"80";
  constant OPCODE_WRITE_C : byte := x"00";

  type state_t is (
    ST_RESET,
    ST_CMD,          -- read opcode
    ST_ID_CONSUME,   -- drop remaining identify command bytes until last
    ST_ID_EMIT,      -- emit identify payload
    ST_ADDR,         -- collect address (read or write)
    ST_COUNT,        -- collect word count (read)
    ST_RD_CONSUME,   -- drop remaining read command bytes until last
    ST_RD_SETUP,     -- APB read, setup phase
    ST_RD_ACCESS,    -- APB read, access phase
    ST_RD_EMIT,      -- emit fetched word bytes
    ST_WR_COLLECT,   -- collect write data bytes into a word
    ST_WR_SETUP,     -- APB write, setup phase
    ST_WR_ACCESS,    -- APB write, access phase
    ST_ERR_CONSUME,  -- drop malformed command until last
    ST_STATUS        -- emit status byte (last)
    );

  type regs_t is
  record
    state : state_t;
    is_write : boolean;
    addr : unsigned(apb_config_c.address_width-1 downto 0);
    count_acc : unsigned(count_bytes_c*8-1 downto 0);
    words_rem : unsigned(words_width_c-1 downto 0);
    field_idx : natural range 0 to nsl_math.arith.max(addr_bytes_c, count_bytes_c);
    word : byte_string(0 to data_bytes_c-1);
    word_idx : natural range 0 to data_bytes_c;
    id_idx : natural range 0 to identify_len_c;
    status_err : std_ulogic;
    wr_last : boolean;
  end record;

  signal r, rin : regs_t;

  -- Replaces byte idx of a little-endian field, bit by bit with
  -- constant indices: synthesis refuses a slice whose bounds depend on
  -- a register.  Bits beyond the field's top are left out.
  function byte_set(field : unsigned; idx : natural; b : byte) return unsigned
  is
    variable ret : unsigned(field'length-1 downto 0) := field;
  begin
    for i in ret'range
    loop
      if i / 8 = idx then
        ret(i) := b(i mod 8);
      end if;
    end loop;
    return ret;
  end function;

begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, rx_i, tx_i, apb_i)
    variable ib : byte;
    variable addr_v : unsigned(apb_config_c.address_width-1 downto 0);
    variable cnt_v : unsigned(count_bytes_c*8-1 downto 0);
  begin
    rin <= r;
    ib := bytes(stream_config_c, rx_i)(0);

    case r.state is
      when ST_RESET =>
        rin.state <= ST_CMD;

      when ST_CMD =>
        if is_valid(stream_config_c, rx_i) then
          rin.status_err <= '0';
          rin.field_idx <= 0;
          rin.word_idx <= 0;
          rin.id_idx <= 0;
          if ib = OPCODE_IDENTIFY_C then
            if is_last(stream_config_c, rx_i) then
              rin.state <= ST_ID_EMIT;
            else
              rin.state <= ST_ID_CONSUME;
            end if;
          elsif ib = OPCODE_READ_C then
            if is_last(stream_config_c, rx_i) then
              rin.status_err <= '1';
              rin.state <= ST_STATUS;
            else
              rin.is_write <= false;
              rin.state <= ST_ADDR;
            end if;
          elsif ib = OPCODE_WRITE_C then
            if is_last(stream_config_c, rx_i) then
              rin.status_err <= '1';
              rin.state <= ST_STATUS;
            else
              rin.is_write <= true;
              rin.state <= ST_ADDR;
            end if;
          else
            rin.status_err <= '1';
            if is_last(stream_config_c, rx_i) then
              rin.state <= ST_STATUS;
            else
              rin.state <= ST_ERR_CONSUME;
            end if;
          end if;
        end if;

      when ST_ID_CONSUME =>
        if is_valid(stream_config_c, rx_i) and is_last(stream_config_c, rx_i) then
          rin.state <= ST_ID_EMIT;
        end if;

      when ST_ID_EMIT =>
        if is_ready(stream_config_c, tx_i) then
          if r.id_idx = identify_len_c - 1 then
            rin.state <= ST_STATUS;
          else
            rin.id_idx <= r.id_idx + 1;
          end if;
        end if;

      when ST_ADDR =>
        if is_valid(stream_config_c, rx_i) then
          addr_v := byte_set(r.addr, r.field_idx, ib);
          rin.addr <= addr_v;
          if r.field_idx = addr_bytes_c - 1 then
            rin.field_idx <= 0;
            if is_last(stream_config_c, rx_i) then
              -- Address was the last byte: no count / no data.
              if r.is_write then
                rin.state <= ST_STATUS;
              else
                rin.status_err <= '1';
                rin.state <= ST_STATUS;
              end if;
            elsif r.is_write then
              rin.word_idx <= 0;
              rin.state <= ST_WR_COLLECT;
            else
              rin.state <= ST_COUNT;
            end if;
          elsif is_last(stream_config_c, rx_i) then
            -- Short frame: last before address complete.
            rin.status_err <= '1';
            rin.state <= ST_STATUS;
          else
            rin.field_idx <= r.field_idx + 1;
          end if;
        end if;

      when ST_COUNT =>
        if is_valid(stream_config_c, rx_i) then
          cnt_v := byte_set(r.count_acc, r.field_idx, ib);
          rin.count_acc <= cnt_v;
          if r.field_idx = count_bytes_c - 1 then
            rin.field_idx <= 0;
            -- count field carries (word count - 1)
            rin.words_rem <= resize(cnt_v, words_width_c);
            rin.word_idx <= 0;
            if is_last(stream_config_c, rx_i) then
              rin.state <= ST_RD_SETUP;
            else
              rin.state <= ST_RD_CONSUME;
            end if;
          elsif is_last(stream_config_c, rx_i) then
            -- Short frame: last before count complete.
            rin.status_err <= '1';
            rin.state <= ST_STATUS;
          else
            rin.field_idx <= r.field_idx + 1;
          end if;
        end if;

      when ST_RD_CONSUME =>
        if is_valid(stream_config_c, rx_i) and is_last(stream_config_c, rx_i) then
          rin.state <= ST_RD_SETUP;
        end if;

      when ST_RD_SETUP =>
        rin.state <= ST_RD_ACCESS;

      when ST_RD_ACCESS =>
        if is_ready(apb_config_c, apb_i) then
          rin.word <= bytes(apb_config_c, apb_i);
          if is_error(apb_config_c, apb_i) then
            rin.status_err <= '1';
          end if;
          rin.word_idx <= 0;
          rin.state <= ST_RD_EMIT;
        end if;

      when ST_RD_EMIT =>
        if is_ready(stream_config_c, tx_i) then
          if r.word_idx = data_bytes_c - 1 then
            if r.words_rem = 0 then
              -- off-by-one counter: 0 on the last word
              rin.state <= ST_STATUS;
            else
              rin.words_rem <= r.words_rem - 1;
              rin.addr <= r.addr + data_bytes_c;
              rin.state <= ST_RD_SETUP;
            end if;
          else
            rin.word_idx <= r.word_idx + 1;
          end if;
        end if;

      when ST_WR_COLLECT =>
        if is_valid(stream_config_c, rx_i) then
          rin.word(r.word_idx) <= ib;
          if r.word_idx = data_bytes_c - 1 then
            rin.word_idx <= 0;
            rin.wr_last <= is_last(stream_config_c, rx_i);
            rin.state <= ST_WR_SETUP;
          else
            rin.word_idx <= r.word_idx + 1;
            if is_last(stream_config_c, rx_i) then
              -- last fell mid-word: not word-complete.
              rin.status_err <= '1';
              rin.state <= ST_STATUS;
            end if;
          end if;
        end if;

      when ST_WR_SETUP =>
        rin.state <= ST_WR_ACCESS;

      when ST_WR_ACCESS =>
        if is_ready(apb_config_c, apb_i) then
          if is_error(apb_config_c, apb_i) then
            rin.status_err <= '1';
          end if;
          rin.addr <= r.addr + data_bytes_c;
          if r.wr_last then
            rin.state <= ST_STATUS;
          else
            rin.word_idx <= 0;
            rin.state <= ST_WR_COLLECT;
          end if;
        end if;

      when ST_ERR_CONSUME =>
        if is_valid(stream_config_c, rx_i) and is_last(stream_config_c, rx_i) then
          rin.state <= ST_STATUS;
        end if;

      when ST_STATUS =>
        if is_ready(stream_config_c, tx_i) then
          rin.state <= ST_CMD;
        end if;
    end case;
  end process;

  mealy: process(r, rx_i, tx_i, apb_i)
    variable status_v : byte;
  begin
    rx_o <= accept(stream_config_c, false);
    tx_o <= transfer_defaults(stream_config_c);
    apb_o <= transfer_idle(apb_config_c);

    status_v := (0 => r.status_err, others => '0');

    case r.state is
      when ST_CMD | ST_ID_CONSUME | ST_ADDR | ST_COUNT
        | ST_RD_CONSUME | ST_WR_COLLECT | ST_ERR_CONSUME =>
        rx_o <= accept(stream_config_c, true);

      when ST_ID_EMIT =>
        tx_o <= transfer(stream_config_c,
                         bytes => byte_string'(0 => identify_c(identify_c'low + r.id_idx)),
                         valid => true,
                         last => false);

      when ST_RD_EMIT =>
        tx_o <= transfer(stream_config_c,
                         bytes => byte_string'(0 => r.word(r.word_idx)),
                         valid => true,
                         last => false);

      when ST_STATUS =>
        tx_o <= transfer(stream_config_c,
                         bytes => byte_string'(0 => status_v),
                         valid => true,
                         last => true);

      when ST_RD_SETUP =>
        apb_o <= read_transfer(apb_config_c, addr => r.addr, phase => PHASE_SETUP);

      when ST_RD_ACCESS =>
        apb_o <= read_transfer(apb_config_c, addr => r.addr, phase => PHASE_ACCESS);

      when ST_WR_SETUP =>
        apb_o <= write_transfer(apb_config_c, addr => r.addr, bytes => r.word,
                                strb => ones_strb_c, phase => PHASE_SETUP);

      when ST_WR_ACCESS =>
        apb_o <= write_transfer(apb_config_c, addr => r.addr, bytes => r.word,
                                strb => ones_strb_c, phase => PHASE_ACCESS);

      when others =>
        null;
    end case;
  end process;

end architecture;
