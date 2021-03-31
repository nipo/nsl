library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_spi;
use nsl_spi.transactor.all;

entity spi_muxed_transactor is
  generic(
    extender_slave_no_c: integer;
    muxed_slave_no_c: integer
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    slave_cmd_i : in  nsl_bnoc.framed.framed_req;
    slave_cmd_o : out nsl_bnoc.framed.framed_ack;
    slave_rsp_o : out nsl_bnoc.framed.framed_req;
    slave_rsp_i : in  nsl_bnoc.framed.framed_ack;

    master_cmd_i : in  nsl_bnoc.framed.framed_ack;
    master_cmd_o : out nsl_bnoc.framed.framed_req;
    master_rsp_o : out nsl_bnoc.framed.framed_ack;
    master_rsp_i : in  nsl_bnoc.framed.framed_req
    );
end entity;

architecture rtl of spi_muxed_transactor is

  type cmd_state_t is (
    CMD_RESET,
    CMD_IDLE,
    CMD_ROUTE,
    CMD_PUT,
    CMD_DATA_GET,
    CMD_DATA_PUT,
    CMD_SELECT_SELECT,
    CMD_SELECT_SHIFT,
    CMD_SELECT_DATA,
    CMD_SELECT_SELECT2,
    CMD_RSP_WAIT
    );

  type rsp_state_t is (
    RSP_RESET,
    RSP_IDLE,
    RSP_GET,
    RSP_PUT,
    RSP_DATA_GET,
    RSP_DATA_PUT,
    RSP_SELECT_SELECT,
    RSP_SELECT_SHIFT,
    RSP_SELECT_SELECT2,
    RSP_SELECT_RSP
    );
  
  type regs_t is record
    cmd_state  : cmd_state_t;
    rsp_state  : rsp_state_t;
    cmd, rsp : nsl_bnoc.framed.framed_data_t;
    cmd_word_left, rsp_word_left  : integer range 0 to 2**6-1;
    last       : std_ulogic;
    rsp_last : std_ulogic;
  end record;

  signal r, rin: regs_t;
    
begin
  
  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.cmd_state <= CMD_RESET;
      r.rsp_state <= RSP_RESET;
    end if;
  end process;

  transition: process(r, slave_cmd_i, slave_rsp_i, master_cmd_i, master_rsp_i)
  begin
    rin <= r;

    case r.cmd_state is
      when CMD_RESET =>
        rin.cmd_state <= CMD_IDLE;

      when CMD_IDLE =>
        if slave_cmd_i.valid = '1' then
          rin.last <= slave_cmd_i.last;
          rin.cmd <= slave_cmd_i.data;
          rin.cmd_state <= CMD_ROUTE;
        end if;

      when CMD_ROUTE =>
        if std_match(r.cmd, SPI_CMD_SELECT) then
          rin.cmd_state <= CMD_SELECT_SELECT;
        else
          rin.cmd_state <= CMD_PUT;
        end if;

      when CMD_PUT =>
        if master_cmd_i.ready = '1' then
          if std_match(r.cmd, SPI_CMD_SHIFT_OUT) or
            std_match(r.cmd, SPI_CMD_SHIFT_IO) then
            rin.cmd_state <= CMD_DATA_GET;
            rin.cmd_word_left <= to_integer(unsigned(r.cmd(5 downto 0)));
          else
            rin.cmd_state <= CMD_RSP_WAIT;
          end if;
        end if;

      when CMD_RSP_WAIT =>
        if r.rsp_state = RSP_IDLE then
          rin.cmd_state <= CMD_IDLE;
        end if;

      when CMD_DATA_GET =>
        if slave_cmd_i.valid = '1' then
          rin.cmd_state <= CMD_DATA_PUT;
          rin.cmd <= slave_cmd_i.data;
          rin.last <= slave_cmd_i.last;
        end if;

      when CMD_DATA_PUT =>
        if master_cmd_i.ready = '1' then
          if r.cmd_word_left /= 0 then
            rin.cmd_word_left <= r.cmd_word_left - 1;
            rin.cmd_state <= CMD_DATA_GET;
          else
            rin.cmd_state <= CMD_RSP_WAIT;
          end if;
        end if;

      when CMD_SELECT_SELECT =>
        if master_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_SELECT_SHIFT;
        end if;

      when CMD_SELECT_SHIFT =>
        if master_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_SELECT_DATA;
        end if;

      when CMD_SELECT_DATA =>
        if master_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_SELECT_SELECT2;
        end if;

      when CMD_SELECT_SELECT2 =>
        if master_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_RSP_WAIT;
        end if;
    end case;

    case r.rsp_state is
      when RSP_RESET =>
        rin.rsp_state <= RSP_IDLE;

      when RSP_IDLE =>
        if r.cmd_state = CMD_ROUTE then
          if std_match(r.cmd, SPI_CMD_SELECT) then
            rin.rsp_state <= RSP_SELECT_SELECT;
          else
            rin.rsp_state <= RSP_GET;
          end if;
        end if;

      when RSP_GET =>
        if master_rsp_i.valid = '1' then
          rin.rsp <= master_rsp_i.data;
          rin.rsp_last <= master_rsp_i.last;
          rin.rsp_state <= RSP_PUT;
        end if;

      when RSP_PUT =>
        if slave_rsp_i.ready = '1' then
          if std_match(r.rsp, SPI_CMD_SHIFT_IN) or
            std_match(r.rsp, SPI_CMD_SHIFT_IO) then
            rin.rsp_state <= RSP_DATA_GET;
            rin.rsp_word_left <= to_integer(unsigned(r.rsp(5 downto 0)));
          else
            rin.rsp_state <= RSP_IDLE;
          end if;
        end if;

      when RSP_DATA_GET =>
        if master_rsp_i.valid = '1' then
          rin.rsp <= master_rsp_i.data;
          rin.rsp_last <= master_rsp_i.last;
          rin.rsp_state <= RSP_DATA_PUT;
        end if;

      when RSP_DATA_PUT =>
        if slave_rsp_i.ready = '1' then
          if r.rsp_word_left /= 0 then
            rin.rsp_word_left <= r.rsp_word_left - 1;
            rin.rsp_state <= RSP_DATA_GET;
          else
            rin.rsp_state <= RSP_IDLE;
          end if;
        end if;

      when RSP_SELECT_SELECT =>
        if master_rsp_i.valid = '1' then
          rin.rsp_state <= RSP_SELECT_SHIFT;
        end if;
        
      when RSP_SELECT_SHIFT =>
        if master_rsp_i.valid = '1' then
          rin.rsp_state <= RSP_SELECT_SELECT2;
        end if;
        
      when RSP_SELECT_SELECT2 =>
        if master_rsp_i.valid = '1' then
          rin.rsp_state <= RSP_SELECT_RSP;
        end if;

      when RSP_SELECT_RSP =>
        if slave_rsp_i.ready = '1' then
          rin.rsp_state <= RSP_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    master_rsp_o.ready <= '0';
    slave_cmd_o.ready <= '0';
    master_cmd_o.valid <= '0';
    master_cmd_o.last <= '-';
    master_cmd_o.data <= (others => '-');
    slave_rsp_o.valid <= '0';
    slave_rsp_o.last <= '-';
    slave_rsp_o.data <= (others => '-');
    
    case r.cmd_state is
      when CMD_RESET | CMD_ROUTE | CMD_RSP_WAIT =>
        null;

      when CMD_IDLE | CMD_DATA_GET =>
        slave_cmd_o.ready <= '1';

      when CMD_PUT | CMD_DATA_PUT =>
        master_cmd_o.valid <= '1';
        master_cmd_o.last <= r.last;
        master_cmd_o.data <= r.cmd;

      when CMD_SELECT_SELECT =>
        master_cmd_o.valid <= '1';
        master_cmd_o.last <= '0';
        master_cmd_o.data <= SPI_CMD_SELECT(7 downto 5) & "00"
                             & std_ulogic_vector(to_unsigned(extender_slave_no_c, 3));

      when CMD_SELECT_SHIFT =>
        master_cmd_o.valid <= '1';
        master_cmd_o.last <= '0';
        master_cmd_o.data <= SPI_CMD_SHIFT_OUT(7 downto 6) & "000000";

      when CMD_SELECT_DATA =>
        master_cmd_o.valid <= '1';
        master_cmd_o.last <= '0';
        master_cmd_o.data <= (others => '1');
        master_cmd_o.data(to_integer(unsigned(r.cmd(2 downto 0)))) <= '0';

      when CMD_SELECT_SELECT2 =>
        master_cmd_o.valid <= '1';
        master_cmd_o.last <= '0';
        master_cmd_o.data <= SPI_CMD_SELECT(7 downto 5) & "00"
                             & std_ulogic_vector(to_unsigned(muxed_slave_no_c, 3));
    end case;

    case r.rsp_state is
      when RSP_RESET | RSP_IDLE =>
        null;

      when RSP_GET | RSP_DATA_GET | RSP_SELECT_SELECT
        | RSP_SELECT_SHIFT | RSP_SELECT_SELECT2 =>
        master_rsp_o.ready <= '1';

      when RSP_PUT | RSP_DATA_PUT =>
        slave_rsp_o.valid <= '1';
        slave_rsp_o.data <= r.rsp;
        slave_rsp_o.last <= r.rsp_last;
        
      when RSP_SELECT_RSP =>
        slave_rsp_o.valid <= '1';
        slave_rsp_o.data <= r.cmd;
        slave_rsp_o.last <= r.last;
    end case;
  end process;
  
end architecture;
