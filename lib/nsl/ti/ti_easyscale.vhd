library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl;
use nsl.ti.all;

entity ti_easyscale is
  generic(
    p_clk_hz   : natural range 1000000 to 100000000
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_easyscale: inout std_logic;
    
    p_dev_addr : in std_ulogic_vector(7 downto 0);
    p_ack_req  : in std_ulogic;
    p_reg_addr : in std_ulogic_vector(1 downto 0);
    p_data     : in std_ulogic_vector(4 downto 0);
    p_start    : in std_ulogic;

    p_busy     : out std_ulogic;
    p_dev_ack  : out std_ulogic
    );
end entity;

architecture rtl of ti_easyscale is

  constant cycles_per_2us : natural := (p_clk_hz / 500000);

  type state_t is (
    STATE_IDLE,
    STATE_DADR_START,
    STATE_DADR_LOW,
    STATE_DADR_BIT,
    STATE_DADR_HIGH,
    STATE_DADR_EOS,
    STATE_DATA_START,
    STATE_DATA_LOW,
    STATE_DATA_BIT,
    STATE_DATA_HIGH,
    STATE_DATA_EOS,
    STATE_DEV_ACK
    );

  type regs_t is record
    wait_ctr: natural range 0 to cycles_per_2us - 1;
    bit_ctr: natural range 0 to 511;
    state: state_t;
    addr : std_ulogic_vector(7 downto 0);
    data : std_ulogic_vector(7 downto 0);
    ack_req : std_ulogic;
    dev_ack : std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= STATE_IDLE;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_start, p_data, p_reg_addr, p_dev_addr, p_ack_req, p_easyscale)
  begin
    rin <= r;

    if r.state = STATE_IDLE then
      if p_start = '1' then
        rin.state <= STATE_DADR_START;
        rin.addr <= p_dev_addr;
        rin.ack_req <= p_ack_req;
        rin.data <= p_ack_req & p_reg_addr & p_data;
        rin.wait_ctr <= cycles_per_2us - 1;
      end if;
    else
      if r.wait_ctr /= 0 then
        rin.wait_ctr <= r.wait_ctr - 1;
      else
        rin.wait_ctr <= cycles_per_2us - 1;

        case r.state is
          when STATE_DADR_START =>
            rin.bit_ctr <= 7;
            rin.state <= STATE_DADR_LOW;
          when STATE_DADR_LOW =>
            rin.state <= STATE_DADR_BIT;
          when STATE_DADR_BIT =>
            rin.state <= STATE_DADR_HIGH;
          when STATE_DADR_HIGH =>
            if r.bit_ctr = 0 then
              rin.state <= STATE_DADR_EOS;
            else
              rin.bit_ctr <= r.bit_ctr - 1;
              rin.state <= STATE_DADR_LOW;
            end if;
          when STATE_DADR_EOS =>
            rin.state <= STATE_DATA_START;
          when STATE_DATA_START =>
            rin.bit_ctr <= 7;
            rin.state <= STATE_DATA_LOW;
          when STATE_DATA_LOW =>
            rin.state <= STATE_DATA_BIT;
          when STATE_DATA_BIT =>
            rin.state <= STATE_DATA_HIGH;
          when STATE_DATA_HIGH =>
            if r.bit_ctr = 0 then
              rin.state <= STATE_DATA_EOS;
            else
              rin.bit_ctr <= r.bit_ctr - 1;
              rin.state <= STATE_DATA_LOW;
            end if;
          when STATE_DATA_EOS =>
            if r.ack_req = '1' then
              rin.state <= STATE_DEV_ACK;
              rin.bit_ctr <= 511;
            else
              rin.state <= STATE_IDLE;
            end if;
          when STATE_DEV_ACK =>
            if r.bit_ctr = 0 then
              rin.state <= STATE_IDLE;
            else
              if r.bit_ctr = 256 then
                rin.dev_ack <= not p_easyscale;
              end if;
              rin.bit_ctr <= r.bit_ctr - 1;
            end if;
          when others =>
            null;
        end case;
      end if;
    end if;
  end process;

  easyscale_moore: process(r)
  begin
    case r.state is
      when STATE_IDLE =>
        p_easyscale <= '1';
      when STATE_DADR_START | STATE_DADR_HIGH
        | STATE_DATA_START | STATE_DATA_HIGH =>
        p_easyscale <= '1';
      when STATE_DADR_EOS | STATE_DADR_LOW
        | STATE_DATA_EOS | STATE_DATA_LOW =>
        p_easyscale <= '0';
      when STATE_DEV_ACK =>
        p_easyscale <= 'H';
      when STATE_DADR_BIT =>
        p_easyscale <= r.addr(r.bit_ctr);
      when STATE_DATA_BIT =>
        p_easyscale <= r.data(r.bit_ctr);
    end case;
  end process;

  rsp_moore: process(r)
  begin
    case r.state is
      when STATE_IDLE =>
        p_busy <= '0';
        p_dev_ack <= r.dev_ack;
      when others =>
        p_busy <= '1';
        p_dev_ack <= 'X';
    end case;
  end process;

end architecture;
