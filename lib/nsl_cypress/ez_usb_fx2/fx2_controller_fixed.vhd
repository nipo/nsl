library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic;
library nsl_cypress;
use nsl_cypress.ez_usb_fx2.all;

entity fx2_controller_fixed is
  generic(
    axi_cfg_c           : nsl_amba.axi4_stream.config_t;
    rx_ep_c             : fx2_ep_t   := FX2_EP2;
    rx_empty_flag_c     : fx2_flag_t := FX2_FLAGA;
    tx_ep_c             : fx2_ep_t   := FX2_EP6;
    tx_full_flag_c      : fx2_flag_t := FX2_FLAGB;
    addr_change_delay_c : natural := 0
    );
  port(
    clock_i    : in std_ulogic;
    reset_n_i  : in std_ulogic;
    
    tx_i       : in nsl_amba.axi4_stream.master_t;
    tx_o       : out nsl_amba.axi4_stream.slave_t;
    
    rx_o       : out nsl_amba.axi4_stream.master_t;
    rx_i       : in nsl_amba.axi4_stream.slave_t;

    to_fx2_o   : out fx2_i;
    from_fx2_i : in  fx2_flags_o;

    addr_change_done_i : in std_ulogic := '1'
    );
end entity;

architecture rtl of fx2_controller_fixed is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WAIT_ADDR,
    ST_W_STATE1,
    ST_W_STATE2,
    ST_R_STATE1,
    ST_R_STATE2,
    ST_R_STATE3
    );

  type regs_t is record
    state   : state_t;
    data    : std_ulogic_vector(7 downto 0);
    last    : boolean;
    addr    : fx2_addr_t;
    count   : natural range 0 to addr_change_delay_c;
  end record;
  signal r, rin: regs_t;

  signal rx_empty_n_s : std_ulogic;
  signal tx_full_n_s : std_ulogic;
begin

  -- flag assignment (TX - IN endpoint)
  with tx_full_flag_c select
    tx_full_n_s  <= from_fx2_i.flag_a when FX2_FLAGA,
                    from_fx2_i.flag_b when FX2_FLAGB,
                    from_fx2_i.flag_c when FX2_FLAGC,
                    from_fx2_i.flag_d when FX2_FLAGD,
                    '1' when others;

  -- flag assignment (RX - OUT endpoint)
  with rx_empty_flag_c select
    rx_empty_n_s <= from_fx2_i.flag_a when FX2_FLAGA,
                    from_fx2_i.flag_b when FX2_FLAGB,
                    from_fx2_i.flag_c when FX2_FLAGC,
                    from_fx2_i.flag_d when FX2_FLAGD,
                    '1' when others;
  
  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;  

  -- TODO make work for other axi stream configurations!!  
  transition: process(r, tx_i, rx_i, from_fx2_i, rx_empty_n_s, tx_full_n_s, addr_change_done_i)
    variable received_bytes : nsl_data.bytestream.byte_string(0 downto 0);
  begin
    rin <= r;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.data <= (others => '-');
        rin.last <= false;

      when ST_IDLE => -- Write has priority
        if tx_full_n_s = '1' and nsl_amba.axi4_stream.is_valid(axi_cfg_c, tx_i) then
          received_bytes := nsl_amba.axi4_stream.bytes(axi_cfg_c, tx_i);
          rin.data <= received_bytes(0);
          rin.last <= nsl_amba.axi4_stream.is_last(axi_cfg_c, tx_i);
          rin.addr  <= get_fifoaddr(tx_ep_c);
          if addr_change_delay_c = 0 then
            rin.state <= ST_W_STATE1;
          else
            rin.count <= addr_change_delay_c;
            rin.state <= ST_WAIT_ADDR;
          end if;
        elsif rx_empty_n_s = '1' and nsl_amba.axi4_stream.is_ready(axi_cfg_c, rx_i) then
          rin.addr  <= get_fifoaddr(rx_ep_c);
          rin.count <= addr_change_delay_c;
          if addr_change_delay_c = 0 then
            rin.state <= ST_R_STATE1;
          else
            rin.count <= addr_change_delay_c;
            rin.state <= ST_WAIT_ADDR;
          end if;
        end if;

      when ST_WAIT_ADDR =>
        if r.count = 0 then
          if r.addr = get_fifoaddr(tx_ep_c) then
            rin.state <= ST_W_STATE1;
          elsif r.addr = get_fifoaddr(rx_ep_c) then
            rin.state <= ST_R_STATE1;
          end if;
        else
          rin.count <= r.count - 1;
        end if;

      when ST_W_STATE1 => -- Set FIFO address to point to EP6 and wait for
                          -- address to be set
        if addr_change_done_i = '1' then
          rin.state <= ST_W_STATE2;
        end if;
        
      when ST_W_STATE2 => -- Write data to FX2 FD
        if tx_full_n_s = '1' and nsl_amba.axi4_stream.is_valid(axi_cfg_c, tx_i) then
          received_bytes := nsl_amba.axi4_stream.bytes(axi_cfg_c, tx_i);
          rin.data  <= received_bytes(0);
          rin.last  <= nsl_amba.axi4_stream.is_last(axi_cfg_c, tx_i);
        else
          rin.state <= ST_IDLE;
        end if;
        
      when ST_R_STATE1 => -- Set FIFO address to point to EP2 and wait for
                          -- address to be set
        if addr_change_done_i = '1' then
          rin.state <= ST_R_STATE2;
        end if;

      when ST_R_STATE2 => -- data is read from RX EP, but rx_empty_n_s does not yet represent if this is the last byte
        rin.data  <= from_fx2_i.data;
        rin.state <= ST_R_STATE3;
                
      when ST_R_STATE3 => -- write read data to rx_o, reading rx_empty_n_s to
                          -- see if this is the last byte.
        if nsl_amba.axi4_stream.is_ready(axi_cfg_c, rx_i) then
          if rx_empty_n_s = '1' then
            rin.state <= ST_R_STATE2;
          else
            rin.state <= ST_IDLE;
          end if;
        end if;
        
    end case;
  end process;

  moore: process (r)
    variable received_bytes : nsl_data.bytestream.byte_string(0 downto 0);
  begin
    to_fx2_o.addr   <= r.addr;
    to_fx2_o.data   <= (others => '-');
    to_fx2_o.wr_n   <= '1';
    to_fx2_o.rd_n   <= '1';
    to_fx2_o.oe_n   <= '1';
    to_fx2_o.pktend <= '1';
    
    tx_o <= nsl_amba.axi4_stream.accept(axi_cfg_c, false);
    rx_o <= nsl_amba.axi4_stream.transfer_defaults(axi_cfg_c);
    
    case r.state is      
      when ST_IDLE => -- ready to write, priority to write
        tx_o <= nsl_amba.axi4_stream.accept(axi_cfg_c, tx_full_n_s = '1');

      when ST_RESET | ST_WAIT_ADDR | ST_W_STATE1 | ST_R_STATE1 =>
      
      when ST_W_STATE2 =>
        to_fx2_o.pktend <= nsl_logic.bool.to_logic(not r.last);
        to_fx2_o.data   <= r.data;
        to_fx2_o.wr_n   <= '0'; -- advance FIFO pointer
        
        tx_o <= nsl_amba.axi4_stream.accept(axi_cfg_c, tx_full_n_s = '1');

      when ST_R_STATE2 => -- read is performed
        to_fx2_o.rd_n <= '0'; -- increment FIFO pointer
        to_fx2_o.oe_n <= '0';
      
      when ST_R_STATE3 => -- read data outputted with correct tlast flag based
                          -- on the empty flag
        rx_o <= nsl_amba.axi4_stream.transfer(cfg => axi_cfg_c,
                                              bytes => nsl_data.bytestream.from_suv(r.data),
                                              last => false);

        to_fx2_o.oe_n <= '0';
      
    end case;
  end process;
end architecture;
