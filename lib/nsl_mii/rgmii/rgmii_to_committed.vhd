library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_mii, nsl_data, nsl_math;
use nsl_mii.rgmii.all;
use nsl_data.crc.all;
use nsl_data.bytestream.all;

entity rgmii_to_committed is
  port(
    clock_o : out std_ulogic;
    reset_n_i : in std_ulogic;

    committed_o : out nsl_bnoc.committed.committed_req;
    committed_i : in nsl_bnoc.committed.committed_ack;

    rgmii_i : in rgmii_pipe
    );
end entity;

architecture beh of rgmii_to_committed is

  constant pre_byte : std_ulogic_vector(7 downto 0) := x"55";
  constant sfd_byte : std_ulogic_vector(7 downto 0) := x"d5";

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WAIT_PRE,
    ST_WAIT_SFD,
    ST_FILL,
    ST_FORWARD,
    ST_DONE,
    ST_IGNORE
    );

  type regs_t is
  record
    state : state_t;
    rx_valid : std_ulogic;
    buf : nsl_data.bytestream.byte_string(0 to 4);
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

  transition: process(r, rgmii_i, committed_i)
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
            rin.rx_valid <= '1';
            rin.fcs <= crc_ieee_802_3_init;
            rin.state <= ST_FILL;
            rin.ctr <= 4;
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
          rin.fcs <= crc_ieee_802_3_update(r.fcs, from_suv(rgmii_i.data));
          rin.buf(4 to 4) <= nsl_data.bytestream.from_suv(rgmii_i.data);
          rin.buf(0 to 3) <= r.buf(1 to 4);
          if r.ctr /= 0 then
            rin.ctr <= r.ctr - 1;
          else
            rin.state <= ST_FORWARD;
          end if;
        end if;

      when ST_FORWARD =>
        -- Overrun condition
        if committed_i.ready = '0' then
          rin.rx_valid <= '0';
        end if;
        rin.fcs <= crc_ieee_802_3_update(r.fcs, from_suv(rgmii_i.data));
        rin.buf(4 to 4) <= nsl_data.bytestream.from_suv(rgmii_i.data);
        rin.buf(0 to 3) <= r.buf(1 to 4);

        if rgmii_i.valid = '0' then
          rin.state <= ST_DONE;

          if r.fcs /= crc_ieee_802_3_check then
            rin.rx_valid <= '0';
          end if;
        elsif rgmii_i.error = '1' then
          rin.rx_valid <= '0';
        end if;

      when ST_DONE =>
        -- At least wait intake of last=1
        if committed_i.ready = '1' then
          rin.state <= ST_IDLE;
        end if;
        
      when ST_IGNORE =>
        if rgmii_i.valid = '0' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  clock_o <= rgmii_i.clock;

  moore: process(r)
  begin
    committed_o.valid <= '0';
    committed_o.last <= '-';
    committed_o.data <= (others => '-');

    case r.state is
      when ST_FORWARD =>
        committed_o.last <= '0';
        committed_o.valid <= '1';
        committed_o.data <= r.buf(0);

      when ST_DONE =>
        committed_o.last <= '1';
        committed_o.valid <= '1';
        committed_o.data <= "0000000" & r.rx_valid;

      when others =>
    end case;
  end process;
  
end architecture;
