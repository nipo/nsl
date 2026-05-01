library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight, nsl_amba, nsl_data, nsl_simulation, nsl_logic;
use nsl_data.cbor.all;
use nsl_data.bytestream.all;

entity axi4stream_cbor_dp_transactor is
  generic(
    clock_i_hz_c    : natural;
    stream_config_c : nsl_amba.axi4_stream.config_t
    );
  port (
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;
    
    tick_i    : in std_ulogic;

    swd_o     : out nsl_coresight.swd.swd_master_o;
    swd_i     : in  nsl_coresight.swd.swd_master_i;

    cmd_i     : in nsl_amba.axi4_stream.master_t;
    cmd_o     : out nsl_amba.axi4_stream.slave_t;

    rsp_o     : out nsl_amba.axi4_stream.master_t;
    rsp_i     : in nsl_amba.axi4_stream.slave_t
  );
end entity;

architecture rtl of axi4stream_cbor_dp_transactor is
  constant cbr_hdr_max_size_c : natural := 5;
  constant buffer_cfg_c       : nsl_amba.axi4_stream.buffer_config_t := nsl_amba.axi4_stream.buffer_config(stream_config_c, cbr_hdr_max_size_c);

  constant err_ok_c     : std_ulogic_vector(2 downto 0) := "001"; 
  constant err_wait_c   : std_ulogic_vector(2 downto 0) := "010"; 
  constant err_fault_c  : std_ulogic_vector(2 downto 0) := "100"; 
  constant err_parity_c : std_ulogic_vector(3 downto 0) := "1000"; 
  
  type state_t is (
    ST_RESET,

    ST_ARRAY_GET,             -- Enter array and get number of items
    ST_ARRAY_ENTER,

    ST_CMD_GET,               -- Get individual commands in payload
    ST_CMD_EXEC,              -- Parse another byte of the stream
                              -- and execute individual commands in payload
    ST_CMD_END,               -- End execution of a command and return to parsing of
                              -- commands or to parsing of commands array if that command
                              -- was the last one

    ST_DATA_GET,              -- Get data to write

    ST_CMD_SHIFT,             -- Send SWD request
    ST_CMD_TURNAROUND,        -- Wait for turnaround cycles

    ST_ACK_SHIFT,             -- Get ACK bits
    ST_ACK_TURNAROUND,        -- Wait for turnaround cycles
    
    ST_DATA_SHIFT_OUT,        -- Write data
    ST_PARITY_SHIFT_OUT,      -- Write parity bit

    ST_RSP_WRITE_STATUS_PREP, -- Build Write response: array of 2 elements
    ST_RSP_WRITE_STATUS_PUT,  -- Send Write response

    ST_RSP_READ_STATUS_PREP,  -- Complete read response: close indefinite len
                              -- bstr and add status and word offset
    ST_RSP_READ_STATUS_PUT,   -- Send read response closer
    
    ST_DATA_SHIFT_IN,         -- Read data
    ST_PARITY_SHIFT_IN,       -- Read parity bit

    ST_DATA_PREP,             -- Prepare read data to send in rsp. Aglomerates 4 bytes (1
                              -- word) to be sent in the next state
    ST_DATA_PUT,              -- Send a read word in rsp

    ST_DATA_TURNAROUND,       -- Wait for turnaround cycles

    ST_RUN,                   -- Run for r.cycle_count cycles

    ST_BITBANG,               -- Bitbang data in r.data for r.cycle_counts cycles
                              -- (LSB first)
    
    ST_RSP_READ_HDR_PREP,     -- Read response header: 3-element array header
                              -- and indefinite length bstr header
    ST_RSP_READ_HDR_PUT,      -- Send read response header
    
    ST_RSP_ARRAY_HDR_PREP,    -- Indefinite-length array header, for the
                              -- response to the complete command stream.
    ST_RSP_ARRAY_HDR_PUT,     -- Send header

    ST_RSP_BSTR_HDR_PREP,     -- Definite-length bstr header. Size: 4 bytes,
                              -- a 32 bit word. This bstr will contain the read data
    ST_RSP_BSTR_HDR_PUT,      -- Send bstr header

    ST_RSP_BSTR_BREAK_PREP,   -- Break code for indefinite length bstr.
    ST_RSP_BSTR_BREAK_PUT,    -- Put break code

    ST_RSP_BREAK_PREP,        -- Break code for indefinite length array.
    ST_RSP_BREAK_PUT,         -- Put break code

    ST_CMD_CANCELLED,         -- If a command is cancelled, flush input data,

    ST_ERROR_DRAIN
    );

  type regs_t is record
    state         : state_t;

    cmd           : std_ulogic_vector(7 downto 0);
    cycle         : natural range 0 to 3;
    data          : std_ulogic_vector(31 downto 0);

    parser        : nsl_data.cbor.parser_t;
    tag           : natural range 0 to 11; 
    command_count : natural range 0 to 1023;
    cmd_cancelled : boolean;
    indefinite    : boolean;
    inside_cmd    : boolean;
    
    encoded       : nsl_amba.axi4_stream.buffer_t;
    last          : boolean;

    ack           : std_ulogic_vector(2 downto 0);
    turnaround    : natural range 0 to 3;
    wait_cycles   : natural range 0 to 128;
    cycle_count   : natural range 0 to 256;
    word_count    : natural range 0 to 31;
    word_total    : natural range 0 to 31;

    op            : std_ulogic_vector(7 downto 0);
    run_val       : std_ulogic;
    is_read       : boolean;
    is_bitbang    : boolean;

    par_in        : std_ulogic;
    par_out       : std_ulogic;

    swd           : nsl_coresight.swd.swd_master_o;
  end record;

  signal r, rin: regs_t;

  function state_to_string(s : state_t) return string is
  begin
    case s is
    when ST_RESET                 => return "ST_RESET";
    when ST_ARRAY_GET             => return "ST_ARRAY_GET";
    when ST_ARRAY_ENTER           => return "ST_ARRAY_ENTER";
    when ST_CMD_GET               => return "ST_CMD_GET";
    when ST_CMD_EXEC              => return "ST_CMD_EXEC";
    when ST_CMD_END               => return "ST_CMD_END";
    when ST_DATA_GET              => return "ST_DATA_GET";
    when ST_DATA_PREP             => return "ST_DATA_PREP";
    when ST_DATA_PUT              => return "ST_DATA_PUT";
    when ST_CMD_SHIFT             => return "ST_CMD_SHIFT";
    when ST_CMD_TURNAROUND        => return "ST_CMD_TURNAROUND";
    when ST_ACK_SHIFT             => return "ST_ACK_SHIFT";
    when ST_ACK_TURNAROUND        => return "ST_ACK_TURNAROUND";
    when ST_DATA_SHIFT_OUT        => return "ST_DATA_SHIFT_OUT";
    when ST_PARITY_SHIFT_OUT      => return "ST_PARITY_SHIFT_OUT";
    when ST_DATA_SHIFT_IN         => return "ST_DATA_SHIFT_IN";
    when ST_PARITY_SHIFT_IN       => return "ST_PARITY_SHIFT_IN";
    when ST_DATA_TURNAROUND       => return "ST_DATA_TURNAROUND";
    when ST_RUN                   => return "ST_RUN";
    when ST_BITBANG               => return "ST_BITBANG";
    when ST_RSP_WRITE_STATUS_PREP => return "ST_RSP_WRITE_STATUS_PREP";
    when ST_RSP_WRITE_STATUS_PUT  => return "ST_RSP_WRITE_STATUS_PUT";
    when ST_RSP_READ_STATUS_PREP  => return "ST_RSP_READ_STATUS_PREP";
    when ST_RSP_READ_STATUS_PUT   => return "ST_RSP_READ_STATUS_PUT";
    when ST_RSP_READ_HDR_PREP     => return "ST_RSP_READ_HDR_PREP";
    when ST_RSP_READ_HDR_PUT      => return "ST_RSP_READ_HDR_PUT";
    when ST_RSP_ARRAY_HDR_PREP    => return "ST_RSP_ARRAY_HDR_PREP";
    when ST_RSP_ARRAY_HDR_PUT     => return "ST_RSP_ARRAY_HDR_PUT";
    when ST_RSP_BSTR_HDR_PREP     => return "ST_RSP_BSTR_HDR_PREP";
    when ST_RSP_BSTR_HDR_PUT      => return "ST_RSP_BSTR_HDR_PUT";
    when ST_RSP_BSTR_BREAK_PREP   => return "ST_RSP_BSTR_BREAK_PREP";
    when ST_RSP_BSTR_BREAK_PUT    => return "ST_RSP_BSTR_BREAK_PUT";
    when ST_RSP_BREAK_PREP        => return "ST_RSP_BREAK_PREP";
    when ST_RSP_BREAK_PUT         => return "ST_RSP_BREAK_PUT";
    when ST_CMD_CANCELLED         => return "ST_CMD_CANCELLED";
    when ST_ERROR_DRAIN           => return "ST_ERROR_DRAIN";
    end case;
  end;
  
  constant c_print_logs : boolean := false;
  
  procedure log_state_change(r : regs_t; rin: regs_t) is  begin
    if c_print_logs then
      nsl_simulation.logging.log_info("In " & state_to_string(r.state) & " => " & state_to_string(rin.state) & LF);
    end if;
  end procedure;
  
  function swd_cmd(reg : integer; ap : boolean; read : boolean) return std_ulogic_vector
  is
    variable cmd : std_ulogic_vector(7 downto 0);
  begin
    cmd(7 downto 6) := "10"; -- park and stop bits

    cmd(4 downto 3) := std_ulogic_vector(to_unsigned(reg, 2));
    cmd(2) := nsl_logic.bool.to_logic(read);
    cmd(1) := nsl_logic.bool.to_logic(ap);
    cmd(0) := '1'; -- start bit

    cmd(5) := cmd(1) xor cmd(2) xor cmd(3) xor cmd(4); -- parity

    return cmd;
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
  
  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
      if rin.state /= r.state then
        log_state_change(r => r, rin => rin);
      end if;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.swd.clk <= '0';
    end if;
  end process;  

  transition: process(r, cmd_i, rsp_i, swd_i, tick_i)
    variable tag           : natural range 0 to 11;
    variable swclk_falling : boolean;
    variable swclk_rising  : boolean;
    variable status        : std_ulogic_vector(3 downto 0);
  begin
    rin <= r;
    
    swclk_falling := false;
    swclk_rising := false;
    
    case r.state is
      when ST_CMD_SHIFT | ST_CMD_TURNAROUND | ST_ACK_SHIFT | ST_ACK_TURNAROUND | ST_DATA_SHIFT_IN | ST_DATA_SHIFT_OUT | ST_DATA_TURNAROUND | ST_PARITY_SHIFT_IN | ST_PARITY_SHIFT_OUT | ST_RUN | ST_BITBANG =>
        if tick_i = '1' then
          rin.swd.clk <= not r.swd.clk;
          swclk_falling := r.swd.clk = '1';
          swclk_rising := r.swd.clk = '0';
        end if;
        
      when others =>
        
    end case;

    case r.state is
      when ST_RESET =>
        rin.state         <= ST_ARRAY_GET;
        rin.cmd           <= (others => '-');
        rin.last          <= false;
        rin.cycle         <= 0;
        rin.data          <= (others => '-');
        rin.parser        <= nsl_data.cbor.reset;
        rin.tag           <= 0;
        rin.command_count <= 0;
        rin.word_total    <= 0;
        rin.word_count    <= 0;
        rin.indefinite    <= false;
        rin.inside_cmd    <= false;
        rin.encoded       <= nsl_amba.axi4_stream.reset(buffer_cfg_c);
        rin.swd.clk       <= '0';
        rin.swd.dio.v     <= '0';
        rin.turnaround    <=  0;
        rin.run_val       <= '0';
        rin.is_bitbang    <= false;
        rin.par_in        <= '0';
        rin.par_out       <= '0';
        rin.cmd_cancelled <= false;

      when ST_ARRAY_GET =>
        rin.cmd_cancelled <= false;
        if cmd_i.valid = '1' then
          rin.parser <= nsl_data.cbor.feed(r.parser, cmd_i.data(0));
          if nsl_data.cbor.is_last(r.parser, cmd_i.data(0)) then
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
            rin.parser <= nsl_data.cbor.feed(r.parser, cmd_i.data(0));
            if nsl_data.cbor.is_last(r.parser, cmd_i.data(0)) then
              rin.state <= ST_CMD_EXEC;
              if not r.indefinite and not r.inside_cmd then
                rin.command_count <= r.command_count - 1;
              end if;
            end if;
          end if;

      when ST_CMD_EXEC =>
        rin.inside_cmd <= false;
        rin.parser <= nsl_data.cbor.reset;
        if nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_TAG then
          tag            := nsl_data.cbor.arg_int(r.parser);
          rin.tag        <= tag;
          rin.inside_cmd <= true;
          rin.state      <=  ST_CMD_GET;
          if 0 <= tag and tag < 8 then
            -- SWD RW. tag indicates register
          elsif tag = 8 then
            -- SWD turnaround. next item is an int that indicates the number of
            -- cycles. sticky setting.
          elsif tag = 9 then
            -- bitbang. next item is a bstr with the data to bitbang
          elsif tag = 10 then
            -- wait for cycles. next item is a positive integer with the number
            -- of cycles to wait for
          else
            nsl_simulation.logging.log_warning("Unhandled CBOR tag " & integer'image(tag) &" received, draining frame");
            rin.last  <= false;
            rin.state <= ST_ERROR_DRAIN;
          end if;
        elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_POSITIVE then
          if not r.inside_cmd then
            -- SWD_RUN
            rin.inside_cmd <= false;
            rin.cycle_count <= nsl_data.cbor.arg_int(r.parser) - 1;
            if not r.cmd_cancelled then
              rin.state <= ST_RUN;
            else
              rin.state <= ST_CMD_END;
            end if;
          else --inside a command
            if 0 <= r.tag and r.tag < 8 then
              -- it's a read. the register to read is indicated by the tag and
              -- the number indicates the count of words to read
              -- nsl_simulation.logging.log_info("Received command to SWD_READ, going to ST_CMD_SHIFT via ST_RSP_READ_HDR_PREP/PUT ");
              rin.is_read <= true;
              if r.tag < 4 then
                rin.cmd <= swd_cmd(reg => r.tag, ap => false, read => true);
              else
                rin.cmd <= swd_cmd(reg => r.tag - 4, ap => true, read => true);
              end if;
              rin.inside_cmd <= false;

              rin.par_in <= '0';
              rin.par_out <= '0';
              rin.word_count <= nsl_data.cbor.arg_int(r.parser);
              rin.word_total <= nsl_data.cbor.arg_int(r.parser);

              rin.cycle_count <= 7;
              if not r.cmd_cancelled then
                rin.state <= ST_RSP_READ_HDR_PREP;
              else
                rin.state <= ST_CMD_END;
              end if;
              
            elsif r.tag = 8 then
              rin.turnaround <= nsl_data.cbor.arg_int(r.parser)-1;
              rin.inside_cmd <= false;

              rin.state <= ST_CMD_END;
            elsif r.tag = 10 then
              rin.wait_cycles <= nsl_data.cbor.arg_int(r.parser)-1;
              rin.inside_cmd  <= false;

              rin.state <= ST_CMD_END;
            else
              nsl_simulation.logging.log_warning("Unhandled tag contect for positive number received, draining frame");
              rin.last  <= false;
              rin.state <= ST_ERROR_DRAIN;
            end if;
          end if;
        elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_BSTR then
          if r.inside_cmd then
            if 0 <= r.tag and r.tag < 8 then
              rin.is_read <= false;
              if r.tag < 4 then
                rin.cmd <= swd_cmd(reg => r.tag, ap => false, read => false);
              else
                rin.cmd <= swd_cmd(reg => r.tag - 4, ap => true, read => false);
              end if;
              
              rin.word_count <= nsl_data.cbor.arg_int(r.parser)/4;
              rin.word_total <= nsl_data.cbor.arg_int(r.parser)/4;
              
              rin.par_in <= '0';
              rin.par_out <= '0';
              rin.cycle <= 3;
              rin.cycle_count <= 7;
              if not r.cmd_cancelled then
                rin.state <= ST_CMD_SHIFT;
              else
                rin.state <= ST_CMD_CANCELLED; -- Need to consume the bitstream!
              end if;
            elsif r.tag = 9 then -- bitbang operation
              rin.inside_cmd <= false;
              rin.is_bitbang <= true;
              rin.word_count <= nsl_data.cbor.arg_int(r.parser) - 1;
              rin.cycle_count <= 7;
              rin.cycle      <= 3;
              if not r.cmd_cancelled then
                rin.state <= ST_DATA_GET;
              else
                rin.state <= ST_CMD_END;
              end if;
            else
              nsl_simulation.logging.log_warning("Unhandled tag context for bytestring, draining frame");
              rin.last  <= false;
              rin.state <= ST_ERROR_DRAIN;
            end if;
          else
            nsl_simulation.logging.log_error("Received bytestring outside of tag, register undefined. Draining frame");
            rin.last  <= false;
            rin.state <= ST_ERROR_DRAIN;
          end if;
        elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_TRUE then -- JTAG-to-SWD
          rin.inside_cmd <= false;
          rin.data(31 downto 16) <= (others => '-');
          rin.data(15 downto 0)  <= x"E79E";
          rin.word_count  <= 0;
          rin.cycle_count <= 15;
          if r.cmd_cancelled then
            rin.state <= ST_CMD_END;
          else
            rin.state <= ST_BITBANG;
          end if;
        elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_BREAK then
          if r.indefinite then
            rin.state <= ST_RSP_BREAK_PREP;
          else 
            nsl_simulation.logging.log_warning("Found break code inside definite lenght array. Malformed command, draining frame");
            rin.last  <= false;
            rin.state <= ST_ERROR_DRAIN;
          end if;
        else
          nsl_simulation.logging.log_error("Received non-compliant command");
          rin.last  <= false;
          rin.state <= ST_ERROR_DRAIN;
        end if;
      
      when ST_CMD_END =>
        if not r.indefinite and r.command_count = 0 then
          rin.cmd_cancelled <= false;
          rin.state <= ST_RSP_BREAK_PREP;
        else
          rin.state <= ST_CMD_GET;
        end if;
        rin.tag        <= 0;
        rin.parser     <= nsl_data.cbor.reset;
        rin.is_bitbang <= false;
        
      when ST_CMD_SHIFT =>
        if swclk_falling then
          rin.swd.dio.v <= r.cmd(0);
          rin.swd.dio.output <= '1';
        elsif swclk_rising then
          rin.cmd <= r.cmd(0) & r.cmd(7 downto 1); -- Rotate, instead of just shift
                                                   -- out, to preserve cmd for multi-word
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.state <= ST_CMD_TURNAROUND;
            rin.cycle_count <= r.turnaround;
          end if;
        end if;

      when ST_CMD_TURNAROUND =>
        if swclk_falling then
          rin.swd.dio.output <= '0';
          rin.swd.dio.v <= '-';
        elsif swclk_rising then
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.state <= ST_ACK_SHIFT;
            rin.cycle_count <= 2;
          end if;
        end if;

      when ST_ACK_SHIFT =>
        if swclk_falling then
          rin.swd.dio.output <= '0';
          rin.swd.dio.v <= '-';
        elsif swclk_rising then
          rin.ack <= to_x01(swd_i.dio) & r.ack(2 downto 1);
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            if (to_x01(swd_i.dio) & r.ack(2 downto 1)) = err_ok_c then
              if r.is_read then
                rin.cycle_count <= 31;
                rin.state <= ST_RSP_BSTR_HDR_PREP;
              else
                rin.cycle_count <= r.turnaround;
                rin.state <= ST_ACK_TURNAROUND;
              end if;
            else
              if r.is_read then
                rin.cmd_cancelled <= true;
                rin.state <= ST_RSP_READ_STATUS_PREP;
              else
                rin.cmd_cancelled <= true;
                rin.state <= ST_RSP_WRITE_STATUS_PREP;
              end if;
            end if;
          end if;
        end if;

      when ST_ACK_TURNAROUND =>
        if swclk_falling then
          rin.swd.dio.output <= '0';
          rin.swd.dio.v <= '-';
        elsif swclk_rising then
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.cycle_count <= 31;
            rin.state <= ST_DATA_GET;
          end if;
        end if;

      when ST_DATA_GET =>
        if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
          if r.is_bitbang then
            rin.data <= r.data(23 downto 0) & cmd_i.data(0);
            rin.state <= ST_BITBANG;
          else
            rin.data <= cmd_i.data(0) & r.data(31 downto 8);
            if r.cycle = 0 then
              rin.cycle <= 3;
              rin.word_count <= r.word_count - 1;
              rin.state <= ST_DATA_SHIFT_OUT;
            else
              rin.cycle <= r.cycle - 1;
            end if;
          end if;
        end if;
        
      when ST_DATA_SHIFT_OUT =>
        if swclk_falling then
          rin.swd.dio.output <= '1';
          rin.swd.dio.v <= r.data(0);
          rin.par_out <= r.par_out xor r.data(0);
        elsif swclk_rising then
          rin.data <= '-' & r.data(31 downto 1);
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.state <= ST_PARITY_SHIFT_OUT;
          end if;
        end if;

      when ST_PARITY_SHIFT_OUT =>
        if swclk_falling then
          rin.swd.dio.output <= '1';
          rin.swd.dio.v <= r.par_out;
        elsif swclk_rising then
          if r.word_count = 0 then
            rin.state <= ST_RSP_WRITE_STATUS_PREP;
            rin.cycle_count <= r.wait_cycles;
          else
              -- Multi-word write: do turnaround before next command
              rin.cycle_count <= r.turnaround;
              rin.par_out <= '0';  -- Reset parity for next word
              rin.state <= ST_DATA_TURNAROUND;
          end if;
        end if;

      when ST_DATA_SHIFT_IN =>
        if swclk_falling then
          rin.swd.dio.output <= '0';
          rin.swd.dio.v <= '-';
        elsif swclk_rising then
          rin.data <= to_x01(swd_i.dio) & r.data(31 downto 1);
          rin.par_in <= r.par_in xor to_x01(swd_i.dio);
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.state <= ST_PARITY_SHIFT_IN;
          end if;
        end if;

      when ST_PARITY_SHIFT_IN =>
        if swclk_falling then
          rin.swd.dio.output <= '0';
          rin.swd.dio.v <= '-';
        elsif swclk_rising then
          rin.par_in <= r.par_in xor to_x01(swd_i.dio);
          rin.state <= ST_DATA_PREP;
          rin.cycle_count <= r.turnaround;
        end if;

      when ST_DATA_TURNAROUND =>
        if swclk_falling then
          rin.swd.dio.output <= '0';
          rin.swd.dio.v <= '-';
        elsif swclk_rising then
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            if r.word_count /= 0 then
              -- Multi-word read/write: send next command
              rin.cycle_count <= 7;
              rin.state <= ST_CMD_SHIFT;
            else
              rin.state <= ST_RUN;
              rin.cycle_count <= r.wait_cycles;
            end if;
          end if;
        end if;

      when ST_RUN =>
        if swclk_falling then
          rin.swd.dio.output <= '1';
          rin.swd.dio.v <= r.run_val;
        elsif swclk_rising then
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            rin.state <= ST_CMD_END;
          end if;
        end if;
        
      when ST_BITBANG =>
        if swclk_falling then
          rin.swd.dio.output <= '1';
          rin.swd.dio.v <= r.data(0);
        elsif swclk_rising then
          rin.data <= '-' & r.data(31 downto 1);          
          if r.cycle_count /= 0 then
            rin.cycle_count <= r.cycle_count - 1;
          else
            if r.word_count = 0 then
              rin.state <= ST_CMD_END; -- TODO go to DATA_PUT??
            else
              rin.word_count <= r.word_count - 1;
              rin.cycle_count <= 7;
              rin.state <= ST_DATA_GET;
            end if;
          end if;
        end if;

      when ST_DATA_PREP =>
        rin.state <= ST_DATA_PUT;
        if r.par_in = '1' then -- parity bad
          rin.cmd_cancelled <= true;
          rin.state <= ST_RSP_READ_STATUS_PREP;
        else
          rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.bytestream.from_suv(r.data));
        end if;
        
      when ST_DATA_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          if nsl_amba.axi4_stream.is_last(buffer_cfg_c, r.encoded) then
            rin.word_count <= r.word_count - 1;  -- Decrement word count
            if r.word_count = 1 then  -- This was the last word
              rin.state <= ST_RSP_READ_STATUS_PREP;
            else  -- More words to read
              rin.par_in <= '0';  -- Reset parity for next word
              rin.cycle_count <= r.turnaround;
              rin.state <= ST_DATA_TURNAROUND;
            end if;
          end if;
          rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
        end if;

      when ST_RSP_ARRAY_HDR_PREP =>
        rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_array_hdr(length => -1));
        rin.state <= ST_RSP_ARRAY_HDR_PUT;
        rin.last  <= false;
          
      when ST_RSP_ARRAY_HDR_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          if nsl_amba.axi4_stream.is_last(buffer_cfg_c, r.encoded) then
            rin.state <= ST_CMD_GET;
          end if;
          rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
        end if;

      when ST_RSP_READ_HDR_PREP =>
        rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, byte_string'(nsl_data.cbor.cbor_array_hdr(3)) & byte_string'(nsl_data.cbor.cbor_bstr_hdr));
        -- array header for 3 items
        -- indefinite length bytestream header
        rin.state <= ST_RSP_READ_HDR_PUT;

      when ST_RSP_READ_HDR_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          if nsl_amba.axi4_stream.is_last(buffer_cfg_c, r.encoded) then
            rin.state <= ST_CMD_SHIFT;
          end if;
          rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
        end if;

      when ST_RSP_WRITE_STATUS_PREP =>
        status(3) := r.par_in;
        status(2 downto 0) := r.ack;
        rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c,
            nsl_data.cbor.cbor_array(
              nsl_data.cbor.cbor_positive(to_unsigned(r.word_total - r.word_count, 5)),
              nsl_data.cbor.cbor_positive(unsigned(status))
              ));
        rin.state <= ST_RSP_WRITE_STATUS_PUT;

      when ST_RSP_WRITE_STATUS_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          if nsl_amba.axi4_stream.is_last(buffer_cfg_c, r.encoded) then
            if r.cmd_cancelled then
              rin.state <= ST_CMD_CANCELLED;
            else
              rin.state <= ST_RUN;
            end if;
          end if;
          rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
        end if;
    
      when ST_RSP_READ_STATUS_PREP =>
        if is_x(r.par_in) then -- TODO remove? handles problems in sim
          status(3) := '0';
        else
          status(3) := r.par_in;
        end if;
        status(2 downto 0) := r.ack;
        rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c,
          (nsl_data.cbor.cbor_break & nsl_data.cbor.cbor_positive(to_unsigned(r.word_total - r.word_count, 5))) 
          & nsl_data.cbor.cbor_positive(unsigned(status)));
        rin.state <= ST_RSP_READ_STATUS_PUT;
      
      when ST_RSP_READ_STATUS_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          if nsl_amba.axi4_stream.is_last(buffer_cfg_c, r.encoded) then
            if r.cmd_cancelled then
              rin.state <= ST_CMD_END;
            else
              rin.state <= ST_RUN;
            end if;
          end if;
          rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
        end if;

      when ST_RSP_BSTR_HDR_PREP =>
        rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_bstr_hdr(length => to_unsigned(4, 3)));
        rin.state <= ST_RSP_BSTR_HDR_PUT;

      when ST_RSP_BSTR_HDR_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          if nsl_amba.axi4_stream.is_last(buffer_cfg_c, r.encoded) then
            rin.state <= ST_DATA_SHIFT_IN;
          end if;
          rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
        end if;

      when ST_RSP_BSTR_BREAK_PREP =>
        rin.data(7 downto 0) <= nsl_data.cbor.cbor_break(0);
        rin.last  <= true;
        rin.state <= ST_RSP_BSTR_BREAK_PUT;
    
      when ST_RSP_BSTR_BREAK_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          rin.state <= ST_CMD_END;
        end if;
          
      when ST_RSP_BREAK_PREP =>
        rin.data(7 downto 0) <= nsl_data.cbor.cbor_break(0);
        rin.last  <= true;
        rin.state <= ST_RSP_BREAK_PUT;
    
      when ST_RSP_BREAK_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          rin.state <= ST_ARRAY_GET;
        end if;

      when ST_CMD_CANCELLED =>
        if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
          nsl_simulation.logging.log_info("[Cancelled command] Discarding data to write");
          if r.cycle = 0 then
            rin.cycle <= 3;
            if r.word_count = 0 then
              rin.state <= ST_CMD_END;
            else
              rin.word_count <= r.word_count - 1;
            end if;
          else
            rin.cycle <= r.cycle - 1;
          end if;
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
      
      when others =>
        null;

    end case;
  end process;

  moore: process(r)
  begin
    cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, false);
    rsp_o <= nsl_amba.axi4_stream.transfer_defaults(cfg => stream_config_c);

    swd_o <= r.swd;

    case r.state is
      when ST_RESET | ST_ARRAY_ENTER | ST_CMD_EXEC | ST_CMD_END =>
        
      when ST_ARRAY_GET | ST_CMD_GET | ST_DATA_GET | ST_ERROR_DRAIN | ST_CMD_CANCELLED =>
        cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, true);
                
      when ST_CMD_SHIFT | ST_CMD_TURNAROUND | ST_ACK_SHIFT | ST_ACK_TURNAROUND | ST_DATA_SHIFT_OUT | ST_PARITY_SHIFT_OUT | ST_DATA_SHIFT_IN | ST_PARITY_SHIFT_IN | ST_DATA_TURNAROUND | ST_RUN | ST_BITBANG =>
        
      when ST_RSP_ARRAY_HDR_PREP | ST_RSP_READ_HDR_PREP | ST_RSP_BSTR_HDR_PREP | ST_RSP_BREAK_PREP | ST_RSP_BSTR_BREAK_PREP | ST_RSP_READ_STATUS_PREP | ST_RSP_WRITE_STATUS_PREP | ST_DATA_PREP =>
        
      when ST_RSP_ARRAY_HDR_PUT | ST_RSP_READ_HDR_PUT | ST_RSP_BSTR_HDR_PUT | ST_DATA_PUT | ST_RSP_READ_STATUS_PUT | ST_RSP_WRITE_STATUS_PUT =>
        rsp_o <= nsl_amba.axi4_stream.next_beat(cfg => buffer_cfg_c, b => r.encoded, last => r.last);
        
      when ST_RSP_BREAK_PUT | ST_RSP_BSTR_BREAK_PUT =>
        rsp_o <= nsl_amba.axi4_stream.transfer(cfg => stream_config_c, bytes => nsl_data.bytestream.from_suv(r.data(7 downto 0)), last => r.last);

    end case;
  end process;
  
end architecture;
