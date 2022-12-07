library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;

entity pca8574_driver is
  generic(
    i2c_addr_c    : unsigned(6 downto 0) := "0100000";
    in_supported_c : boolean := true
    );
  port(
    reset_n_i   : in std_ulogic;
    clock_i     : in std_ulogic;

    force_i : in  std_ulogic := '0';
    busy_o  : out std_ulogic;
    irq_n_i : in  std_ulogic := '1';

    pin_i : in  std_ulogic_vector(0 to 7);
    pin_o : out std_ulogic_vector(0 to 7);

    cmd_o  : out nsl_bnoc.framed.framed_req;
    cmd_i  : in  nsl_bnoc.framed.framed_ack;
    rsp_i  : in  nsl_bnoc.framed.framed_req;
    rsp_o  : out nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of pca8574_driver is

  type cmd_state_t is (
    CMD_RESET,
    CMD_IDLE,

    -- Common
    CMD_PUT_START_W,
    CMD_PUT_WRITE_W, -- 2 bytes
    CMD_PUT_SADDR_W,
    CMD_PUT_OUT,
    -- Goto stop

    -- If read
    CMD_PUT_START_R,
    CMD_PUT_WRITE_R, -- 1 byte
    CMD_PUT_SADDR_R,
    CMD_PUT_READ, -- 1 byte

    -- Common
    CMD_PUT_STOP,
    CMD_WAIT_DONE
    );

  type rsp_state_t is (
    RSP_RESET,
    RSP_IDLE,
    -- If write, goto wait_done. This simplifies FSM if read is not needed

    -- Only if read
    RSP_GET_START,
    RSP_GET_SADDR_R,
    RSP_GET_RSP,

    RSP_WAIT_DONE
    );

  type regs_t is
  record
    cmd_state: cmd_state_t;
    rsp_state: rsp_state_t;
    io_out, io_in : std_ulogic_vector(7 downto 0);
    out_dirty, in_dirty: boolean;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.cmd_state <= CMD_RESET;
      r.rsp_state <= RSP_RESET;
      r.io_in <= (others => '0');
      r.io_out <= (others => '0');
      r.out_dirty <= true;
      r.in_dirty <= in_supported_c;
    end if;
  end process;

  transition: process(r, irq_n_i, cmd_i, rsp_i, pin_i, force_i) is
    variable pin_i_swapped: std_ulogic_vector(7 downto 0);
  begin
    rin <= r;

    pin_i_swapped := nsl_data.endian.bitswap(pin_i);
    
    if in_supported_c and (irq_n_i = '0' or force_i = '1') then
      rin.in_dirty <= true;
    end if;

    if pin_i_swapped /= r.io_out or force_i = '1' then
      rin.out_dirty <= true;
      rin.io_out <= pin_i_swapped;
    end if;
    
    case r.cmd_state is
      when CMD_RESET =>
        rin.cmd_state <= CMD_IDLE;

      when CMD_IDLE =>
        if r.out_dirty then
          rin.cmd_state <= CMD_PUT_START_W;
        elsif in_supported_c and r.in_dirty then
          rin.cmd_state <= CMD_PUT_START_R;
        end if;

      when CMD_PUT_START_W =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_WRITE_W;
        end if;

      when CMD_PUT_WRITE_W =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_SADDR_W;
        end if;

      when CMD_PUT_SADDR_W =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_OUT;
        end if;

      when CMD_PUT_OUT =>
        if cmd_i.ready = '1' then
          rin.out_dirty <= false;
          rin.cmd_state <= CMD_PUT_STOP;
        end if;

      when CMD_PUT_START_R =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_WRITE_R;
        end if;

      when CMD_PUT_WRITE_R =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_SADDR_R;
        end if;

      when CMD_PUT_SADDR_R =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_READ;
        end if;

      when CMD_PUT_READ =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_STOP;
        end if;

      when CMD_PUT_STOP =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_WAIT_DONE;
        end if;

      when CMD_WAIT_DONE =>
        if r.rsp_state = RSP_IDLE then
          rin.cmd_state <= CMD_IDLE;
        end if;
    end case;

    case r.rsp_state is
      when RSP_RESET =>
        rin.rsp_state <= RSP_IDLE;

      when RSP_IDLE =>
        if r.cmd_state = CMD_PUT_START_R then
          rin.rsp_state <= RSP_GET_START;
        elsif r.cmd_state = CMD_PUT_START_W then
          rin.rsp_state <= RSP_WAIT_DONE;
        end if;

      when RSP_GET_START =>
        if rsp_i.valid = '1' then
          rin.rsp_state <= RSP_GET_SADDR_R;
        end if;

      when RSP_GET_SADDR_R =>
        if rsp_i.valid = '1' then
          rin.rsp_state <= RSP_GET_RSP;
          if rsp_i.data(0) /= '1' then
            rin.rsp_state <= RSP_WAIT_DONE;
          end if;
        end if;

      when RSP_GET_RSP =>
        if rsp_i.valid = '1' then
          rin.io_in <= rsp_i.data;
          rin.rsp_state <= RSP_WAIT_DONE;
          rin.in_dirty <= false;
        end if;

      when RSP_WAIT_DONE =>
        if rsp_i.valid = '1' and rsp_i.last = '1' then
          rin.rsp_state <= RSP_IDLE;
        end if;
    end case;

  end process;

  moore: process(r) is
  begin
    pin_o <= nsl_data.endian.bitswap(r.io_in);

    case r.cmd_state is
      when CMD_RESET | CMD_IDLE | CMD_WAIT_DONE =>
        cmd_o <= (valid => '0', last => '-', data => (others => '0'));

      when CMD_PUT_START_W | CMD_PUT_START_R =>
        cmd_o <= (valid => '1', last => '0', data => x"20");

      when CMD_PUT_WRITE_W =>
        -- Write SADDR, OUT
        cmd_o <= (valid => '1', last => '0', data => x"41");

      when CMD_PUT_SADDR_W =>
        cmd_o <= (valid => '1', last => '0', data => std_ulogic_vector(i2c_addr_c) & "0");

      when CMD_PUT_OUT =>
        cmd_o <= (valid => '1', last => '0', data => r.io_out);

      when CMD_PUT_WRITE_R =>
        cmd_o <= (valid => '1', last => '0', data => x"40");

      when CMD_PUT_SADDR_R =>
        cmd_o <= (valid => '1', last => '0', data => std_ulogic_vector(i2c_addr_c) & "1");

      when CMD_PUT_READ =>
        -- End with a NACK
        cmd_o <= (valid => '1', last => '0', data => x"80");

      when CMD_PUT_STOP =>
        cmd_o <= (valid => '1', last => '1', data => x"21");
    end case;

    case r.rsp_state is
      when RSP_RESET | RSP_IDLE =>
        rsp_o.ready <= '0';
        if r.out_dirty or r.in_dirty then
          busy_o <= '1';
        else
          busy_o <= '0';
        end if;

      when others =>
        rsp_o.ready <= '1';
        busy_o <= '1';
    end case;
  end process;

end architecture;
