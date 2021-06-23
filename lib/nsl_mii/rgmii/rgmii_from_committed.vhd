library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_mii, nsl_data, nsl_math;
use nsl_mii.rgmii.all;

entity rgmii_from_committed is
  generic(
    ipg_c : natural := 96/8
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    committed_i : in nsl_bnoc.committed.committed_req;
    committed_o : out nsl_bnoc.committed.committed_ack;

    rgmii_o : out rgmii_pipe
    );
end entity;

architecture beh of rgmii_from_committed is

  type state_t is (
    ST_RESET,
    ST_IPG,
    ST_IDLE,
    ST_PRE,
    ST_FORWARD,
    ST_PAD,
    ST_FCS
    );

  constant min_size : natural := 64;
  constant max_pad : natural := min_size - 4; -- FCS is always here
  constant ctr_max : natural := nsl_math.arith.max(max_pad-1, ipg_c-1);
  constant pad_byte : std_ulogic_vector(7 downto 0) := x"00";
  constant pre_byte : std_ulogic_vector(7 downto 0) := x"55";
  constant sfd_byte : std_ulogic_vector(7 downto 0) := x"d5";
  
  type regs_t is
  record
    state : state_t;
    tx_error : std_ulogic;
    tx_buf : std_ulogic_vector(7 downto 0);
    ctr : natural range 0 to ctr_max;
    fcs : nsl_data.crc.crc32;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, committed_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IPG;
        rin.ctr <= ipg_c - 1;

      when ST_IPG =>
        if r.ctr /= 0 then
          rin.ctr <= r.ctr - 1;
        else
          rin.state <= ST_IDLE;
        end if;

      when ST_IDLE =>
        if committed_i.valid = '1' then
          rin.state <= ST_PRE;
          rin.ctr <= 7;
          rin.tx_buf <= committed_i.data;
          rin.tx_error <= '0';
        end if;

      when ST_PRE =>
        if r.ctr /= 0 then
          rin.ctr <= r.ctr - 1;
        else
          rin.state <= ST_FORWARD;
          rin.fcs <= nsl_data.crc.crc_ieee_802_3_init;
          rin.ctr <= max_pad - 1;
        end if;

      when ST_FORWARD =>
        rin.fcs <= nsl_data.crc.crc_ieee_802_3_update(r.fcs, nsl_data.bytestream.from_suv(r.tx_buf));

        if r.ctr /= 0 then
          rin.ctr <= r.ctr - 1;
        end if;

        if committed_i.valid = '0' then
          rin.tx_error <= '1';
          rin.tx_buf <= pad_byte;
        else
          rin.tx_buf <= committed_i.data;

          if committed_i.last = '1' then
            rin.tx_buf <= pad_byte;

            if committed_i.data(0) /= '1' then
              rin.tx_error <= '1';
            end if;

            if r.ctr /= 0 then
              rin.state <= ST_PAD;
            else
              rin.ctr <= 3;
              rin.state <= ST_FCS;
            end if;
          end if;
        end if;

      when ST_PAD =>
        rin.fcs <= nsl_data.crc.crc_ieee_802_3_update(r.fcs, nsl_data.bytestream.from_suv(r.tx_buf));
        rin.tx_buf <= pad_byte;

        if r.ctr /= 0 then
          rin.ctr <= r.ctr - 1;
        else
          rin.state <= ST_FCS;
          rin.ctr <= 3;
        end if;

      when ST_FCS =>
        rin.fcs <= nsl_data.crc.crc32("--------" & std_ulogic_vector(r.fcs(31 downto 8)));
        if r.ctr /= 0 then
          rin.ctr <= r.ctr - 1;
        else
          rin.state <= ST_IPG;
          rin.ctr <= ipg_c - 1;
        end if;
    end case;
  end process;

  rgmii_o.clock <= clock_i;
  
  mealy: process(r)
  begin
    rgmii_o.valid <= '0';
    rgmii_o.error <= '0';
    rgmii_o.data <= (others => '0');
    committed_o.ready <= '0';

    case r.state is
      when ST_RESET | ST_IPG =>
        null;

      when ST_IDLE =>
        committed_o.ready <= '1';

      when ST_PRE =>
        rgmii_o.error <= '0';
        rgmii_o.valid <= '1';
        if r.ctr = 0 then
          rgmii_o.data <= sfd_byte;
        else
          rgmii_o.data <= pre_byte;
        end if;

      when ST_FORWARD =>
        rgmii_o.error <= r.tx_error;
        rgmii_o.valid <= '1';
        rgmii_o.data <= r.tx_buf;
        committed_o.ready <= '1';

      when ST_PAD =>
        rgmii_o.error <= r.tx_error;
        rgmii_o.valid <= '1';
        rgmii_o.data <= r.tx_buf;

      when ST_FCS =>
        rgmii_o.error <= r.tx_error;
        rgmii_o.valid <= '1';
        rgmii_o.data <= std_ulogic_vector(r.fcs(7 downto 0));
    end case;
  end process;

end architecture;
