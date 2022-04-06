library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_mii, nsl_logic, nsl_bnoc;
use nsl_logic.bool.all;
use nsl_mii.mii.all;
use nsl_logic.bool.all;

entity mii_driver_oversampled is
  generic(
    ipg_c : natural := 96 --bits
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    rx_sfd_o: out std_ulogic;
    tx_sfd_o: out std_ulogic;

    mii_o : out mii_m2p;
    mii_i : in  mii_p2m;

    rx_o : out nsl_bnoc.committed.committed_req;
    rx_i : in nsl_bnoc.committed.committed_ack;

    tx_i : in nsl_bnoc.committed.committed_req;
    tx_o : out nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of mii_driver_oversampled is

  type mii_rx_pipe_t is array (integer range <>) of mii_rx_p2m;

  signal tx_flit_s: mii_flit_t;

  type rx_state_t is (
    RX_INTERFRAME,
    RX_PREAMBLE,
    RX_FRAME
    );
  
  type regs_t is
  record
    last_rx_clock, last_tx_clock: std_ulogic;

    rx_pipe: mii_rx_pipe_t(0 to 2);
    rx_is_msb, rx_is_sfd: boolean;
    rx_state: rx_state_t;
    rx_flit : mii_flit_t;
    rx_flit_valid : std_ulogic;

    tx_flit: mii_flit_t;
    tx_is_msb: boolean;
    tx_new_frame, tx_sfd: boolean;
    tx_pop: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin
  
  rx_regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.rx_state <= RX_INTERFRAME;
      r.rx_is_msb <= false;

      r.tx_is_msb <= false;
    end if;
  end process;

  transition: process(r, mii_i, tx_flit_s) is
  begin
    rin <= r;

    rin.last_tx_clock <= mii_i.tx.clk;
    rin.last_rx_clock <= mii_i.rx.clk;
    rin.rx_is_sfd <= false;

    rin.rx_flit_valid <= '0';
    if r.last_rx_clock = '0' and mii_i.rx.clk = '1' then
      rin.rx_pipe <= r.rx_pipe(1 to 2) & mii_i.rx;

      -- One cycle out of 2 makes flit valid
      rin.rx_is_msb <= not r.rx_is_msb;
      rin.rx_flit_valid <= to_logic(r.rx_is_msb);

      -- Merge two consecutive cycles
      rin.rx_flit.data <= r.rx_pipe(1).d & r.rx_pipe(0).d;
      rin.rx_flit.valid <= r.rx_pipe(0).dv and r.rx_pipe(1).dv;
      rin.rx_flit.error <= r.rx_pipe(0).er or r.rx_pipe(1).er;

      case r.rx_state is
        when RX_INTERFRAME =>
          if r.rx_pipe(0).dv = '1' and r.rx_pipe(1).dv = '1' then
            rin.rx_state <= RX_PREAMBLE;
          end if;

        when RX_PREAMBLE =>
          if r.rx_pipe(0).dv = '1' and r.rx_pipe(1).dv = '1' and
            r.rx_pipe(0).d = x"5" and r.rx_pipe(1).d = x"d" then
            rin.rx_is_sfd <= true;
            rin.rx_state <= RX_FRAME;
            rin.rx_is_msb <= false;
            rin.rx_flit_valid <= '1';
          end if;

        when RX_FRAME =>
          null;
      end case;

      -- Common
      if r.rx_pipe(0).dv = '0' and r.rx_pipe(1).dv = '0' then
        rin.rx_state <= RX_INTERFRAME;
      end if;
    end if;


    rin.tx_sfd <= false;

    if tx_flit_s.valid = '0' then
      rin.tx_new_frame <= true;
    elsif r.tx_new_frame and tx_flit_s.data = x"d5" then
      rin.tx_new_frame <= false;
      rin.tx_sfd <= true;
    end if;
    
    rin.tx_pop <= '0';
    if r.last_tx_clock = '0' and mii_i.tx.clk = '1' then
      rin.tx_is_msb <= not r.tx_is_msb;
      if r.tx_is_msb then
        rin.tx_flit <= tx_flit_s;
        rin.tx_pop <= '1';
      end if;
    end if;
  end process;

  rx_sfd_o <= to_logic(r.rx_is_sfd);
  tx_sfd_o <= to_logic(r.tx_sfd);

  mii_o.tx.d <= r.tx_flit.data(7 downto 4)
                when r.tx_is_msb else r.tx_flit.data(3 downto 0);
  mii_o.tx.en <= r.tx_flit.valid;
  mii_o.tx.er <= r.tx_flit.error;

  rx_to_committed: work.mii.mii_flit_to_committed
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      flit_i => r.rx_flit,
      valid_i => r.rx_flit_valid,

      committed_o => rx_o,
      committed_i => rx_i
      );
  
  tx_from_committed: work.mii.mii_flit_from_committed
    generic map(
      ipg_c => ipg_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      committed_i => tx_i,
      committed_o => tx_o,

      flit_o => tx_flit_s,
      ready_i => r.tx_pop
      );
      
end architecture;
