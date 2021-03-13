library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_mii, nsl_data, nsl_math;
use nsl_mii.rgmii.all;
use nsl_data.crc.all;

entity rgmii_to_framed is
  port(
    clock_o : out std_ulogic;
    reset_n_i : in std_ulogic;

    valid_o : out std_ulogic;
    framed_o : out nsl_bnoc.framed.framed_req;
    framed_i : in nsl_bnoc.framed.framed_ack;

    rgmii_i : in rgmii_pipe
    );
end entity;

architecture beh of rgmii_to_framed is

  constant pre_byte : std_ulogic_vector(7 downto 0) := x"55";
  constant sfd_byte : std_ulogic_vector(7 downto 0) := x"d5";

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WAIT_PRE,
    ST_WAIT_SFD,
    ST_FILL,
    ST_FORWARD,
    ST_VALID,
    ST_INVALID,
    ST_IGNORE
    );

  type regs_t is
  record
    state : state_t;
    buf : nsl_data.bytestream.byte_string(0 to 5);
    fcs : crc32;
    ctr : natural range 0 to 7;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(reset_n_i, rgmii_i.clock)
  begin
    if rising_edge(rgmii_i.clock) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, rgmii_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if rgmii_i.valid = '1' then
          rin.state <= ST_WAIT_PRE;
          -- Allow first PRE byte to come within 8 next bytes
          rin.ctr <= 7;
        end if;

      when ST_WAIT_PRE =>
        if rgmii_i.valid = '0' then
          rin.state <= ST_IDLE;
        elsif rgmii_i.data = pre_byte then
          rin.state <= ST_WAIT_SFD;
          -- Allow SFD to come after 5 PRE
          rin.ctr <= 4;
        elsif r.ctr /= 0 then
          rin.ctr <= r.ctr - 1;
        else
          rin.state <= ST_IGNORE;
        end if;

      when ST_WAIT_SFD =>
        if rgmii_i.valid = '0' then
          rin.state <= ST_IDLE;
        elsif rgmii_i.data = sfd_byte then
          if r.ctr = 0 then
            rin.fcs <= crc_ieee_802_3_init;
            rin.state <= ST_FILL;
            rin.ctr <= 5;
          else
            rin.state <= ST_IGNORE;
          end if;
        elsif rgmii_i.data = pre_byte then
          if r.ctr /= 0 then
            rin.ctr <= r.ctr - 1;
          end if;
        else
          rin.state <= ST_IGNORE;
        end if;

      when ST_FILL =>
        if rgmii_i.valid = '0' then
          rin.state <= ST_IDLE;
        else
          rin.fcs <= crc_ieee_802_3_update(r.fcs, nsl_data.bytestream.from_suv(rgmii_i.data));
          rin.buf(5 to 5) <= nsl_data.bytestream.from_suv(rgmii_i.data);
          rin.buf(0 to 4) <= r.buf(1 to 5);
          if r.ctr /= 0 then
            rin.ctr <= r.ctr - 1;
          else
            rin.state <= ST_FORWARD;
          end if;
        end if;

      when ST_FORWARD =>
        if rgmii_i.valid = '1' then
          rin.fcs <= crc_ieee_802_3_update(r.fcs, nsl_data.bytestream.from_suv(rgmii_i.data));
          rin.buf(5 to 5) <= nsl_data.bytestream.from_suv(rgmii_i.data);
          rin.buf(0 to 4) <= r.buf(1 to 5);
        else
          if r.fcs = crc_ieee_802_3_check then
            rin.state <= ST_VALID;
          else
            rin.state <= ST_INVALID;
          end if;
        end if;

      when ST_VALID =>
        rin.state <= ST_IDLE;

      when ST_INVALID =>
        rin.state <= ST_IDLE;
        
      when ST_IGNORE =>
        if rgmii_i.valid = '0' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  clock_o <= rgmii_i.clock;

  moore: process(r)
  begin
    framed_o.valid <= '0';
    framed_o.last <= '-';
    framed_o.data <= (others => '-');
    valid_o <= '-';

    case r.state is
      when ST_FORWARD =>
        framed_o.last <= '0';
        framed_o.valid <= '1';
        framed_o.data <= r.buf(0);

      when ST_VALID =>
        valid_o <= '1';
        framed_o.last <= '1';
        framed_o.valid <= '1';
        framed_o.data <= r.buf(0);

      when ST_INVALID =>
        valid_o <= '0';
        framed_o.last <= '1';
        framed_o.valid <= '1';
        framed_o.data <= r.buf(0);

      when others =>
    end case;
  end process;
  
end architecture;
