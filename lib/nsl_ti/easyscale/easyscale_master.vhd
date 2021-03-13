library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_io;

entity easyscale_master is
  generic(
    clock_rate_c : natural range 1000000 to 100000000
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    easyscale_o: out nsl_io.io.tristated;
    easyscale_i: in std_ulogic;
    
    dev_addr_i : in std_ulogic_vector(7 downto 0);
    ack_req_i  : in std_ulogic;
    reg_addr_i : in std_ulogic_vector(1 downto 0);
    data_i     : in std_ulogic_vector(4 downto 0);
    start_i    : in std_ulogic;

    busy_o     : out std_ulogic;
    dev_ack_o  : out std_ulogic
    );
end entity;

architecture rtl of easyscale_master is

  constant cycles_per_2us : natural := (clock_rate_c / 500000);

  type state_t is (
    STATE_IDLE,
    STATE_START,
    STATE_LOW,
    STATE_BIT,
    STATE_HIGH,
    STATE_EOS,
    STATE_DEV_ACK
    );

  type regs_t is record
    wait_ctr: natural range 0 to cycles_per_2us - 1;
    bit_ctr: natural range 0 to 511;
    state: state_t;
    cmd : std_ulogic_vector(15 downto 0);
    ack_req : std_ulogic;
    dev_ack : std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process (reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= STATE_IDLE;
      r.dev_ack <= '0';
    end if;
  end process;

  transition: process(r, start_i, data_i, reg_addr_i, dev_addr_i, ack_req_i, easyscale_i)
  begin
    rin <= r;

    if r.state = STATE_IDLE then
      if start_i = '1' then
        rin.state <= STATE_START;
        rin.cmd <= dev_addr_i & ack_req_i & reg_addr_i & data_i;
        rin.ack_req <= ack_req_i;
        rin.wait_ctr <= cycles_per_2us - 1;
        rin.bit_ctr <= 15;
      end if;
    else
      if r.wait_ctr /= 0 then
        rin.wait_ctr <= r.wait_ctr - 1;
      else
        rin.wait_ctr <= cycles_per_2us - 1;

        case r.state is
          when STATE_START =>
            rin.state <= STATE_LOW;
          when STATE_LOW =>
            rin.state <= STATE_BIT;
          when STATE_BIT =>
            rin.state <= STATE_HIGH;
          when STATE_HIGH =>
            if r.bit_ctr = 8 or r.bit_ctr = 0 then
              rin.state <= STATE_EOS;
            else
              rin.state <= STATE_LOW;
            end if;
            rin.bit_ctr <= (r.bit_ctr - 1) mod 512;
          when STATE_EOS =>
            if r.bit_ctr /= 7 then
              if r.ack_req = '1' then
                rin.state <= STATE_DEV_ACK;
                rin.bit_ctr <= 511;
              else
                rin.state <= STATE_IDLE;
                rin.dev_ack <= '1';
              end if;
            else
              rin.state <= STATE_START;
            end if;
          when STATE_DEV_ACK =>
            if r.bit_ctr = 0 then
              rin.state <= STATE_IDLE;
            else
              if r.bit_ctr = 256 then
                rin.dev_ack <= not easyscale_i;
              end if;
              rin.bit_ctr <= (r.bit_ctr - 1) mod 512;
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
        easyscale_o.v <= '1';
        easyscale_o.en <= '1';
      when STATE_START | STATE_HIGH =>
        easyscale_o.v <= '1';
        easyscale_o.en <= '1';
      when STATE_EOS | STATE_LOW =>
        easyscale_o.v <= '0';
        easyscale_o.en <= '1';
      when STATE_DEV_ACK =>
        easyscale_o.v <= '-';
        easyscale_o.en <= '0';
      when STATE_BIT =>
        easyscale_o.v <= r.cmd(r.bit_ctr mod 16);
        easyscale_o.en <= '1';
    end case;
  end process;

  rsp_moore: process(r)
  begin
    case r.state is
      when STATE_IDLE =>
        busy_o <= '0';
      when others =>
        busy_o <= '1';
    end case;
  end process;

  dev_ack_o <= r.dev_ack;

end architecture;
