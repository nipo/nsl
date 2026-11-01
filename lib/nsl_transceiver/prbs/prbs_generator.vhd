library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_data;
use nsl_data.bytestream.all;
use nsl_transceiver.lane.all;
use nsl_transceiver.prbs.all;

entity prbs_generator is
  generic(
    byte_count_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    mode_i : in prbs_mode_t;
    force_error_i : in std_ulogic;

    -- The pattern advances on an accepted word only. A sink that
    -- stalls gets the same word again rather than a hole in the
    -- sequence, which is the difference between a far end that
    -- stays locked and one that has to hunt again.
    ready_i : in std_ulogic;

    data_o : out byte_string(0 to byte_count_c-1);
    valid_o : out std_ulogic
    );
end entity;

architecture beh of prbs_generator is

  constant bit_count_c : natural := byte_count_c * 8;

  -- History plus the word being produced from it. Oldest bit first,
  -- so a tap of depth d for the bit at index i reads index i-d.
  subtype window_t is std_ulogic_vector(0 to max_order_c + bit_count_c - 1);

  type regs_t is
  record
    history : history_t;
    data : byte_string(0 to byte_count_c-1);
    valid : std_ulogic;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      -- All zeros is the pattern's one fixed point: a generator
      -- started there would never leave it.
      r.history <= (others => '1');
      r.valid <= '0';
    end if;
  end process;

  transition: process(r, mode_i, force_error_i, ready_i) is
    variable window_v : window_t;
    variable deep_v, shallow_v : natural;
    variable byte_v : byte;
  begin
    rin <= r;

    deep_v := deep_tap(mode_i);
    shallow_v := shallow_tap(mode_i);

    if mode_i = PRBS_NONE then
      rin.valid <= '0';
      rin.data <= (others => (others => '-'));
    elsif r.valid = '0' or ready_i = '1' then
      window_v := (others => '0');
      window_v(0 to max_order_c-1) := r.history;

      for i in max_order_c to max_order_c + bit_count_c - 1 loop
        window_v(i) := window_v(i - deep_v) xor window_v(i - shallow_v);
      end loop;

      -- One bit of the word goes out wrong on request. The state is
      -- left alone, so the pattern itself does not break: the far
      -- end sees a single wrong bit and nothing more.
      if force_error_i = '1' then
        window_v(max_order_c) := not window_v(max_order_c);
      end if;

      for i in 0 to byte_count_c-1 loop
        for b in 0 to 7 loop
          byte_v(b) := window_v(max_order_c + i * 8 + b);
        end loop;
        rin.data(i) <= byte_v;
      end loop;

      -- The forced bit is not fed back, so what the generator
      -- remembers is the pattern it should have sent.
      if force_error_i = '1' then
        window_v(max_order_c) := not window_v(max_order_c);
      end if;

      rin.history <= window_v(bit_count_c to bit_count_c + max_order_c - 1);
      rin.valid <= '1';
    end if;
  end process;

  moore: process(r) is
  begin
    data_o <= r.data;
    valid_o <= r.valid;
  end process;

end architecture;
