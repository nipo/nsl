library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_amba, nsl_data, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use work.timestamping.all;

entity timestamping_rx_tagger is
  generic(
    config_c : config_t;
    id_bits_c : natural range 1 to 4 := 2
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    sfd_i : in std_ulogic;

    sfd_o : out std_ulogic;
    id_o : out tag_id_t;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of timestamping_rx_tagger is

  -- Identifiers are queued between the strobe and the frame it
  -- belongs to.  The depth only has to cover the frames the driver
  -- holds between its strobe and its stream output.
  constant id_fifo_depth_c: natural := 8;

  -- Two slots are needed to sustain one beat per cycle while both
  -- handshake sides are registered.
  constant fifo_depth_c: natural := 2;

  constant user_zero_c: std_ulogic_vector(0 to max_user_width_c-1)
    := (others => '0');

  type state_t is (
    ST_RESET,
    -- Waiting for a packet to start, to prepend its tag block.
    ST_TAG,
    -- Forwarding the packet the tag block was emitted for.
    ST_FORWARD
    );

  type regs_t is
  record
    state: state_t;
    -- Identifier the last strobe assigned.
    id: tag_id_t;

    -- Tag bytes of the frames whose strobe passed but that did not
    -- reach the input yet, oldest first.
    id_fifo: byte_string(0 to id_fifo_depth_c-1);
    id_fillness: natural range 0 to id_fifo_depth_c;

    sfd: std_ulogic;
    sfd_id: tag_id_t;

    fifo: master_vector(0 to fifo_depth_c-1);
    fifo_fillness: natural range 0 to fifo_depth_c;
  end record;

  signal r, rin: regs_t;

  function id_next(id: tag_id_t) return tag_id_t
  is
    variable ret: tag_id_t := (others => '0');
  begin
    ret(id_bits_c-1 downto 0) := id(id_bits_c-1 downto 0) + 1;
    return ret;
  end function;

  function tag_beat(tag: byte) return master_t
  is
    variable data: byte_string(0 to config_c.data_width-1)
      := (others => x"00");
  begin
    data(0) := tag;
    return transfer(config_c,
                    bytes => data,
                    user => user_zero_c(0 to config_c.user_width-1),
                    valid => true,
                    last => false);
  end function;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.id <= (others => '1');
      r.id_fillness <= 0;
      r.fifo_fillness <= 0;
      r.sfd <= '0';
    end if;
  end process;

  transition: process(r, sfd_i, in_i, out_i) is
    variable id_push, id_pop, fifo_push, fifo_pop: boolean;
    variable id_v: tag_id_t;
    variable beat_v: master_t;
  begin
    rin <= r;

    id_push := false;
    id_pop := false;
    fifo_push := false;
    fifo_pop := false;
    id_v := id_next(r.id);
    beat_v := in_i;

    rin.sfd <= '0';

    if sfd_i = '1' then
      rin.id <= id_v;
      rin.sfd <= '1';
      rin.sfd_id <= id_v;
      id_push := true;
    end if;

    fifo_pop := r.fifo_fillness /= 0 and is_ready(config_c, out_i);

    case r.state is
      when ST_RESET =>
        rin.state <= ST_TAG;

      when ST_TAG =>
        if is_valid(config_c, in_i)
          and r.id_fillness /= 0
          and r.fifo_fillness < fifo_depth_c then
          beat_v := tag_beat(r.id_fifo(0));
          fifo_push := true;
          id_pop := true;
          rin.state <= ST_FORWARD;
        end if;

      when ST_FORWARD =>
        if is_valid(config_c, in_i) and r.fifo_fillness < fifo_depth_c then
          fifo_push := true;
          if is_last(config_c, in_i) then
            rin.state <= ST_TAG;
          end if;
        end if;
    end case;

    if id_push and id_pop then
      rin.id_fifo <= shift_left(r.id_fifo);
      rin.id_fifo(r.id_fillness-1) <= tag_build(false, id_v);
    elsif id_push and r.id_fillness /= id_fifo_depth_c then
      rin.id_fifo(r.id_fillness) <= tag_build(false, id_v);
      rin.id_fillness <= r.id_fillness + 1;
    elsif id_pop then
      rin.id_fifo <= shift_left(r.id_fifo);
      rin.id_fillness <= r.id_fillness - 1;
    end if;

    if fifo_push and fifo_pop then
      rin.fifo <= r.fifo(1 to fifo_depth_c-1) & r.fifo(fifo_depth_c-1);
      rin.fifo(r.fifo_fillness-1) <= beat_v;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= beat_v;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= r.fifo(1 to fifo_depth_c-1) & r.fifo(fifo_depth_c-1);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  -- Interface contract, sampled on the clock edge like the design
  -- does: between the edge that accepts a beat and the moment the
  -- source updates the bus, the accepted beat is still on it.
  check: process(clock_i) is
  begin
    if rising_edge(clock_i) and reset_n_i = '1' then
      assert not (r.state = ST_TAG
                  and is_valid(config_c, in_i)
                  and r.id_fillness = 0)
        report "Packet started with no identifier queued"
        severity failure;

      assert not (sfd_i = '1'
                  and r.id_fillness = id_fifo_depth_c)
        report "Identifier queue overflow"
        severity failure;
    end if;
  end process;

  moore: process(r) is
  begin
    out_o <= transfer(config_c, r.fifo(0),
                      force_valid => true,
                      valid => r.fifo_fillness /= 0);
    in_o <= accept(config_c,
                   r.state = ST_FORWARD and r.fifo_fillness < fifo_depth_c);
    sfd_o <= r.sfd;
    id_o <= r.sfd_id;
  end process;

end architecture;
