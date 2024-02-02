library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_bnoc, nsl_data, nsl_logic;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;
use nsl_bnoc.framed.all;
use work.memap_mapper.all;
use work.transactor.all;

entity framed_memap_transactor is
  port (
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;
    
    cmd_i : in nsl_bnoc.framed.framed_req;
    cmd_o : out nsl_bnoc.framed.framed_ack;
    rsp_o : out nsl_bnoc.framed.framed_req;
    rsp_i : in nsl_bnoc.framed.framed_ack;

    dp_cmd_o : out nsl_bnoc.framed.framed_req;
    dp_cmd_i : in nsl_bnoc.framed.framed_ack;
    dp_rsp_i : in nsl_bnoc.framed.framed_req;
    dp_rsp_o : out nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of framed_memap_transactor is

  type cmd_state_t is (
    CMD_RESET,
    CMD_IDLE,
    CMD_ROUTE,
    CMD_RW_ABORT,
    CMD_RW_CSW_CMD,
    CMD_RW_CSW_VAR,
    CMD_RW_CSW_CST,
    CMD_R_DRW_CMD,
    CMD_R_DRW_RUN,
    CMD_R_RDBUFF,
    CMD_R_RDBUFF_RUN,
    CMD_W_DRW_CMD,
    CMD_W_DRW_GET,
    CMD_W_DRW_SET,
    CMD_W_RUN,
    CMD_TAR_CMD, -- Copy of data are done by RAW_GET/RAW_SET pairs
    CMD_RAW_GET,
    CMD_RAW_SET,
    CMD_RAW_PT_GET,
    CMD_RAW_PT_SET,
    CMD_CSW_BASE_DATA,
    CMD_WAIT_RSP
    );

  type rsp_state_t is (
    RSP_RESET,
    RSP_IDLE,
    RSP_RW_ABORT,
    RSP_RW_CSW_STATUS,
    RSP_R_INIT_STATUS,
    RSP_R_INIT_DATA,
    RSP_R_INIT_RUN,
    RSP_R_DATA_STATUS,
    RSP_R_DATA_DATA_GET,
    RSP_R_DATA_DATA_SET,
    RSP_R_DATA_RUN,
    RSP_W_STATUS,
    RSP_W_RUN,
    RSP_RW_WRAPUP,
    RSP_TAR_STATUS,
    RSP_RAW_GET,
    RSP_RAW_SET,
    RSP_RAW_PT_GET,
    RSP_RAW_PT_SET,
    RSP_NOP
    );
  
  type regs_t is
  record
    cmd_state: cmd_state_t;
    cmd_data: byte;
    cmd_data_left: natural range 0 to 3;
    cmd_is_write: boolean;
    cmd_left: natural range 0 to 63;
    cmd_last: boolean;

    interval: unsigned(5 downto 0);
    csw_base: byte_string(1 to 3);
    csw_size: std_ulogic_vector(2 downto 0);

    rsp_state: rsp_state_t;
    rsp_is_write: boolean;
    rsp_data: byte;
    rsp_data_left: natural range 0 to 3;
    rsp_left: natural range 0 to 63;
    rsp_last: boolean;

    rsp_error: boolean;
    rsp_error_index: natural range 0 to 64;
  end record;

  signal r, rin : regs_t;

  constant memap_csw_c : std_ulogic_vector := x"0";
  constant memap_drw_c : std_ulogic_vector := x"3";
  constant memap_tar_c : std_ulogic_vector := x"1";
  constant dp_rdbuff_c : std_ulogic_vector := x"3";
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.cmd_state <= CMD_RESET;
      r.rsp_state <= RSP_RESET;
    end if;
  end process;

  transition: process(r, cmd_i, dp_cmd_i, rsp_i, dp_rsp_i) is
  begin
    rin <= r;

    case r.cmd_state is
      when CMD_RESET =>
        rin.cmd_last <= false;
        rin.interval <= to_unsigned(10, rin.interval'length);
        rin.csw_base <= from_hex("000000");
        rin.cmd_state <= CMD_IDLE;

      when CMD_IDLE =>
        if cmd_i.valid = '1' then
          rin.cmd_last <= cmd_i.last = '1';
          rin.cmd_data <= cmd_i.data;
          rin.cmd_state <= CMD_ROUTE;
        end if;
        
      when CMD_ROUTE =>
        if r.rsp_state = RSP_IDLE then
          if std_match(r.cmd_data, MEMAP_CMD_INTERVAL) then
            rin.interval <= unsigned(r.cmd_data(5 downto 0));
            rin.cmd_state <= CMD_IDLE;
          elsif std_match(r.cmd_data, MEMAP_CMD_WRITE) then
            rin.csw_size <= "010";
            rin.cmd_left <= to_integer(unsigned(r.cmd_data(5 downto 0)));
            rin.cmd_state <= CMD_RW_ABORT;
            rin.cmd_is_write <= true;
          elsif std_match(r.cmd_data, MEMAP_CMD_READ) then
            rin.csw_size <= "010";
            rin.cmd_left <= to_integer(unsigned(r.cmd_data(5 downto 0)));
            rin.cmd_state <= CMD_RW_ABORT;
            rin.cmd_is_write <= false;
          elsif std_match(r.cmd_data, MEMAP_CMD_WRITE8) then
            rin.csw_size <= "000";
            rin.cmd_left <= 0;
            rin.cmd_state <= CMD_RW_ABORT;
            rin.cmd_is_write <= true;
          elsif std_match(r.cmd_data, MEMAP_CMD_READ8) then
            rin.csw_size <= "000";
            rin.cmd_left <= 0;
            rin.cmd_state <= CMD_RW_ABORT;
            rin.cmd_is_write <= false;
          elsif std_match(r.cmd_data, MEMAP_CMD_WRITE16) then
            rin.csw_size <= "001";
            rin.cmd_left <= 0;
            rin.cmd_state <= CMD_RW_ABORT;
            rin.cmd_is_write <= true;
          elsif std_match(r.cmd_data, MEMAP_CMD_READ16) then
            rin.csw_size <= "001";
            rin.cmd_left <= 0;
            rin.cmd_state <= CMD_RW_ABORT;
            rin.cmd_is_write <= false;
          elsif std_match(r.cmd_data, MEMAP_CMD_ADDRESS) then
            rin.cmd_state <= CMD_TAR_CMD;
          elsif std_match(r.cmd_data, MEMAP_CMD_CSW) then
            rin.cmd_state <= CMD_CSW_BASE_DATA;
            rin.cmd_data_left <= 2;
          elsif std_match(r.cmd_data, MEMAP_CMD_RAW_RSP) then
            rin.cmd_state <= CMD_IDLE;
          elsif std_match(r.cmd_data, MEMAP_CMD_NOP) then
            rin.cmd_state <= CMD_WAIT_RSP;
          else
            rin.cmd_state <= CMD_IDLE;
          end if;
        end if;

        -- This one may start even if response is not idle. We'll wait for RSP
        -- path at end of execution
        if std_match(r.cmd_data, MEMAP_CMD_RAW_CMD) then
          rin.cmd_left <= to_integer(unsigned(r.cmd_data(3 downto 0)));
          rin.cmd_state <= CMD_RAW_GET;
        elsif std_match(r.cmd_data, MEMAP_CMD_RAW_CMD_PT) then
          rin.cmd_state <= CMD_RAW_PT_GET;
        end if;
  
      when CMD_RW_ABORT =>
        if dp_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_RW_CSW_CMD;
        end if;

      when CMD_RW_CSW_CMD =>
        if dp_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_RW_CSW_VAR;
        end if;

      when CMD_RW_CSW_VAR =>
        if dp_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_RW_CSW_CST;
          rin.cmd_data_left <= 2;
        end if;

      when CMD_RW_CSW_CST =>
        if dp_cmd_i.ready = '1' then
          rin.csw_base <= rot_left(r.csw_base);
          if r.cmd_data_left /= 0 then
            rin.cmd_data_left <= r.cmd_data_left - 1;
          elsif r.cmd_is_write then
            rin.cmd_state <= CMD_W_DRW_CMD;
          else
            rin.cmd_state <= CMD_R_DRW_CMD;
          end if;
        end if;

      when CMD_R_DRW_CMD =>
        if dp_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_R_DRW_RUN;
        end if;

      when CMD_R_DRW_RUN =>
        if dp_cmd_i.ready = '1' then
          if r.cmd_left /= 0 then
            rin.cmd_state <= CMD_R_DRW_CMD;
            rin.cmd_left <= r.cmd_left - 1;
          else
            rin.cmd_state <= CMD_R_RDBUFF;
          end if;
        end if;

      when CMD_R_RDBUFF =>
        if dp_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_R_RDBUFF_RUN;
        end if;

      when CMD_R_RDBUFF_RUN =>
        if dp_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_WAIT_RSP;
        end if;

      when CMD_W_DRW_CMD =>
        if dp_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_W_DRW_GET;
          rin.cmd_data_left <= 3;
        end if;

      when CMD_W_DRW_GET =>
        if cmd_i.valid = '1' then
          rin.cmd_last <= cmd_i.last = '1';
          rin.cmd_data <= cmd_i.data;
          rin.cmd_state <= CMD_W_DRW_SET;
        end if;

      when CMD_W_DRW_SET =>
        if dp_cmd_i.ready = '1' then
          if r.cmd_data_left /= 0 then
            rin.cmd_data_left <= r.cmd_data_left - 1;
            rin.cmd_state <= CMD_W_DRW_GET;
          else
            rin.cmd_state <= CMD_W_RUN;
          end if;
        end if;

      when CMD_W_RUN =>
        if dp_cmd_i.ready = '1' then
          if r.cmd_left /= 0 then
            rin.cmd_state <= CMD_W_DRW_CMD;
            rin.cmd_left <= r.cmd_left - 1;
          else
            rin.cmd_state <= CMD_IDLE;
          end if;
        end if;

      when CMD_TAR_CMD =>
        if dp_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_RAW_GET;
          rin.cmd_left <= 3;
        end if;

      when CMD_RAW_GET =>
        if cmd_i.valid = '1' then
          rin.cmd_last <= cmd_i.last = '1';
          rin.cmd_data <= cmd_i.data;
          rin.cmd_state <= CMD_RAW_SET;
        end if;

      when CMD_RAW_SET =>
        if dp_cmd_i.ready = '1' then
          if r.cmd_left /= 0 then
            rin.cmd_left <= r.cmd_left - 1;
            rin.cmd_state <= CMD_RAW_GET;
          else
            rin.cmd_state <= CMD_WAIT_RSP;
          end if;
        end if;

      when CMD_RAW_PT_GET =>
        if cmd_i.valid = '1' then
          rin.cmd_last <= cmd_i.last = '1';
          rin.cmd_data <= cmd_i.data;
          rin.cmd_state <= CMD_RAW_PT_SET;
        end if;

      when CMD_RAW_PT_SET =>
        if dp_cmd_i.ready = '1' then
          if r.cmd_last then
            rin.cmd_state <= CMD_WAIT_RSP;
          else
            rin.cmd_state <= CMD_RAW_PT_GET;
          end if;
        end if;

      when CMD_CSW_BASE_DATA =>
        if cmd_i.valid = '1' then
          rin.csw_base <= shift_left(r.csw_base, cmd_i.data);
          if r.cmd_data_left /= 0 then
            rin.cmd_data_left <= r.cmd_data_left - 1;
          else
            rin.cmd_last <= cmd_i.last = '1';
            rin.cmd_state <= CMD_IDLE;
          end if;
        end if;

      when CMD_WAIT_RSP =>
        if r.rsp_state = RSP_IDLE then
          rin.cmd_state <= CMD_IDLE;
        end if;
    end case;

    case r.rsp_state is
      when RSP_RESET =>
        rin.rsp_state <= RSP_IDLE;

      when RSP_IDLE =>
        if r.cmd_state = CMD_ROUTE then
          rin.rsp_last <= r.cmd_last;
          if std_match(r.cmd_data, MEMAP_CMD_INTERVAL) then
            null;
          elsif std_match(r.cmd_data, MEMAP_CMD_WRITE) then
            rin.rsp_left <= to_integer(unsigned(r.cmd_data(5 downto 0)));
            rin.rsp_state <= RSP_RW_ABORT;
            rin.rsp_is_write <= true;
          elsif std_match(r.cmd_data, MEMAP_CMD_READ) then
            rin.rsp_left <= to_integer(unsigned(r.cmd_data(5 downto 0)));
            rin.rsp_state <= RSP_RW_ABORT;
            rin.rsp_is_write <= false;
          elsif std_match(r.cmd_data, MEMAP_CMD_WRITE8) then
            rin.rsp_left <= 0;
            rin.rsp_state <= RSP_RW_ABORT;
            rin.rsp_is_write <= true;
          elsif std_match(r.cmd_data, MEMAP_CMD_READ8) then
            rin.rsp_left <= 0;
            rin.rsp_state <= RSP_RW_ABORT;
            rin.rsp_is_write <= false;
          elsif std_match(r.cmd_data, MEMAP_CMD_WRITE16) then
            rin.rsp_left <= 0;
            rin.rsp_state <= RSP_RW_ABORT;
            rin.rsp_is_write <= true;
          elsif std_match(r.cmd_data, MEMAP_CMD_READ16) then
            rin.rsp_left <= 0;
            rin.rsp_state <= RSP_RW_ABORT;
            rin.rsp_is_write <= false;
          elsif std_match(r.cmd_data, MEMAP_CMD_ADDRESS) then
            rin.rsp_state <= RSP_TAR_STATUS;
          elsif std_match(r.cmd_data, MEMAP_CMD_CSW) then
            null;
          elsif std_match(r.cmd_data, MEMAP_CMD_RAW_CMD) then
            null;
          elsif std_match(r.cmd_data, MEMAP_CMD_RAW_RSP) then
            rin.rsp_left <= to_integer(unsigned(r.cmd_data(3 downto 0)));
            rin.rsp_state <= RSP_RAW_GET;
          elsif std_match(r.cmd_data, MEMAP_CMD_RAW_RSP_PT) then
            rin.rsp_state <= RSP_RAW_PT_GET;
          elsif std_match(r.cmd_data, MEMAP_CMD_NOP) then
            rin.rsp_state <= RSP_NOP;
            rin.rsp_data <= r.cmd_data;
          else
            null;
          end if;
        end if;

      when RSP_RW_ABORT =>
        if dp_rsp_i.valid = '1' then
          rin.rsp_state <= RSP_RW_CSW_STATUS;
        end if;
        
      when RSP_RW_CSW_STATUS =>
        if dp_rsp_i.valid = '1' then
          rin.rsp_error <= false;
          rin.rsp_error_index <= 0;

          if r.rsp_is_write then
            rin.rsp_state <= RSP_W_STATUS;
          else
            rin.rsp_state <= RSP_R_INIT_STATUS;
          end if;
        end if;

      when RSP_R_INIT_STATUS =>
        if dp_rsp_i.valid = '1' then
          rin.rsp_data_left <= 3;
          rin.rsp_state <= RSP_R_INIT_DATA;
        end if;

      when RSP_R_INIT_DATA =>
        if dp_rsp_i.valid = '1' then
          if r.rsp_data_left /= 0 then
            rin.rsp_data_left <= r.rsp_data_left - 1;
          else
            rin.rsp_state <= RSP_R_INIT_RUN;
          end if;
        end if;
        
      when RSP_R_INIT_RUN =>
        if dp_rsp_i.valid = '1' then
          rin.rsp_state <= RSP_R_DATA_STATUS;
        end if;

      when RSP_R_DATA_STATUS =>
        if dp_rsp_i.valid = '1' then
          if not r.rsp_error then
            -- After first error happened, freeze the error registers
            if not std_match(dp_rsp_i.data, DP_RSP_ACK) or not std_match(dp_rsp_i.data, DP_RSP_PAR_OK) then
              rin.rsp_error <= true;
            else
              rin.rsp_error_index <= r.rsp_error_index + 1;
            end if;
          end if;

          rin.rsp_data_left <= 3;
          rin.rsp_state <= RSP_R_DATA_DATA_GET;
        end if;
        
      when RSP_R_DATA_DATA_GET =>
        if dp_rsp_i.valid = '1' then
          rin.rsp_data <= dp_rsp_i.data;
          rin.rsp_state <= RSP_R_DATA_DATA_SET;
        end if;

      when RSP_R_DATA_DATA_SET =>
        if rsp_i.ready = '1' then
          if r.rsp_data_left /= 0 then
            rin.rsp_data_left <= r.rsp_data_left - 1;
            rin.rsp_state <= RSP_R_DATA_DATA_GET;
          else
            rin.rsp_state <= RSP_R_DATA_RUN;
          end if;
        end if;

      when RSP_R_DATA_RUN =>
        if dp_rsp_i.valid = '1' then
          if r.rsp_left /= 0 then
            rin.rsp_left <= r.rsp_left - 1;
            rin.rsp_state <= RSP_R_DATA_STATUS;
          else
            rin.rsp_last <= r.cmd_last;
            rin.rsp_state <= RSP_RW_WRAPUP;
          end if;
        end if;
        
      when RSP_W_STATUS =>
        if dp_rsp_i.valid = '1' then
          if not r.rsp_error then
            -- After first error happened, freeze the error registers
            if not std_match(dp_rsp_i.data, DP_RSP_ACK) or not std_match(dp_rsp_i.data, DP_RSP_PAR_OK) then
              rin.rsp_error <= true;
            else
              rin.rsp_error_index <= r.rsp_error_index + 1;
            end if;
          end if;

          rin.rsp_state <= RSP_W_RUN;
        end if;

      when RSP_W_RUN =>
        if dp_rsp_i.valid = '1' then
          if r.rsp_left /= 0 then
            rin.rsp_left <= r.rsp_left - 1; 
            rin.rsp_state <= RSP_W_STATUS;
         else
            rin.rsp_last <= r.cmd_last;
            rin.rsp_state <= RSP_RW_WRAPUP;
          end if;
        end if;

      when RSP_RW_WRAPUP =>
        if rsp_i.ready = '1' then
          rin.rsp_state <= RSP_IDLE;
        end if;

      when RSP_TAR_STATUS =>
        if dp_rsp_i.valid = '1' then
          rin.rsp_state <= RSP_IDLE;
        end if;

      when RSP_RAW_GET =>
        if dp_rsp_i.valid = '1' then
          rin.rsp_data <= dp_rsp_i.data;
          rin.rsp_last <= r.cmd_last;
          rin.rsp_state <= RSP_RAW_SET;
        end if;

      when RSP_RAW_SET =>
        if rsp_i.ready = '1' then
          if r.rsp_left /= 0 then
            rin.rsp_left <= r.rsp_left - 1;
            rin.rsp_state <= RSP_RAW_GET;
          else
            rin.rsp_state <= RSP_IDLE;
          end if;
        end if;

      when RSP_RAW_PT_GET =>
        if dp_rsp_i.valid = '1' then
          rin.rsp_data <= dp_rsp_i.data;
          rin.rsp_last <= dp_rsp_i.last = '1';
          rin.rsp_state <= RSP_RAW_PT_SET;
        end if;

      when RSP_RAW_PT_SET =>
        if rsp_i.ready = '1' then
          if r.rsp_last then
            rin.rsp_state <= RSP_IDLE;
          else
            rin.rsp_state <= RSP_RAW_PT_GET;
          end if;
        end if;

      when RSP_NOP =>
        if rsp_i.ready = '1' then
          rin.rsp_state <= RSP_IDLE;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    cmd_o <= framed_ack_idle_c;
    dp_cmd_o <= framed_req_idle_c;

    case r.cmd_state is
      when CMD_RESET | CMD_ROUTE | CMD_WAIT_RSP =>
        null;

      when CMD_IDLE | CMD_W_DRW_GET | CMD_RAW_GET | CMD_CSW_BASE_DATA | CMD_RAW_PT_GET =>
        cmd_o <= framed_accept(true);
  
      when CMD_RW_ABORT =>
        dp_cmd_o <= framed_flit(data => DP_CMD_ABORT);

      when CMD_RW_CSW_CMD =>
        dp_cmd_o <= framed_flit(data => DP_CMD_AP_WRITE(7 downto 4) & memap_csw_c);

      when CMD_RW_CSW_VAR =>
        dp_cmd_o <= framed_flit(data => "00010" & r.csw_size);

      when CMD_RW_CSW_CST =>
        dp_cmd_o <= framed_flit(data => first_left(r.csw_base));

      when CMD_R_DRW_CMD =>
        dp_cmd_o <= framed_flit(data => DP_CMD_AP_READ(7 downto 4) & memap_drw_c);

      when CMD_R_DRW_RUN =>
        dp_cmd_o <= framed_flit(data => DP_CMD_RUN_0(7 downto 6) & std_ulogic_vector(r.interval));

      when CMD_R_RDBUFF =>
        dp_cmd_o <= framed_flit(data => DP_CMD_DP_READ(7 downto 4) & dp_rdbuff_c);

      when CMD_R_RDBUFF_RUN | CMD_W_RUN =>
        dp_cmd_o <= framed_flit(data => DP_CMD_RUN_0(7 downto 6) & std_ulogic_vector(r.interval),
                                last => r.cmd_left = 0 and r.cmd_last);

      when CMD_W_DRW_CMD =>
        dp_cmd_o <= framed_flit(data => DP_CMD_AP_WRITE(7 downto 4) & memap_drw_c);

      when CMD_W_DRW_SET =>
        dp_cmd_o <= framed_flit(data => r.cmd_data);

      when CMD_RAW_SET =>
        dp_cmd_o <= framed_flit(data => r.cmd_data,
                                last => r.cmd_left = 0 and r.cmd_last);

      when CMD_RAW_PT_SET =>
        dp_cmd_o <= framed_flit(data => r.cmd_data,
                                last => r.cmd_last);

      when CMD_TAR_CMD =>
        dp_cmd_o <= framed_flit(data => DP_CMD_AP_WRITE(7 downto 4) & memap_tar_c);
    end case;
    
    rsp_o <= framed_req_idle_c;
    dp_rsp_o <= framed_ack_idle_c;

    case r.rsp_state is
      when RSP_RESET | RSP_IDLE =>
        null;
        
      when RSP_RW_ABORT | RSP_RW_CSW_STATUS | RSP_R_INIT_DATA | RSP_R_INIT_STATUS
        | RSP_R_INIT_RUN | RSP_R_DATA_DATA_GET | RSP_R_DATA_STATUS | RSP_R_DATA_RUN
        | RSP_W_STATUS | RSP_W_RUN | RSP_TAR_STATUS | RSP_RAW_GET | RSP_RAW_PT_GET =>
        dp_rsp_o <= framed_accept(true);

      when RSP_R_DATA_DATA_SET =>
        rsp_o <= framed_flit(r.rsp_data);

      when RSP_RW_WRAPUP =>
        rsp_o <= framed_flit(data => to_logic(r.rsp_error) & std_ulogic_vector(to_unsigned(r.rsp_error_index, 7)),
                             last => r.rsp_last);

      when RSP_RAW_SET =>
        rsp_o <= framed_flit(data => r.rsp_data,
                             last => r.rsp_last and r.rsp_left = 0);

      when RSP_NOP =>
        rsp_o <= framed_flit(data => r.rsp_data,
                             last => r.rsp_last);

      when RSP_RAW_PT_SET =>
        rsp_o <= framed_flit(data => r.rsp_data,
                             last => r.rsp_last);
    end case;
  end process;

end architecture;
