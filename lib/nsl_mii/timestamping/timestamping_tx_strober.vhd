library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_amba, nsl_data, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use work.timestamping.all;

entity timestamping_tx_strober is
  generic(
    config_c : config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    sfd_i : in std_ulogic;

    strobe_o : out std_ulogic;
    id_o : out tag_id_t;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of timestamping_tx_strober is

  -- Tags are queued between the frame handoff to the driver and the
  -- strobe of its SFD.  The prefill buffers and the driver fifos in
  -- between may hold more than one frame.
  constant tag_fifo_depth_c: natural := 8;

  -- Two slots are needed to sustain one beat per cycle while both
  -- handshake sides are registered.
  constant fifo_depth_c: natural := 2;

  type state_t is (
    ST_RESET,
    -- Waiting for a packet to start, to consume its tag block.
    ST_TAG,
    -- Forwarding the packet the tag block was consumed for.
    ST_FORWARD
    );

  type regs_t is
  record
    state: state_t;

    -- Tag bytes of the frames handed over to the driver that did not
    -- strobe their SFD yet, oldest first.
    tag_fifo: byte_string(0 to tag_fifo_depth_c-1);
    tag_fillness: natural range 0 to tag_fifo_depth_c;

    strobe: std_ulogic;
    strobe_id: tag_id_t;

    fifo: master_vector(0 to fifo_depth_c-1);
    fifo_fillness: natural range 0 to fifo_depth_c;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.tag_fillness <= 0;
      r.fifo_fillness <= 0;
      r.strobe <= '0';
    end if;
  end process;

  transition: process(r, sfd_i, in_i, out_i) is
    variable tag_push, tag_pop, fifo_push, fifo_pop: boolean;
    variable tag_v: byte;
  begin
    rin <= r;

    tag_push := false;
    tag_pop := false;
    fifo_push := false;
    fifo_pop := false;
    tag_v := bytes(config_c, in_i)(0);

    rin.strobe <= '0';

    if sfd_i = '1' and r.tag_fillness /= 0 then
      tag_pop := true;
      if tag_strobes(r.tag_fifo(0)) then
        rin.strobe <= '1';
        rin.strobe_id <= tag_id(r.tag_fifo(0));
      end if;
    end if;

    fifo_pop := r.fifo_fillness /= 0 and is_ready(config_c, out_i);

    case r.state is
      when ST_RESET =>
        rin.state <= ST_TAG;

      when ST_TAG =>
        if is_valid(config_c, in_i)
          and r.tag_fillness < tag_fifo_depth_c
          and not is_last(config_c, in_i) then
          tag_push := true;
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

    if tag_push and tag_pop then
      rin.tag_fifo <= shift_left(r.tag_fifo);
      rin.tag_fifo(r.tag_fillness-1) <= tag_v;
    elsif tag_push then
      rin.tag_fifo(r.tag_fillness) <= tag_v;
      rin.tag_fillness <= r.tag_fillness + 1;
    elsif tag_pop then
      rin.tag_fifo <= shift_left(r.tag_fifo);
      rin.tag_fillness <= r.tag_fillness - 1;
    end if;

    if fifo_push and fifo_pop then
      rin.fifo <= r.fifo(1 to fifo_depth_c-1) & r.fifo(fifo_depth_c-1);
      rin.fifo(r.fifo_fillness-1) <= in_i;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= in_i;
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
    if rising_edge(clock_i) then
      if reset_n_i = '1' then
        assert not (sfd_i = '1' and r.tag_fillness = 0)
          report "SFD strobed with no tag queued"
          severity failure;

        assert not (r.state = ST_TAG
                    and is_valid(config_c, in_i)
                    and is_last(config_c, in_i))
          report "Packet carries a tag block and no frame"
          severity failure;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    out_o <= transfer(config_c, r.fifo(0),
                      force_valid => true,
                      valid => r.fifo_fillness /= 0);

    case r.state is
      when ST_RESET =>
        in_o <= accept(config_c, false);

      when ST_TAG =>
        in_o <= accept(config_c, r.tag_fillness < tag_fifo_depth_c);

      when ST_FORWARD =>
        in_o <= accept(config_c, r.fifo_fillness < fifo_depth_c);
    end case;

    strobe_o <= r.strobe;
    id_o <= r.strobe_id;
  end process;

end architecture;
