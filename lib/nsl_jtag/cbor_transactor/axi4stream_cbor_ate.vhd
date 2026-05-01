library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_io, nsl_amba, nsl_data, nsl_simulation;
use nsl_data.cbor.all;

entity axi4stream_cbor_ate is
  generic(
    stream_config_c : nsl_amba.axi4_stream.config_t
    );
  port (
    clock_i      : in  std_ulogic;
    reset_n_i    : in  std_ulogic;

    tick_i       : in std_ulogic;
    tick_ms_i : in std_ulogic;

    cmd_i        : in nsl_amba.axi4_stream.master_t;
    cmd_o        : out nsl_amba.axi4_stream.slave_t;
    rsp_o        : out nsl_amba.axi4_stream.master_t;
    rsp_i        : in nsl_amba.axi4_stream.slave_t;

    jtag_o       : out nsl_jtag.jtag.jtag_ate_o;
    jtag_i       : in nsl_jtag.jtag.jtag_ate_i
    );
end entity;

architecture rtl of axi4stream_cbor_ate is

  
  constant data_max_size_c      : natural := 8;
  constant cbr_hdr_max_size_c   : natural := 3;
  constant buffer_cfg_c         : nsl_amba.axi4_stream.buffer_config_t := nsl_amba.axi4_stream.buffer_config(axi_s_cfg_c, cbr_hdr_max_size_c);

  type state_t is (
    ST_RESET,

    ST_ARRAY_GET,
    ST_ARRAY_ENTER,

    ST_CMD_GET,
    ST_CMD_EXEC,
    ST_CMD_END,

    ST_ATE_RUN,
    ST_ATE_WAIT_FOR_DONE,

    ST_ATE_RUN_MS,
    ST_ATE_RUN_MS_WAIT_FOR_DONE,

    ST_DATA_GET,
    ST_DATA_RUN,
    ST_DATA_GET_RSP,
    ST_DATA_PUT,

    ST_RSP_ARRAY_HDR_PREP,
    ST_RSP_ARRAY_HDR_PUT, 
    ST_RSP_BSTR_HDR_PREP,
    ST_RSP_BSTR_HDR_PUT,
    ST_RSP_BREAK_PREP,
    ST_RSP_BREAK_PUT,
    ST_ERROR_DRAIN
  );
  
  type regs_t is
  record
    state         : state_t;
    
    cmd_pending   : nsl_jtag.ate.ate_op;
    cmd_bit_count : natural range 0 to data_max_size_c - 1;
    
    has_tdo       : boolean;
    has_tdi       : boolean;
    data          : std_ulogic_vector(7 downto 0);
    bit_count     : natural range 0 to 8;
    word_count    : natural range 0 to 4095;
    
    parser        : nsl_data.cbor.parser_t;
    indefinite    : boolean;
    tag           : natural range 0 to 11;
    command_count : natural range 0 to 1023;
    inside_cmd    : boolean;
    
    encoded       : nsl_amba.axi4_stream.buffer_t;
    last          : boolean;
  end record;

  signal r, rin: regs_t;
  
  signal s_cmd_ready    : std_ulogic;
  signal s_cmd_valid    : std_ulogic;

  signal s_rsp_ready    : std_ulogic;
  signal s_rsp_valid    : std_ulogic;
  signal s_rsp_data     : std_ulogic_vector(data_max_size_c-1 downto 0);
  
  constant c_print_logs : boolean := false;

  function state_to_string(s : state_t) return string is
  begin
   case s is
     when ST_RESET              => return "ST_RESET";
     when ST_ARRAY_GET          => return "ST_ARRAY_GET";
     when ST_ARRAY_ENTER        => return "ST_ARRAY_ENTER";
     when ST_CMD_GET            => return "ST_CMD_GET";
     when ST_CMD_EXEC           => return "ST_CMD_EXEC";
     when ST_CMD_END            => return "ST_CMD_END";
     when ST_ATE_RUN            => return "ST_ATE_RUN";
     when ST_ATE_WAIT_FOR_DONE  => return "ST_ATE_WAIT_FOR_DONE";
     when ST_DATA_GET           => return "ST_DATA_GET";
     when ST_DATA_RUN           => return "ST_DATA_RUN";
     when ST_DATA_GET_RSP       => return "ST_DATA_GET_RSP";
     when ST_DATA_PUT           => return "ST_DATA_PUT";
     when ST_RSP_ARRAY_HDR_PREP => return "ST_RSP_ARRAY_HDR_PREP";
     when ST_RSP_ARRAY_HDR_PUT  => return "ST_RSP_ARRAY_HDR_PUT";
     when ST_RSP_BSTR_HDR_PREP  => return "ST_RSP_BSTR_HDR_PREP";
     when ST_RSP_BSTR_HDR_PUT   => return "ST_RSP_BSTR_HDR_PUT";
     when ST_RSP_BREAK_PREP     => return "ST_RSP_BREAK_PREP";
     when ST_RSP_BREAK_PUT      => return "ST_RSP_BREAK_PUT";
     when ST_ERROR_DRAIN        => return "ST_ERROR_DRAIN";
     when others                => return "UNKNOWN";
   end case;
  end;
  
  procedure log_state_change(r : regs_t; rin: regs_t) is  begin
    if c_print_logs then
      nsl_simulation.logging.log_info("In " & state_to_string(r.state) & " => " & state_to_string(rin.state) & LF );
    end if;
  end procedure;

  -- Returns a mask with bits (size_m1 downto 0) set to '1'
  function bit_mask(size_m1 : natural range 0 to 7) return std_ulogic_vector is
    variable mask : std_ulogic_vector(7 downto 0) := (others => '0');
  begin
    mask(size_m1 downto 0) := (others => '1');
    return mask;
  end function;

begin
  
  assert nsl_amba.axi4_stream.byte_count(stream_config_c, cmd_i) = 1
    report "AXI-Stream bad data length, must be 1 byte"
    severity failure;
  
  assert stream_config_c.has_last = true
    report "AXI-Stream configuration incorrect, must have TLAST"
    severity failure;
  
  assert stream_config_c.has_ready = true
    report "AXI-Stream configuration incorrect, must have TREADY"
    severity failure;

  reg: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
      if rin.state = r.state then
      else
        log_state_change(r => r, rin => rin);
      end if;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process (cmd_i, r, rsp_i, tick_ms_i,
                       s_cmd_ready, s_rsp_data, s_rsp_valid)
    variable data : std_ulogic_vector(7 downto 0);
  begin
    rin <= r;

    if r.state = ST_ATE_RUN_MS or r.state = ST_ATE_RUN_MS_WAIT_FOR_DONE then
      if tick_ms_i = '1' then
        if r.word_count /= 0 then
          rin.word_count <= r.word_count - 1;
        end if;
      end if;
    end if;

    case r.state is
      
      when ST_RESET =>
          nsl_simulation.logging.log_info("In ST_RESET");

          rin.has_tdo       <= true;
          rin.has_tdi       <= true;
          rin.data          <= (others => '-');
          rin.bit_count     <= 8;
          rin.word_count    <= 0;
          rin.parser        <= nsl_data.cbor.reset;
          rin.indefinite    <= false;
          rin.command_count <= 0;
          rin.encoded       <= nsl_amba.axi4_stream.reset(buffer_cfg_c);
          rin.last          <= false;
          rin.inside_cmd    <= false;
          rin.tag           <= 0;

          rin.state         <= ST_ARRAY_GET;

      when ST_ARRAY_GET =>
        if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
          nsl_simulation.logging.log_info("In ST_ARRAY_GET, parsing a byte");
          data := nsl_data.bytestream.first_left(nsl_amba.axi4_stream.bytes(stream_config_c, cmd_i));
          rin.parser <= nsl_data.cbor.feed(r.parser, data);
          if nsl_data.cbor.is_last( r.parser, data ) then
            rin.state <= ST_ARRAY_ENTER;
          end if;
        end if;

      when ST_ARRAY_ENTER =>
        if nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_ARRAY then
          if not r.parser.indefinite then
            rin.command_count <= nsl_data.cbor.arg_int(r.parser);
            rin.indefinite    <= false;
          else
            rin.indefinite    <= true;
          end if;
          rin.parser <= nsl_data.cbor.reset;
          rin.state  <= ST_RSP_ARRAY_HDR_PREP;
        else
          nsl_simulation.logging.log_warning("Expected CBOR array, draining frame");
          rin.last  <= true;
          rin.state <= ST_ERROR_DRAIN;
        end if;

      when ST_CMD_GET =>
        if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
          data := nsl_data.bytestream.first_left(nsl_amba.axi4_stream.bytes(stream_config_c, cmd_i));
          rin.parser <= nsl_data.cbor.feed(r.parser, data );
          if nsl_data.cbor.is_last( r.parser, data ) then
            rin.state <= ST_CMD_EXEC;
            if not r.indefinite and not r.inside_cmd then
              rin.command_count <= r.command_count - 1;
              rin.bit_count <= 8;
            end if;
          end if;
        end if;

      when ST_CMD_EXEC =>
        rin.inside_cmd <= false;
        if nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_TAG then
          rin.tag <= nsl_data.cbor.arg_int(r.parser);
          if nsl_data.cbor.arg_int(r.parser) > 0 and nsl_data.cbor.arg_int(r.parser) < 8 then -- minus
            rin.bit_count  <= data_max_size_c - nsl_data.cbor.arg_int(r.parser) - 1;
            rin.inside_cmd <= true;
            rin.state      <= ST_CMD_GET; -- going to get the bstr header
          elsif nsl_data.cbor.arg_int(r.parser) = 8 then -- SHIFT with no TDI
            rin.has_tdi    <= false;
            rin.inside_cmd <= true;
            rin.state      <= ST_CMD_GET; -- going to get the number of cycles to shift
          elsif nsl_data.cbor.arg_int(r.parser) = 9 then -- SHIFT with no TDO
            rin.has_tdo    <= false;
            rin.inside_cmd <= true;
            rin.state      <= ST_CMD_GET; -- going to get the data to SHIFT IN
          elsif nsl_data.cbor.arg_int(r.parser) = 10 then -- reset for N cycles
            rin.inside_cmd <= true;
            rin.state      <= ST_CMD_GET;  -- going to get the number of cycles
          elsif nsl_data.cbor.arg_int(r.parser) = 11 then -- RTI for N ms
            rin.inside_cmd <= true;
            rin.state      <= ST_CMD_GET; -- going to get the number of ms
          else
            nsl_simulation.logging.log_warning("Unhandled CBOR tag, draining frame");
            rin.last  <= false;
            rin.state <= ST_ERROR_DRAIN;
          end if;
        
        elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_POSITIVE then
          if r.tag = 0 then -- not inside a tag!!
            rin.cmd_bit_count <= 0;
            rin.word_count  <= nsl_data.cbor.arg_int(r.parser);
            rin.cmd_pending <= nsl_jtag.ate.ATE_OP_RTI;
            rin.state       <= ST_ATE_RUN;
          elsif r.tag > 0 and r.tag < 8 then
            rin.word_count  <= nsl_data.cbor.arg_int(r.parser)-1;
            rin.cmd_pending <= nsl_jtag.ate.ATE_OP_SHIFT;
            rin.state     <= ST_RSP_BSTR_HDR_PREP;
          elsif r.tag = 8 then
            rin.word_count  <= (nsl_data.cbor.arg_int(r.parser)+7)/8;
            if nsl_data.cbor.arg_int(r.parser) mod 8 = 0 then
              rin.bit_count <= 8;
            else
              rin.bit_count <= nsl_data.cbor.arg_int(r.parser) mod 8 - 1;
            end if;
            rin.cmd_pending <= nsl_jtag.ate.ATE_OP_SHIFT;
            rin.state     <= ST_RSP_BSTR_HDR_PREP;
          elsif r.tag = 10 then
            rin.cmd_bit_count <= 0;
            rin.word_count  <= nsl_data.cbor.arg_int(r.parser)-1;
            rin.cmd_pending <= nsl_jtag.ate.ATE_OP_RESET;
            rin.state       <= ST_ATE_RUN;
          elsif r.tag = TAG_RUN_MS then
            rin.word_count    <= nsl_data.cbor.arg_int(r.parser) + 1;
            rin.cmd_bit_count <= 0;
            rin.cmd_pending   <= nsl_jtag.ate.ATE_OP_RTI;
            rin.state         <= ST_ATE_RUN_MS;
          else
            nsl_simulation.logging.log_warning("Unhandled tag context for positive value, draining frame");
            rin.last  <= false;
            rin.state <= ST_ERROR_DRAIN;
          end if;

        elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_BSTR then
          rin.word_count  <= nsl_data.cbor.arg_int(r.parser);
          rin.cmd_pending <= nsl_jtag.ate.ATE_OP_SHIFT;
          if r.has_tdo then
            rin.state <= ST_RSP_BSTR_HDR_PREP;
          else
            rin.state <= ST_DATA_GET;
          end if;

        elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_SIMPLE then
          rin.cmd_bit_count <= 0;
          if nsl_data.cbor.arg_int(r.parser) = 1 then
            rin.cmd_pending <= nsl_jtag.ate.ATE_OP_DR_CAPTURE;
            rin.state <= ST_ATE_RUN;
          elsif nsl_data.cbor.arg_int(r.parser) = 2 then
            rin.cmd_pending <= nsl_jtag.ate.ATE_OP_IR_CAPTURE;
            rin.state <= ST_ATE_RUN;
          elsif nsl_data.cbor.arg_int(r.parser) = 3 then
            rin.cmd_pending <= nsl_jtag.ate.ATE_OP_SWD_TO_JTAG;
            rin.state <= ST_ATE_RUN;
          else
            nsl_simulation.logging.log_warning("Unhandled CBOR simple value, draining frame");
            rin.last  <= false;
            rin.state <= ST_ERROR_DRAIN;
          end if;

        elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_BREAK then
          if r.indefinite then
            rin.state  <= ST_RSP_BREAK_PREP;
          else
            nsl_simulation.logging.log_warning("Found break code inside definite length array, draining frame");
            rin.last  <= false;
            rin.state <= ST_ERROR_DRAIN;
          end if;

        else
          nsl_simulation.logging.log_warning("Unknown CBOR type: " & nsl_data.cbor.kind_t'image(nsl_data.cbor.kind(r.parser)) & ", draining frame");
          rin.last  <= false;
          rin.state <= ST_ERROR_DRAIN;
        end if;
        rin.parser <= nsl_data.cbor.reset;

      when ST_CMD_END =>
        if not r.indefinite and r.command_count = 0 then
          rin.state <= ST_RSP_BREAK_PREP;
        else
          rin.state <= ST_CMD_GET;
        end if;
        rin.tag <= 0;
        rin.has_tdo       <= true;
        rin.has_tdi       <= true;
        rin.data          <= (others => '-');
        rin.bit_count     <= 8;
        rin.parser <= nsl_data.cbor.reset;

     when ST_ATE_RUN =>
        if s_cmd_ready = '1' then
          rin.state <= ST_ATE_WAIT_FOR_DONE;
        end if;

      when ST_ATE_WAIT_FOR_DONE =>
        if s_cmd_ready = '1' then
          if r.word_count /= 0 then
            rin.word_count <= r.word_count - 1;
            rin.state      <= ST_ATE_RUN;
          else
            rin.state <= ST_CMD_END;
          end if;
        end if;

      when ST_ATE_RUN_MS =>
        if s_cmd_ready = '1' then
          rin.state <= ST_ATE_RUN_MS_WAIT_FOR_DONE;
        end if;

      when ST_ATE_RUN_MS_WAIT_FOR_DONE =>
        if s_cmd_ready = '1' then
          if r.word_count /= 0 then
            rin.state <= ST_ATE_RUN_MS;
          else
            rin.state <= ST_CMD_END;
          end if;
        end if;

      when ST_DATA_GET =>
        rin.cmd_bit_count <= data_max_size_c - 1;
        if (r.word_count = 1) and (r.bit_count /= 8) then
          rin.cmd_bit_count <= r.bit_count;
        end if;

        if r.has_tdi then
          if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
            rin.data <= nsl_data.bytestream.first_left(nsl_amba.axi4_stream.bytes(stream_config_c, cmd_i));
            if r.word_count /= 0 then
              rin.word_count <= r.word_count - 1;
            end if;
            rin.state <= ST_DATA_RUN;
          end if;
        else
          rin.data <= (others => '0');
          if r.word_count /= 0 then
            rin.word_count <= r.word_count - 1;
          end if;
          rin.state <= ST_DATA_RUN;
        end if;

      when ST_DATA_RUN =>
        if s_cmd_ready = '1' then
          rin.state <= ST_DATA_GET_RSP;
        end if;

      when ST_DATA_GET_RSP =>
        if s_rsp_valid = '1' then
          rin.data <= s_rsp_data;
          rin.state <= ST_DATA_PUT;
        end if;
  
      when ST_DATA_PUT =>
        if not r.has_tdo or nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          if r.word_count = 0 then
            rin.state <= ST_CMD_END;
          else
            rin.state <= ST_DATA_GET;
          end if;
        end if;

      when ST_RSP_ARRAY_HDR_PREP =>
          rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_array_hdr(length => -1) );
          rin.state <= ST_RSP_ARRAY_HDR_PUT;
          rin.last  <= false;

      when ST_RSP_ARRAY_HDR_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
            if nsl_amba.axi4_stream.is_last(buffer_cfg_c, r.encoded) then
              rin.state <= ST_CMD_GET;
            end if;
            rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
          end if;

      when ST_RSP_BSTR_HDR_PREP =>
          rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_bstr_hdr(length => to_unsigned(r.word_count, 12) ) ); --TODO
          rin.state <= ST_RSP_BSTR_HDR_PUT;
          rin.last  <= false;

      when ST_RSP_BSTR_HDR_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
            if nsl_amba.axi4_stream.is_last(buffer_cfg_c, r.encoded) then
              rin.state <= ST_DATA_GET;
            end if;
            rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
          end if;
          
      when ST_RSP_BREAK_PREP =>
          rin.data  <= nsl_data.cbor.cbor_break(0);
          rin.last  <= true;
          rin.state <= ST_RSP_BREAK_PUT;
    
      when ST_RSP_BREAK_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
            rin.state <= ST_ARRAY_GET;
          end if;

      when ST_ERROR_DRAIN =>
        if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
          if nsl_amba.axi4_stream.is_last(stream_config_c, cmd_i) then
            if r.last then
              rin.parser <= nsl_data.cbor.reset;
              rin.state <= ST_ARRAY_GET;
            else
              rin.state <= ST_RSP_BREAK_PREP;
            end if;
          end if;
        end if;
    end case;
  end process;

  moore: process (r)
  begin
    cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, false);
    rsp_o <= nsl_amba.axi4_stream.transfer_defaults(cfg => stream_config_c);

    s_rsp_ready <= '0';
    s_cmd_valid <= '0';

  case r.state is

    when ST_RESET | ST_ARRAY_ENTER | ST_CMD_EXEC | ST_CMD_END =>

    when ST_ARRAY_GET =>
        cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, true);

    when ST_CMD_GET | ST_ERROR_DRAIN =>
        cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, true);

      when ST_ATE_RUN | ST_ATE_RUN_MS | ST_DATA_RUN =>
        s_cmd_valid <= '1';

    when ST_DATA_GET =>
      if r.has_tdi then
          cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, true);
      end if;
      
    when ST_DATA_PUT =>
      if r.has_tdo then
        -- Mask upper bits for partial-byte shifts (minus tags or tag 8 with non-multiple of 8)
        -- bit_count is size_m1: 0 means 1 bit valid, 6 means 7 bits valid, 8 means full byte
        if r.word_count = 0 and r.bit_count /= 8 then
            rsp_o <= nsl_amba.axi4_stream.transfer( cfg => stream_config_c,
            bytes => nsl_data.bytestream.from_suv(r.data and bit_mask(r.bit_count)), last => r.last);
        else
            rsp_o <= nsl_amba.axi4_stream.transfer( cfg => stream_config_c, bytes => nsl_data.bytestream.from_suv(r.data), last => r.last);
        end if;
      end if;
    
    when ST_RSP_BREAK_PUT =>
        rsp_o <= nsl_amba.axi4_stream.transfer( cfg => stream_config_c, bytes => nsl_data.bytestream.from_suv(r.data), last => r.last);

    when ST_RSP_ARRAY_HDR_PREP | ST_RSP_BSTR_HDR_PREP | ST_RSP_BREAK_PREP =>

      when ST_ATE_WAIT_FOR_DONE | ST_ATE_RUN_MS_WAIT_FOR_DONE | ST_DATA_GET_RSP =>
        s_rsp_ready <= '1';
    
    when ST_RSP_ARRAY_HDR_PUT | ST_RSP_BSTR_HDR_PUT =>
      rsp_o <= nsl_amba.axi4_stream.next_beat(cfg => buffer_cfg_c, b => r.encoded, last => r.last);

  end case;
  end process;

  ate: nsl_jtag.ate.jtag_ate
    generic map (
      data_max_size => data_max_size_c,
      allow_pipelining => false
      )
    port map (
      reset_n_i => reset_n_i,
      clock_i   => clock_i,

      tick_i => tick_i,

      cmd_ready_o   => s_cmd_ready,
      cmd_valid_i   => s_cmd_valid,
      cmd_op_i      => r.cmd_pending,
      cmd_data_i    => r.data,
      cmd_size_m1_i => r.cmd_bit_count,

      rsp_ready_i => s_rsp_ready,
      rsp_valid_o => s_rsp_valid,
      rsp_data_o  => s_rsp_data,

      jtag_o => jtag_o,
      jtag_i => jtag_i
      );

end architecture;
