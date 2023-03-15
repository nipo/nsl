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

entity fs_utmi8_tx_phy is
  port (
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;
    fs_ce     : in std_ulogic;
    diff_mode_i  : in std_ulogic;

    bus_o : out nsl_usb.io.usb_io_c; 

    dataout_i : in  byte;
    txvalid_i : in  std_ulogic;
    txready_o : out std_ulogic
  );
end fs_utmi8_tx_phy;
 
architecture rtl of fs_utmi8_tx_phy is

  type state_t is (
    ST_IDLE,
    ST_SOP ,
    ST_DATA,
    ST_WAIT,
    ST_EOP0,
    ST_EOP1,
    ST_EOP2,
    ST_EOP3,
    ST_EOP4,
    ST_EOP5
    );
  
  signal hold_reg           : byte;
  signal ld_data            : std_ulogic;
  signal ld_data_d          : std_ulogic;
  signal ld_sop_d           : std_ulogic;
  signal bit_cnt            : unsigned(2 downto 0);
  signal sft_done_e         : std_ulogic;
  signal append_eop         : std_ulogic;
  signal data_xmit          : std_ulogic;
  signal hold_reg_d         : byte;
  signal one_cnt            : unsigned(2 downto 0);
  signal sd_bs_o            : std_ulogic;
  signal sd_nrzi_o          : std_ulogic;
  signal sd_raw_o           : std_ulogic;
  signal sft_done           : std_ulogic;
  signal sft_done_r         : std_ulogic;
  signal state              : state_t;
  signal stuff              : std_ulogic;
  signal tx_ip              : std_ulogic;
  signal tx_ip_sync         : std_ulogic;
  signal txoe_n_1, txoe_n_2   : std_ulogic;
 
begin
 
  bus_o.dp_pullup_en <= '-';

--======================================================================================--
  -- misc logic                                                                         --
--======================================================================================--
 
  p_txready_o: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      txready_o <= '0';
    elsif rising_edge(clock_i) then
      txready_o <= ld_data_d and txvalid_i;
    end if;
  end process;
 
  p_ld_data: process (clock_i)
  begin
    if rising_edge(clock_i) then
      ld_data <= ld_data_d;
    end if;
  end process;
 
--======================================================================================--
  -- transmit in progress indicator                                                     --
--======================================================================================--
 
  p_tx_ip: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      tx_ip <= '0';
    elsif rising_edge(clock_i) then
      if ld_sop_d  ='1' then
        tx_ip <= '1';
      elsif append_eop ='1' then
        tx_ip <= '0';
      end if;
    end if;
  end process;
 
  p_tx_ip_sync: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      tx_ip_sync <= '0';
    elsif rising_edge(clock_i) then
      if fs_ce ='1' then
        tx_ip_sync <= tx_ip;
      end if;
    end if;
  end process;
 
  -- data_xmit helps us to catch cases where txvalid drops due to
  -- packet end and then gets re-asserted as a new packet starts.
  -- we might not see this because we are still transmitting.
  -- data_xmit should solve those cases ...
  p_data_xmit: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      data_xmit <= '0';
    elsif rising_edge(clock_i) then
      if txvalid_i ='1' and tx_ip ='0' then
        data_xmit <= '1';
      elsif txvalid_i = '0' then
        data_xmit <= '0';
      end if;
    end if;
  end process;
 
--======================================================================================--
  -- shift register                                                                     --
--======================================================================================--
 
  p_bit_cnt: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      bit_cnt <= "000";
    elsif rising_edge(clock_i) then
      if tx_ip_sync ='0' then
        bit_cnt <= "000";
      elsif fs_ce ='1' and stuff ='0' then
        bit_cnt <= bit_cnt + 1;
      end if;
    end if;
  end process;
 
  p_sd_raw_o: process (clock_i)
  begin
    if rising_edge(clock_i) then
      if tx_ip_sync ='0' then
        sd_raw_o <= '0';
      else
        sd_raw_o <= hold_reg_d(to_integer(bit_cnt));
      end if;
    end if;
  end process;
 
  p_sft_done: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      sft_done   <= '0';
      sft_done_r <= '0';
    elsif rising_edge(clock_i) then
      if bit_cnt = "111" then
        sft_done <= not stuff;
      else
        sft_done <= '0';
      end if;
      sft_done_r <= sft_done;
    end if;
  end process;
 
  sft_done_e <= sft_done and not sft_done_r;
 
  -- out data hold register
  p_hold_reg: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
        hold_reg   <= x"00";
        hold_reg_d <= x"00";
    elsif rising_edge(clock_i) then
      if ld_sop_d ='1' then
        hold_reg <= x"80";
      elsif ld_data ='1' then
        hold_reg <= dataout_i;
      end if;
      hold_reg_d <= hold_reg;
    end if;
  end process;
 
--======================================================================================--
  -- bit stuffer                                                                        --
--======================================================================================--
 
  p_one_cnt: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      one_cnt <= "000";
    elsif rising_edge(clock_i) then
      if tx_ip_sync ='0' then
        one_cnt <= "000";
      elsif fs_ce ='1' then
        if sd_raw_o ='0' or stuff = '1' then
          one_cnt <= "000";
        else
          one_cnt <= one_cnt + 1;
        end if;
      end if;
    end if;
  end process;
 
  stuff   <= '1' when one_cnt = "110" else '0';
 
  p_sd_bs_o: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      sd_bs_o <= '0';
    elsif rising_edge(clock_i) then
      if fs_ce ='1' then
        if tx_ip_sync ='0' then
          sd_bs_o <= '0';
        else
          if stuff ='1' then
            sd_bs_o <= '0';
          else
            sd_bs_o <= sd_raw_o;
          end if;
        end if;
      end if;
    end if;
  end process;
 
--======================================================================================--
  -- nrzi encoder                                                                       --
--======================================================================================--
 
  p_sd_nrzi_o: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      sd_nrzi_o <= '1';
    elsif rising_edge(clock_i) then
      if tx_ip_sync ='0' or txoe_n_1 ='0' then
        sd_nrzi_o <= '1';
      elsif fs_ce ='1' then
        if sd_bs_o ='1' then
          sd_nrzi_o <= sd_nrzi_o;
        else
          sd_nrzi_o <= not sd_nrzi_o;
        end if;
      end if;
    end if;
  end process;
 
--======================================================================================--
  -- output enable logic                                                                --
--======================================================================================--
 
  p_txoe_n_o: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      txoe_n_1 <= '0';
      txoe_n_2 <= '0';
      bus_o.oe    <= '0';
    elsif rising_edge(clock_i) then
      if fs_ce ='1' then
        txoe_n_1 <= tx_ip_sync;
        txoe_n_2 <= txoe_n_1;
        bus_o.oe <= txoe_n_1 or txoe_n_2;
      end if;
    end if;
  end process;
 
--======================================================================================--
  -- output registers                                                                   --
--======================================================================================--
 
  p_txdpn: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      bus_o.dp <= '1';
      bus_o.dm <= '0';
    elsif rising_edge(clock_i) then
      if fs_ce ='1' then
        if diff_mode_i = '1' then
          bus_o.dp <= not append_eop and     sd_nrzi_o;
          bus_o.dm <= not append_eop and not sd_nrzi_o;
        else
          bus_o.dp <= sd_nrzi_o;
          bus_o.dm <= append_eop;
        end if;
      end if;
    end if;
  end process;
 
--======================================================================================--
  -- tx statemashine                                                                    --
--======================================================================================--
 
  p_state: process (clock_i, reset_n_i)
  begin
    if reset_n_i ='0' then
      state <= ST_IDLE;
    elsif rising_edge(clock_i) then
      case (state) is
        when ST_IDLE =>
          if txvalid_i ='1' then
            state <= ST_SOP;
          end if;

        when ST_SOP  =>
          if sft_done_e ='1' then
            state <= ST_DATA;
          end if;

        when ST_DATA =>
          if data_xmit ='0' and sft_done_e ='1' then
            if one_cnt = "101" and hold_reg_d(7) = '1' then
              state <= ST_EOP0;
            else
              state <= ST_EOP1;
            end if;
          end if;

        when ST_WAIT =>
            if fs_ce = '1' then
              state <= ST_IDLE;
            end if;

        when ST_EOP0 =>
          if fs_ce ='1' then
            state <= ST_EOP1;
          end if;

        when ST_EOP1 =>
          if fs_ce ='1' then
            state <= ST_EOP2;
          end if;

        when ST_EOP2 =>
          if fs_ce ='1' then
            state <= ST_EOP3;
          end if;

        when ST_EOP3 =>
          if fs_ce ='1' then
            state <= ST_EOP4;
          end if;

        when ST_EOP4 =>
          if fs_ce ='1' then
            state <= ST_EOP5;
          end if;

        when ST_EOP5 =>
          if fs_ce ='1' then
            state <= ST_WAIT;
          end if;
      end case;
    end if;
  end process;
 
  append_eop <= '1' when state = ST_EOP5 or state = ST_EOP4 else '0';
  ld_sop_d   <= txvalid_i  when state = ST_IDLE else '0';
  ld_data_d  <= sft_done_e when state = ST_SOP or (state = ST_DATA and data_xmit ='1') else '0';
 
end rtl;
