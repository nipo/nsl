library ieee;
use ieee.std_logic_1164.all;

-- Shallow FIFO built from a shifting data path and a one-hot fill
-- register.
--
-- Storage is word_count_c registers where slot(0) is always the
-- oldest word, so out_data_o is slot(0) with no logic in between.
-- Fill level is held as a one-hot register `pos` of word_count_c+1
-- bits: pos(k) set means k words are held. Empty is pos(0) and full
-- is pos(word_count_c), both single wires, and each slot's enable and
-- data mux only look at pos(i), pos(i+1) and the two handshake
-- strobes. There is no binary fill counter and no magnitude
-- comparison anywhere.
--
-- Cost is word_count_c*data_width_c + word_count_c+1 registers and
-- one mux2 per stored bit. Compared to a shift FIFO steered by a
-- binary fill counter, this trades log2(word_count_c) counter
-- registers for word_count_c+1 one-hot registers and removes the
-- decoder, the incrementer and the empty/full comparators; the
-- critical path from a handshake strobe to a slot enable stays at one
-- or two gates whatever the depth. Compared to fifo_homogeneous, this
-- has no RAM, no pointer arithmetic and no gray coding, at the price
-- of toggling every stored bit on each pop, which only pays off for
-- the shallow depths this component is meant for.
--
-- This component deliberately stores plain vectors and exposes only
-- the head word. Designs that need to peek deeper than slot(0), or to
-- store an array of records, are still better served by a FIFO
-- hand-rolled in their own state record; do not grow peek ports or
-- structured payloads here.
entity fifo_shift_register is
  generic(
    data_width_c: natural;
    word_count_c: natural range 1 to 16
    );
  port(
    reset_n_i: in std_ulogic;
    clock_i: in std_ulogic;

    in_data_i: in std_ulogic_vector(data_width_c-1 downto 0);
    in_valid_i: in std_ulogic;
    in_ready_o: out std_ulogic;

    out_data_o: out std_ulogic_vector(data_width_c-1 downto 0);
    out_valid_o: out std_ulogic;
    out_ready_i: in std_ulogic;

    -- Registered one-hot fill level, exported as-is. fill_o(k) is set
    -- when the FIFO holds k words. Users needing "at least K words
    -- held" or "room for at least K words" should read the matching
    -- single bits rather than build a count out of it.
    fill_o: out std_ulogic_vector(0 to word_count_c)
    );
end entity;

architecture beh of fifo_shift_register is

  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);
  type word_vector_t is array(natural range <>) of word_t;

  type regs_t is
  record
    slot: word_vector_t(0 to word_count_c-1);
    pos: std_ulogic_vector(0 to word_count_c);
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.pos <= (0 => '1', others => '0');
    end if;
  end process;

  transition: process(r, in_data_i, in_valid_i, out_ready_i) is
    variable push, pop: std_ulogic;
    -- Value slot(i) takes when the data path shifts down.
    variable shifted: word_vector_t(0 to word_count_c-1);
  begin
    push := in_valid_i and not r.pos(word_count_c);
    pop := out_ready_i and not r.pos(0);

    for i in 0 to word_count_c-2
    loop
      shifted(i) := r.slot(i+1);
    end loop;
    shifted(word_count_c-1) := (others => '-');

    rin <= r;

    -- On a push alone, the incoming word lands at the current fill
    -- position. On a push together with a pop, everything shifts down
    -- by one, so the incoming word lands one slot below the current
    -- fill position instead. Both are the same mux2 selected by a
    -- neighbouring pos bit.
    for i in 0 to word_count_c-1
    loop
      if push = '1'
        and ((pop = '1' and r.pos(i+1) = '1')
             or (pop = '0' and r.pos(i) = '1')) then
        rin.slot(i) <= in_data_i;
      elsif pop = '1' then
        rin.slot(i) <= shifted(i);
      end if;
    end loop;

    if push = '1' and pop = '0' then
      rin.pos(0) <= '0';
      for i in 1 to word_count_c
      loop
        rin.pos(i) <= r.pos(i-1);
      end loop;
    elsif push = '0' and pop = '1' then
      for i in 0 to word_count_c-1
      loop
        rin.pos(i) <= r.pos(i+1);
      end loop;
      rin.pos(word_count_c) <= '0';
    end if;
  end process;

  moore: process(r) is
  begin
    in_ready_o <= not r.pos(word_count_c);
    out_valid_o <= not r.pos(0);
    out_data_o <= r.slot(0);
    fill_o <= r.pos;
  end process;

end architecture;
