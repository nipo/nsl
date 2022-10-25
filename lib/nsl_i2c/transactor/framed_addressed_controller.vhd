library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_i2c, nsl_data, nsl_math;
use nsl_i2c.transactor.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;

entity framed_addressed_controller is
  generic(
    addr_byte_count_c : natural;
    big_endian_c : boolean;
    txn_byte_count_max_c : positive
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    cmd_i  : in nsl_bnoc.framed.framed_ack;
    cmd_o  : out nsl_bnoc.framed.framed_req;
    rsp_o  : out nsl_bnoc.framed.framed_ack;
    rsp_i  : in nsl_bnoc.framed.framed_req;

    valid_i : in std_ulogic;
    ready_o : out std_ulogic;
    saddr_i : in unsigned(7 downto 1);
    addr_i : in unsigned(8 * addr_byte_count_c - 1 downto 0) := (others => '0');
    write_i : in std_ulogic;
    wdata_i : in nsl_data.bytestream.byte_string(0 to txn_byte_count_max_c-1);
    data_byte_count_i : natural range 1 to txn_byte_count_max_c;

    valid_o : out std_ulogic;
    ready_i : in std_ulogic;
    rdata_o : out nsl_data.bytestream.byte_string(0 to txn_byte_count_max_c-1);
    error_o : out std_ulogic
    );
begin

  assert
    addr_byte_count_c + txn_byte_count_max_c + 1 <= 2**6
    report "Maximum size for concatinated slave address, byte address and data must not exceed 64 bytes"
    severity failure;

end entity;

architecture rtl of framed_addressed_controller is
  
  type cmd_t is (
    CMD_RESET,

    CMD_IDLE,
    CMD_START,
    CMD_WRITE_CMD,
    CMD_SADDR_PUT,
    CMD_ADDR_PUT,
    CMD_DATA_PUT,
    CMD_RESTART,
    CMD_WRITE_CMD2,
    CMD_SADDR_PUT2,
    CMD_READ_CMD,
    CMD_STOP,
    CMD_RSP_WAIT,
    CMD_DONE
    );

  type rsp_t is (
    RSP_RESET,
    RSP_IDLE,
    RSP_START,
    RSP_SADDR_ACK,
    RSP_ADDR_ACK,
    RSP_DATA_ACK,
    RSP_RESTART,
    RSP_SADDR_ACK2,
    RSP_DATA_GET,
    RSP_STOP
    );
  
  type regs_t is record
    cmd             : cmd_t;
    rsp             : rsp_t;
    saddr           : unsigned(7 downto 1);
    addr            : nsl_data.bytestream.byte_string(0 to addr_byte_count_c-1);
    cmd_byte_count  : natural range 0 to nsl_math.arith.max(addr_byte_count_c, txn_byte_count_max_c)-1;
    write           : boolean;
    data            : nsl_data.bytestream.byte_string(0 to txn_byte_count_max_c-1);
    rsp_byte_count  : natural range 0 to nsl_math.arith.max(addr_byte_count_c, txn_byte_count_max_c)-1;
    data_byte_count : natural range 1 to txn_byte_count_max_c;
    error           : boolean;
  end record;

  signal r, rin : regs_t;

begin

  regs: process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.cmd <= CMD_RESET;
      r.rsp <= RSP_RESET;
    end if;
  end process;

  transition: process(r, cmd_i, rsp_i,
                      valid_i, ready_i, saddr_i,
                      addr_i, write_i, wdata_i,
                      data_byte_count_i)
  begin
    rin <= r;

    case r.cmd is
      when CMD_RESET =>
        rin.cmd <= CMD_IDLE;

      when CMD_IDLE =>
        if valid_i = '1' then
          rin.cmd <= CMD_START;
          if big_endian_c then
            rin.addr <= to_be(addr_i);
          else
            rin.addr <= to_le(addr_i);
          end if;
          rin.write <= write_i = '1';
          rin.saddr <= saddr_i;
          rin.data <= wdata_i;
          rin.data_byte_count <= data_byte_count_i;
        end if;

      when CMD_START =>
        if cmd_i.ready = '1' then
          if addr_byte_count_c /= 0 or r.write then
            rin.cmd <= CMD_WRITE_CMD;
          else
            rin.cmd <= CMD_READ_CMD;
          end if;
        end if;

      when CMD_WRITE_CMD =>
        if cmd_i.ready = '1' then
          rin.cmd <= CMD_SADDR_PUT;
          if addr_byte_count_c /= 0 then
            rin.cmd_byte_count <= addr_byte_count_c - 1;
          end if;
        end if;

      when CMD_SADDR_PUT =>
        if cmd_i.ready = '1' then
          if addr_byte_count_c /= 0 then
            rin.cmd_byte_count <= addr_byte_count_c - 1;
            rin.cmd <= CMD_ADDR_PUT;
          else
            rin.cmd <= CMD_DATA_PUT;
          end if;
        end if;

      when CMD_ADDR_PUT =>
        if cmd_i.ready = '1' then
          if r.cmd_byte_count /= 0 then
            rin.addr <= shift_left(r.addr);
            rin.cmd_byte_count <= r.cmd_byte_count - 1;
          elsif r.write then
            rin.cmd <= CMD_DATA_PUT;
            rin.cmd_byte_count <= r.data_byte_count - 1;
          else
            rin.cmd <= CMD_RESTART;
          end if;
        end if;

      when CMD_DATA_PUT =>
        if cmd_i.ready = '1' then
          rin.data <= shift_left(r.data);
          if r.cmd_byte_count /= 0 then
            rin.cmd_byte_count <= r.cmd_byte_count - 1;
          else
            rin.cmd <= CMD_STOP;
          end if;
        end if;

      when CMD_RESTART =>
        if cmd_i.ready = '1' then
          rin.cmd <= CMD_WRITE_CMD2;
        end if;

      when CMD_WRITE_CMD2 =>
        if cmd_i.ready = '1' then
          rin.cmd <= CMD_SADDR_PUT2;
        end if;

      when CMD_SADDR_PUT2 =>
        if cmd_i.ready = '1' then
          rin.cmd <= CMD_READ_CMD;
        end if;

      when CMD_READ_CMD =>
        if cmd_i.ready = '1' then
          rin.cmd <= CMD_STOP;
        end if;

      when CMD_STOP =>
        if cmd_i.ready = '1' then
          rin.cmd <= CMD_RSP_WAIT;
        end if;

      when CMD_RSP_WAIT =>
        if r.rsp = RSP_IDLE then
          rin.cmd <= CMD_DONE;
        end if;

      when CMD_DONE =>
        if ready_i = '1' then
          rin.cmd <= CMD_IDLE;
        end if;
    end case;

    case r.rsp is
      when RSP_RESET =>
        rin.rsp <= RSP_IDLE;

      when RSP_IDLE =>
        if r.cmd = CMD_START then
          rin.rsp <= RSP_START;
          rin.error <= false;
        end if;

      when RSP_START =>
        if rsp_i.valid = '1' then
          if addr_byte_count_c /= 0 or r.write then
            rin.rsp <= RSP_SADDR_ACK;
          else
            rin.rsp <= RSP_SADDR_ACK2;
          end if;
          if rsp_i.last = '1' then
            rin.error <= true;
            rin.rsp <= RSP_IDLE;
          end if;
        end if;

      when RSP_SADDR_ACK =>
        if rsp_i.valid = '1' then
          rin.error <= r.error or (rsp_i.data(0) /= '1');
          if addr_byte_count_c /= 0 then
            rin.rsp_byte_count <= addr_byte_count_c - 1;
            rin.rsp <= RSP_ADDR_ACK;
          else
            rin.rsp <= RSP_DATA_ACK;
            rin.rsp_byte_count <= r.data_byte_count - 1;
          end if;
          if rsp_i.last = '1' then
            rin.error <= true;
            rin.rsp <= RSP_IDLE;
          end if;
        end if;

      when RSP_ADDR_ACK =>
        if rsp_i.valid = '1' then
          rin.error <= r.error or (rsp_i.data(0) /= '1');
          if r.rsp_byte_count /= 0 then
            rin.rsp_byte_count <= r.rsp_byte_count - 1;
          elsif r.write then
            rin.rsp <= RSP_DATA_ACK;
            rin.rsp_byte_count <= r.data_byte_count - 1;
          else
            rin.rsp <= RSP_RESTART;
          end if;
          if rsp_i.last = '1' then
            rin.error <= true;
            rin.rsp <= RSP_IDLE;
          end if;
        end if;

      when RSP_DATA_ACK =>
        if rsp_i.valid = '1' then
          rin.error <= r.error or (rsp_i.data(0) /= '1');
          if r.rsp_byte_count /= 0 then
            rin.rsp_byte_count <= r.rsp_byte_count - 1;
          else
            rin.rsp <= RSP_STOP;
          end if;
          if rsp_i.last = '1' then
            rin.error <= true;
            rin.rsp <= RSP_IDLE;
          end if;
        end if;

      when RSP_RESTART =>
        if rsp_i.valid = '1' then
          rin.rsp <= RSP_SADDR_ACK2;
          if rsp_i.last = '1' then
            rin.error <= true;
            rin.rsp <= RSP_IDLE;
          end if;
        end if;

      when RSP_SADDR_ACK2 =>
        if rsp_i.valid = '1' then
          rin.error <= r.error or (rsp_i.data(0) /= '1');
          rin.rsp_byte_count <= r.data_byte_count - 1;
          rin.rsp <= RSP_DATA_GET;
          if rsp_i.last = '1' then
            rin.error <= true;
            rin.rsp <= RSP_IDLE;
          end if;
        end if;

      when RSP_DATA_GET =>
        if rsp_i.valid = '1' then
          rin.data(0 to r.data'right-1) <= r.data(1 to r.data'right);
          rin.data(r.data'right) <= rsp_i.data;
          if r.rsp_byte_count /= 0 then
            rin.rsp_byte_count <= r.rsp_byte_count - 1;
          else
            rin.rsp <= RSP_STOP;
          end if;
          if rsp_i.last = '1' then
            rin.error <= true;
            rin.rsp <= RSP_IDLE;
          end if;
        end if;
        
      when RSP_STOP =>
        if rsp_i.valid = '1' then
          if rsp_i.last = '1' then
            rin.rsp <= RSP_IDLE;
          else
            rin.error <= true;
          end if;
        end if;
    end case;
  end process;

  moore : process (r)
  begin
    cmd_o.valid <= '0';
    cmd_o.last <= '-';
    cmd_o.data <= (others => '-');
    rsp_o.ready <= '0';
    ready_o <= '0';
    valid_o <= '0';
    error_o <= '-';
    rdata_o <= (others => (others => '-'));
    
    case r.cmd is
      when CMD_RESET | CMD_RSP_WAIT =>
        null;

      when CMD_IDLE =>
        ready_o <= '1';

      when CMD_START | CMD_RESTART =>
        cmd_o.valid <= '1';
        cmd_o.last <= '0';
        cmd_o.data <= I2C_CMD_START;

      when CMD_WRITE_CMD =>
        cmd_o.valid <= '1';
        cmd_o.last <= '0';
        if r.write then
          cmd_o.data <= I2C_CMD_WRITE(7 downto 6) & std_ulogic_vector(to_unsigned(1 + addr_byte_count_c + r.data_byte_count - 1, 6));
        else
          cmd_o.data <= I2C_CMD_WRITE(7 downto 6) & std_ulogic_vector(to_unsigned(1 + addr_byte_count_c - 1, 6));
        end if;

      when CMD_SADDR_PUT =>
        cmd_o.valid <= '1';
        cmd_o.last <= '0';
        cmd_o.data <= std_ulogic_vector(r.saddr) & "0";

      when CMD_SADDR_PUT2 =>
        cmd_o.valid <= '1';
        cmd_o.last <= '0';
        cmd_o.data <= std_ulogic_vector(r.saddr) & "1";
        
      when CMD_ADDR_PUT =>
        cmd_o.valid <= '1';
        cmd_o.last <= '0';
        cmd_o.data <= first_left(r.addr);

      when CMD_DATA_PUT =>
        cmd_o.valid <= '1';
        cmd_o.last <= '0';
        cmd_o.data <= first_left(r.data);

      when CMD_WRITE_CMD2 =>
        cmd_o.valid <= '1';
        cmd_o.last <= '0';
        cmd_o.data <= I2C_CMD_WRITE(7 downto 6) & std_ulogic_vector(to_unsigned(0, 6));

      when CMD_READ_CMD =>
        cmd_o.valid <= '1';
        cmd_o.last <= '0';
        cmd_o.data <= I2C_CMD_READ_NACK(7 downto 6) & std_ulogic_vector(to_unsigned(r.data_byte_count-1, 6));

      when CMD_STOP =>
        cmd_o.valid <= '1';
        cmd_o.last <= '1';
        cmd_o.data <= I2C_CMD_STOP;

      when CMD_DONE =>
        valid_o <= '1';
        if r.error then
          error_o <= '1';
        else
          error_o <= '0';
        end if;
        rdata_o <= r.data;
    end case;

    case r.rsp is
      when RSP_RESET | RSP_IDLE =>
        null;

      when RSP_START | RSP_SADDR_ACK | RSP_ADDR_ACK
        | RSP_DATA_ACK | RSP_RESTART
        | RSP_SADDR_ACK2 | RSP_DATA_GET
        | RSP_STOP =>
        rsp_o.ready <= '1';
    end case;

  end process;

end architecture;
