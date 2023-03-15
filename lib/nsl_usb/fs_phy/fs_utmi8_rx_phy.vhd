-- Original Verilog implementation:
--   Copyright (C) 2000-2002 Rudolf Usselmann, www.asics.ws, <rudi@asics.ws>
--
-- Translation to VHDL, adaptation to 60MHz reference clock:
--   Copyright (C) 2011 Martin Neumann <martin@neumnns-mail.de>
--
-- 48/60MHz Merge, type cleanup for integration in NSL:
--   Copyright (c) 2021 Nicolas Pouillon

-- This source file may be used and distributed without restriction
-- provided that this copyright statement is not removed from the file
-- and that any derivative work contains the original copyright notice
-- and the associated disclaimer.
--                                                              
-- THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY EXPRESS OR
-- IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR
-- ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
-- OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
-- BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
-- LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
-- (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
-- USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
-- DAMAGE.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data;
use nsl_usb.usb.all;
use nsl_data.bytestream.byte;

entity fs_utmi8_rx_phy is
  generic (
    ref_clock_mhz_c : integer := 60
    );
  port (
    clock_i             : in  std_ulogic;
    reset_n_i             : in  std_ulogic;

    fs_ce_o         : out std_ulogic;
    bus_i : nsl_usb.io.usb_io_s;

    datain_o        : out byte;
    rxvalid_o       : out std_ulogic;
    rxactive_o      : out std_ulogic;
    rxerror_o       : out std_ulogic;
    rx_en_i          : in  std_ulogic;
    linestate : out nsl_usb.usb.usb_symbol_t
  );
end fs_utmi8_rx_phy;

architecture rtl of fs_utmi8_rx_phy is

  type state_t is (
    FS_IDLE,
    K1,
    J1,
    K2,
    J2,
    K3,
    J3,
    K4
    );
 
  signal fs_ce                              : std_ulogic;
  signal rxd_s0, rxd_s1, rxd_s              : std_ulogic;
  signal rxdp_s0, rxdp_s1, rxdp_s, rxdp_s_r : std_ulogic;
  signal rxdn_s0, rxdn_s1, rxdn_s, rxdn_s_r : std_ulogic;
  signal synced_d                           : std_ulogic;
  signal k, j, se0                          : std_ulogic;
  signal rxd_r                              : std_ulogic;
  signal rx_en                              : std_ulogic;
  signal rx_active                          : std_ulogic;
  signal bit_cnt                            : unsigned(2 downto 0);
  signal rx_valid1, rx_valid                : std_ulogic;
  signal shift_en                           : std_ulogic;
  signal sd_r                               : std_ulogic;
  signal sd_nrzi                            : std_ulogic;
  signal hold_reg                           : byte;
  signal drop_bit                           : std_ulogic;    -- Indicates a stuffed bit
  signal one_cnt                            : unsigned(2 downto 0);
  signal change                             : std_ulogic;
  signal lock_en                            : std_ulogic;
  signal fs_state, fs_next_state            : state_t;
  signal rx_valid_r                         : std_ulogic;
  signal sync_err_d, sync_err               : std_ulogic;
  signal bit_stuff_err, byte_err            : std_ulogic;
  signal se0_r, se0_s                       : std_ulogic;

  signal linestate_01 : std_ulogic_vector(1 downto 0);

  signal rxd, rxdp, rxdn : std_ulogic;
  
begin

  rxdp <= to_x01(bus_i.dp);
  rxdn <= to_x01(bus_i.dm);
  rxd <= rxdp and not rxdn;
 
  --====================================================================================--
  -- Misc Logic                                                                         --
  --====================================================================================--
 
  fs_ce_o    <= fs_ce;
  RxActive_o <= rx_active;
  RxValid_o  <= rx_valid;
  RxError_o  <= sync_err or bit_stuff_err or byte_err;
  DataIn_o   <= hold_reg;

  linestate_01 <= to_x01(rxdn_s1 & rxdp_s1);
  with linestate_01 select
    linestate <=
      USB_SYMBOL_SE0 when "00",
      USB_SYMBOL_J when "01",
      USB_SYMBOL_K when "10",
      USB_SYMBOL_SE1 when others;
 
  p_rx_en: process (clock_i)
  begin
    if rising_edge(clock_i) then
      rx_en <= rx_en_i;
    end if;
  end process;
 
  p_sync_err: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      sync_err <= '0';
    elsif rising_edge(clock_i) then
      sync_err <= not rx_active and sync_err_d;
    end if;
  end process;
 
  --====================================================================================--
  -- Synchronize Inputs                                                                 --
  --====================================================================================--
 
  -- First synchronize to the local system clock to
  -- avoid metastability outside the sync block (*_s0).
  -- Then make sure we see the signal for at least two
  -- clock cycles stable to avoid glitches and noise
 
  p_rxd_s: process (clock_i) -- Avoid detecting Line Glitches and noise
  begin
    if rising_edge(clock_i) then
        rxd_s0 <= rxd;
        rxd_s1 <= rxd_s0;
        if rxd_s0 ='1' and rxd_s1 ='1' then
          rxd_s <= '1';
        elsif not rxd_s0 ='1' and not rxd_s1 ='1' then
          rxd_s <= '0';
        end if;
    end if;
  end process;
 
  p_rxdp_s: process (clock_i)
  begin
    if rising_edge(clock_i) then
      rxdp_s0  <= rxdp;
      rxdp_s1  <= rxdp_s0;
      rxdp_s_r <= rxdp_s0 and rxdp_s1;
      rxdp_s   <= (rxdp_s0 and rxdp_s1) or rxdp_s_r;
    end if;
  end process;
 
  p_rxdn_s: process (clock_i)
  begin
    if rising_edge(clock_i) then
      rxdn_s0  <= rxdn;
      rxdn_s1  <= rxdn_s0;
      rxdn_s_r <= rxdn_s0 and rxdn_s1;
      rxdn_s   <= (rxdn_s0 and rxdn_s1) or rxdn_s_r;
    end if;
  end process;
 
  j   <=     rxdp_s and not rxdn_s;
  k   <= not rxdp_s and     rxdn_s;
  se0 <= not rxdp_s and not rxdn_s;
 
  p_se0_s: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      se0_s <= '0';
    elsif rising_edge(clock_i) then
      if fs_ce ='1' then
        se0_s   <= se0;
      end if;
    end if;
  end process;
 
  --====================================================================================--
  -- DPLL                                                                               --
  --====================================================================================--

  dpll_60: if ref_clock_mhz_c = 60
  generate
    signal dpll_cntr : unsigned(3 downto 0);
  begin
    -- This design uses a clock enable to do 12Mhz timing and not a
    -- real 12Mhz clock. Everything always runs at 60 Mhz. We want to
    -- make sure however, that the clock enable is always exactly in
    -- the middle between two virtual 12Mhz rising edges.
    -- We monitor rxdp and rxdn for any changes and do the appropiate
    -- adjustments.

    lock_en <= rx_en; -- Allow clock adjustments only when we are receiving

    p_rxd_r: process (clock_i)
    begin
      if rising_edge(clock_i) then
        rxd_r   <= rxd_s;
      end if;
    end process;

    change  <= rxd_r xor rxd_s; -- Edge detector

    p_dpll_cntr: process (clock_i, reset_n_i)
    begin
      if reset_n_i ='0' then
        dpll_cntr <= "0011";
      elsif rising_edge(clock_i) then
        if lock_en = '1' and change = '1' then
          if dpll_cntr(3)='1' then
            dpll_cntr <= "0010";       -- fe_ce detected, now centered in following cycle
          else
            dpll_cntr <= "0111";       -- adjust fe_ce to center cycle
          end if;
        elsif dpll_cntr(3) = '1' then  -- normal count sequence is 8->4->5->6->7->8->4...
          dpll_cntr <= "0100";
        else
          dpll_cntr <= dpll_cntr +1;
        end if;
      end if;
    end process;

    fs_ce <= dpll_cntr(3);
  end generate;

  dpll_48: if ref_clock_mhz_c = 48
  generate
    signal dpll_state, dpll_next_state        : std_ulogic_vector(1 downto 0);
    signal fs_ce_d                            : std_ulogic;
    signal fs_ce_r1, fs_ce_r2                 : std_ulogic;
  begin
    -- This design uses a clock enable to do 12Mhz timing and not a
    -- real 12Mhz clock. Everything always runs at 48Mhz. We want to
    -- make sure however, that the clock enable is always exactly in
    -- the middle between two virtual 12Mhz rising edges.
    -- We monitor rxdp and rxdn for any changes and do the appropiate
    -- adjustments.
    -- In addition to the locking done in the dpll FSM, we adjust the
    -- final latch enable to compensate for various sync registers ...

    lock_en <= rx_en; -- Allow clock adjustments only when we are receiving

    p_rxd_r: process (clock_i)
    begin
      if rising_edge(clock_i) then
        rxd_r   <= rxd_s;
      end if;
    end process;

    change  <= rxd_r xor rxd_s; -- Edge detector

    -- DPLL FSM
    p_dpll_state: process (clock_i, reset_n_i)
    begin
      if reset_n_i ='0' then
        dpll_state <= "01";
      elsif rising_edge(clock_i) then
        dpll_state <= dpll_next_state;
      end if;
    end process;

    p_dpll_next_state: process (dpll_state, lock_en, change)
    begin
      case (dpll_state) is
        when "00" =>
          if ((lock_en = '1') and (change = '1')) then
            dpll_next_state <= "00";
          else
            dpll_next_state <= "01";
          end if;
        when "01" =>
          if ((lock_en = '1') and (change = '1')) then
            dpll_next_state <= "11";
          else
            dpll_next_state <= "10";
          end if;
        when "10" =>
          if ((lock_en = '1') and (change = '1')) then
            dpll_next_state <= "00";
          else
            dpll_next_state <= "11";
          end if;
        when OTHERS =>
          dpll_next_state <= "00";
      end case;
    end process;

    fs_ce_d <= '1' when dpll_state = "01" else '0';

    -- Compensate for sync registers at the input - allign full speed ...
    -- ... clock enable to be in the middle between two bit changes :

    p_fs_ce: process (clock_i)
    begin
      if rising_edge(clock_i) then
        fs_ce_r1  <= fs_ce_d;
        fs_ce_r2  <= fs_ce_r1;
        fs_ce <= fs_ce_r2;
      end if;
    end process;

  end generate;

  dpll_other: if ref_clock_mhz_c /= 60 and ref_clock_mhz_c /= 48
  generate
    assert false
      report "Unimplemented clock rate"
      severity failure;
  end generate;
 
  --====================================================================================--
  -- Find Sync Pattern FSM                                                              --
  --====================================================================================--
 
  p_fs_state: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      fs_state  <= FS_IDLE;
    elsif rising_edge(clock_i) then
      fs_state  <= fs_next_state;
    end if;
  end process;
 
  p_fs_next_state: process (fs_state, fs_ce, k, j, rx_en, rx_active, se0, se0_s)
  begin
    if fs_ce='1' and  rx_active='0' and se0='0' and se0_s='0' then
      case fs_state is
        when FS_IDLE =>
          if k ='1' and rx_en ='1' then -- 0
            fs_next_state <= K1;
            sync_err_d    <= '0';
          else
            fs_next_state <= FS_IDLE;
            sync_err_d    <= '0';
          end if;
        when K1      =>
          if j ='1' and rx_en ='1' then -- 1
            fs_next_state <= J1;
            sync_err_d    <= '0';
          else
            fs_next_state <= FS_IDLE;
            sync_err_d    <= '1';
          end if;
        when J1      =>
          if k ='1' and rx_en ='1' then -- 2
            fs_next_state <= K2;
            sync_err_d    <= '0';
          else
            fs_next_state <= FS_IDLE;
            sync_err_d    <= '1';
          end if;
        when K2      =>
          if j ='1' and rx_en ='1' then -- 3
            fs_next_state <= J2;
            sync_err_d    <= '0';
          else
            fs_next_state <= FS_IDLE;
            sync_err_d    <= '1';
          end if;
        when J2      =>
          if k ='1' and rx_en ='1' then -- 4
            fs_next_state <= K3;
            sync_err_d    <= '0';
          else
            fs_next_state <= FS_IDLE;
            sync_err_d    <= '1';
          end if;
        when K3      =>
          if j ='1' and rx_en ='1' then -- 5
            fs_next_state <= J3;
            sync_err_d    <= '0';
          elsif k ='1' and rx_en ='1' then  -- Allow missing first K-J
            fs_next_state <= FS_IDLE;
            sync_err_d    <= '0';
          else
            fs_next_state <= FS_IDLE;
            sync_err_d    <= '1';
          end if;
        when J3      =>
          if k ='1' and rx_en ='1' then -- 6
            fs_next_state <= K4;
            sync_err_d    <= '0';
          else
            fs_next_state <= FS_IDLE;
            sync_err_d    <= '1';
          end if;
        when K4      =>
          if k ='1' and rx_en ='1' then -- 7
            sync_err_d    <= '0';
          else
            sync_err_d    <= '1';
          end if;
          fs_next_state <= FS_IDLE;
        when others  =>
          fs_next_state <= FS_IDLE;
          sync_err_d    <= '1';
      end case;
    else
      fs_next_state <= fs_state;
      sync_err_d    <= '0';
    end if;
  end process;
  
  synced_d  <= fs_ce and rx_en
               when (fs_state =K3 and k ='1') or  -- Allow missing first K-J
               (fs_state =K4 and k ='1') else '0';
 
  p_rx_active: process(clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      rx_active   <= '0';
    elsif rising_edge(clock_i) then
      if synced_d ='1' and rx_en ='1' then
        rx_active <= '1';
      elsif se0 ='1' and rx_valid_r ='1' then
        rx_active <= '0';
      end if;
    end if;
  end process;
 
  p_rx_valid_r: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      rx_valid_r <= '0';
    elsif rising_edge(clock_i) then
      if rx_valid ='1' then
        rx_valid_r      <= '1';
      elsif fs_ce ='1' then
        rx_valid_r      <= '0';
      end if;
    end if;
  end process;
 
  --====================================================================================--
  -- NRZI Decoder                                                                       --
  --====================================================================================--
 
  p_sd_r: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      sd_r <= '0';
    elsif rising_edge(clock_i) then
      if fs_ce ='1' then
        sd_r <= rxd_s;
      end if;
    end if;
  end process;
 
  p_sd_nrzi: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      sd_nrzi <= '0';
    elsif rising_edge(clock_i) then
      if rx_active ='0' then
        sd_nrzi <= '1';
      elsif rx_active ='1' and fs_ce ='1' then
        sd_nrzi <= not (rxd_s xor sd_r);
      end if;
    end if;
  end process;
 
  --====================================================================================--
  -- Bit Stuff Detect                                                                   --
  --====================================================================================--
 
  p_one_cnt: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      one_cnt <= "000";
    elsif rising_edge(clock_i) then
      if shift_en ='0' then
        one_cnt <= "000";
      elsif fs_ce ='1' then
        if sd_nrzi ='0' or drop_bit ='1' then
          one_cnt <= "000";
        else
          one_cnt <= one_cnt + 1;
        end if;
      end if;
    end if;
  end process;
 
  drop_bit <= '1' when one_cnt ="110" else '0';
 
  p_bit_stuff_err: process (clock_i, reset_n_i) -- Bit Stuff Error
  begin
    if reset_n_i ='0' then
      bit_stuff_err <= '0';
    elsif rising_edge(clock_i) then
      bit_stuff_err <= drop_bit and sd_nrzi and fs_ce and not se0 and rx_active;
    end if;
  end process;
 
  --====================================================================================--
  -- Serial => Parallel converter                                                       --
  --====================================================================================--
 
  p_shift_en: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      shift_en <= '0';
    elsif rising_edge(clock_i) then
      if fs_ce ='1' then
        shift_en <= synced_d or rx_active;
      end if;
    end if;
  end process;
 
  p_hold_reg: process (clock_i)
  begin
    if rising_edge(clock_i) then
      if fs_ce ='1' and shift_en ='1' and drop_bit ='0' then
        hold_reg <= sd_nrzi & hold_reg(7 downto 1);
      end if;
    end if;
  end process;
 
  --====================================================================================--
  -- Generate RxValid                                                                  --
  --====================================================================================--
 
  p_bit_cnt: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      bit_cnt <= "000";
    elsif rising_edge(clock_i) then
      if shift_en ='0' then
        bit_cnt <=  "000";
      elsif fs_ce ='1' and drop_bit ='0' then
        bit_cnt <= bit_cnt + 1;
      end if;
    end if;
  end process;
 
  p_rx_valid1: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      rx_valid1 <= '0';
    elsif rising_edge(clock_i) then
      if fs_ce ='1' and drop_bit ='0' and bit_cnt ="111" then
        rx_valid1 <= '1';
      elsif rx_valid1 ='1' and fs_ce ='1' and drop_bit ='0' then
        rx_valid1 <= '0';
      end if;
    end if;
  end process;
 
  p_rx_valid: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      rx_valid <= '0';
    elsif rising_edge(clock_i) then
      rx_valid <= not drop_bit and rx_valid1 and fs_ce;
    end if;
  end process;
 
  p_se0_r: process (clock_i)
  begin
    if rising_edge(clock_i) then
      se0_r <= se0;
    end if;
  end process;
 
  p_byte_err: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      byte_err <= '0';
    elsif rising_edge(clock_i) then
      byte_err <= se0 and not se0_r and (bit_cnt(1) or bit_cnt(2)) and rx_active;
    end if;
  end process;
 
end rtl;
