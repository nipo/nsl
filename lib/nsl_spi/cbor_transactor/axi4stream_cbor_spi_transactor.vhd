library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_io, nsl_logic, nsl_data, nsl_simulation, nsl_amba;
use nsl_data.cbor.all;

entity axi4stream_cbor_spi_transactor is
  generic(
    clock_i_hz_c  : natural;
    stream_config_c   : nsl_amba.axi4_stream.config_t;
    slave_count_c : natural range 1 to 7 := 1;
    width_c       : natural := 7
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    tick_i    : in std_ulogic;

    sck_o     : out std_ulogic;
    cs_n_o    : out nsl_io.io.opendrain_vector(0 to slave_count_c-1);
    mosi_o    : out nsl_io.io.tristated;
    miso_i    : in  std_ulogic;

    cmd_i     : in  nsl_amba.axi4_stream.master_t;
    cmd_o     : out nsl_amba.axi4_stream.slave_t;
    rsp_o     : out nsl_amba.axi4_stream.master_t;
    rsp_i     : in nsl_amba.axi4_stream.slave_t
    );
end entity;

architecture rtl of axi4stream_cbor_spi_transactor is

  constant cbr_hdr_max_size_c : natural := 3;
  constant buffer_cfg_c       : nsl_amba.axi4_stream.buffer_config_t := nsl_amba.axi4_stream.buffer_config(stream_config_c, cbr_hdr_max_size_c);

  type state_t is (
    ST_RESET,

    ST_ARRAY_GET,
    ST_ARRAY_ENTER,

    ST_CMD_GET,
    ST_CMD_EXEC,
    ST_CMD_END,

    ST_CMD_GET_CS,
    ST_CMD_GET_MODE,
    
    ST_DATA_GET,
    ST_SELECTED_PRE,
    ST_SELECTED_POST,
    ST_SHIFT_FIRST_HALF,
    ST_SHIFT_SECOND_HALF,
    ST_DATA_PUT,

    ST_RSP_ARRAY_HDR_PREP,
    ST_RSP_ARRAY_HDR_PUT, 
    ST_RSP_BSTR_HDR_PREP,
    ST_RSP_BSTR_HDR_PUT,
    ST_RSP_BREAK_PREP,
    ST_RSP_BREAK_PUT,
    
    ST_ERROR_DRAIN
    );
  
  
 type regs_t is record
    state               : state_t;

    shreg               : std_ulogic_vector(7 downto 0);
    word_count          : natural range 0 to 4095;
    selected            : natural range 0 to 7;
    bit_count           : natural range 0 to 7;
    
    mosi                : std_ulogic;
    cpol                : std_ulogic;
    cpha                : std_ulogic;
    has_miso            : boolean;
    has_mosi            : boolean;
    minus               : natural range 0 to 7;         -- do not shift the last N bits of the operation
                                                        -- r.minus holds the number of bits that must be shifted on the last word

    parser              : nsl_data.cbor.parser_t;
    tag                 : natural range 0 to 11; 
    command_count       : natural range 0 to 1023;
    indefinite          : boolean;
    inside_cmd          : boolean;
    
    encoded             : nsl_amba.axi4_stream.buffer_t;
    last                : boolean;
  end record;

  signal r, rin: regs_t;

  constant c_print_logs : boolean := False;
  
  function state_to_string(s : state_t) return string is
  begin
    case s is
      when ST_RESET                => return "ST_RESET";
        when ST_ARRAY_GET          => return "ST_ARRAY_GET";
        when ST_ARRAY_ENTER        => return "ST_ARRAY_ENTER";
        when ST_CMD_GET            => return "ST_CMD_GET";
        when ST_CMD_EXEC           => return "ST_CMD_EXEC";
        when ST_CMD_END            => return "ST_CMD_END";
        when ST_CMD_GET_CS         => return "ST_CMD_GET_CS";
        when ST_CMD_GET_MODE       => return "ST_CMD_GET_MODE";
        when ST_DATA_GET           => return "ST_DATA_GET";
        when ST_SELECTED_PRE       => return "ST_SELECTED_PRE";
        when ST_SELECTED_POST      => return "ST_SELECTED_POST";
        when ST_SHIFT_FIRST_HALF   => return "ST_SHIFT_FIRST_HALF";
        when ST_SHIFT_SECOND_HALF  => return "ST_SHIFT_SECOND_HALF";
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
      if rin.state = r.state then
      else
        log_state_change(r => r, rin => rin);
      end if;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, cmd_i, rsp_i, miso_i, tick_i)
    variable cbr_encoded : nsl_data.bytestream.byte_stream;
    variable tag         : natural range 0 to 11;
    variable mode        : std_ulogic_vector(1 downto 0);
  begin
    rin <= r;
    
    case r.state is
      when ST_RESET =>
        rin.state         <= ST_ARRAY_GET;
        rin.selected      <= slave_count_c;
        rin.cpol          <= '0';
        rin.cpha          <= '0';
        rin.mosi          <= '0';
        rin.has_mosi      <= true;
        rin.has_miso      <= true;
        
        rin.shreg         <= (others => '-');
        
        rin.minus         <= 0;
        rin.tag           <= 0;
        rin.parser        <= nsl_data.cbor.reset;
        rin.indefinite    <= false;
        rin.inside_cmd    <= false;

        rin.word_count    <= 0;
        rin.command_count <= 0;
        rin.encoded       <= nsl_amba.axi4_stream.reset(buffer_cfg_c);        
        rin.last          <= false;

      when ST_ARRAY_GET =>
        if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
          nsl_simulation.logging.log_info("In parsing, ST_ARRAY_GET a byte");
          rin.parser <= nsl_data.cbor.feed(r.parser, cmd_i.data(0));
          if nsl_data.cbor.is_last( r.parser, cmd_i.data(0) ) then
            rin.state <= ST_ARRAY_ENTER;
          end if;
        end if;

      when ST_ARRAY_ENTER =>
        if nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_ARRAY then
          if not r.parser.indefinite then
            -- nsl_simulation.logging.log_info("r.command_count set to " & nsl_data.text.to_string(nsl_data.cbor.arg_int(r.parser)));
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
            if nsl_data.cbor.is_last( r.parser, cmd_i.data(0) ) then
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
          if tag > 0 and tag < 8 then
            -- nsl_simulation.logging.log_info("minus set to " & nsl_data.text.to_string(8 - tag));
            rin.minus <= 8 - tag;
          elsif tag = 8 then
            rin.has_mosi <= false;
          elsif tag = 9 then
            rin.has_miso <= false;
          elsif tag = 10 then
            rin.has_mosi <= false;
            rin.has_miso <= false;
          else
            nsl_simulation.logging.log_warning("Unhandled CBOR tag, draining frame");
            rin.last  <= false;
            rin.state <= ST_ERROR_DRAIN;            
          end if;
          -- nsl_simulation.logging.log(level => nsl_simulation.logging.LOG_LEVEL_INFO, color => nsl_simulation.logging.LOG_COLOR_BLUE, message => "Found KIND_TAG with tag =" & nsl_data.text.to_string(tag));

        elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_POSITIVE then
          -- nsl_simulation.logging.log(level => nsl_simulation.logging.LOG_LEVEL_INFO, color => nsl_simulation.logging.LOG_COLOR_BLUE, message => "Found KIND_POSITIVE with r.tag =" & nsl_data.text.to_string(r.tag));
          if r.tag = 8 then -- SHIFT_IN (no MOSI)
            rin.shreg <= (others => '0');
            rin.mosi <= '0';
            -- rin.word_count <= nsl_data.cbor.arg_int(r.parser)/8 - 1;
            -- rin.state      <= ST_RSP_BSTR_HDR_PREP;
            -- if nsl_data.cbor.arg_int(r.parser)/8 = 0 and r.minus /= 0 then
            --   rin.bit_count <= r.minus - 1;
            -- else 
            --   rin.bit_count <= width_c;
            -- end if;
            rin.word_count  <= (nsl_data.cbor.arg_int(r.parser)+7)/8 - 1;
            if nsl_data.cbor.arg_int(r.parser) mod 8 = 0 then
              rin.bit_count <= width_c;
            else
              rin.bit_count <= nsl_data.cbor.arg_int(r.parser) mod 8 - 1;
              rin.minus <= nsl_data.cbor.arg_int(r.parser) mod 8 - 1;
            end if;
            rin.state      <= ST_RSP_BSTR_HDR_PREP;
          elsif r.tag = 10 then -- 'pause'
            rin.shreg <= (others => '0');
            rin.mosi <= '0';
            if nsl_data.cbor.arg_int(r.parser) < 8 then
              rin.bit_count <=  nsl_data.cbor.arg_int(r.parser) - 1;
              rin.word_count <= 0;
            else
              rin.bit_count <=  nsl_data.cbor.arg_int(r.parser) mod 8;
              rin.word_count <= nsl_data.cbor.arg_int(r.parser)/8 - 1;
            end if;
            rin.state <= ST_SHIFT_FIRST_HALF;
          else
            nsl_simulation.logging.log_warning("Unhandled tag context for positive value, draining frame");
            rin.last  <= false;
            rin.state <= ST_ERROR_DRAIN;
          end if;

        elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_NULL then
          rin.selected <= slave_count_c;
          rin.state <= ST_CMD_END;

        elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_ARRAY then
          rin.state <= ST_CMD_GET_CS;
          
        elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_BSTR then
          rin.word_count <= nsl_data.cbor.arg_int(r.parser) - 1;
          if r.has_miso then                                                          
            rin.state <= ST_RSP_BSTR_HDR_PREP;                                        
          else                                                                        
            rin.state <= ST_DATA_GET;                                                 
          end if;                       
          
          rin.has_mosi   <= true;

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

      when ST_CMD_END =>
        if not r.indefinite and r.command_count = 0 then
          rin.state <= ST_RSP_BREAK_PREP;
        else
          rin.state <= ST_CMD_GET;
        end if;
        rin.tag      <= 0;
        rin.minus    <= 0;
        rin.has_mosi <= true;
        rin.has_miso <= true;
        rin.shreg    <= (others => '-');
        rin.parser   <= nsl_data.cbor.reset;

      when ST_CMD_GET_CS =>
        if not nsl_data.cbor.is_done(r.parser) then
          if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
            rin.parser <= nsl_data.cbor.feed(r.parser, cmd_i.data(0));
          end if;
        else
          rin.selected <= nsl_data.cbor.arg_int(r.parser);
          rin.parser   <= nsl_data.cbor.reset;
          rin.state    <= ST_CMD_GET_MODE;
        end if;
        
      when ST_CMD_GET_MODE =>
        if not nsl_data.cbor.is_done(r.parser) then
          if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
            rin.parser <= nsl_data.cbor.feed(r.parser, cmd_i.data(0));
          end if;
        else
          mode := std_ulogic_vector(nsl_data.cbor.arg(r.parser, 2));
          -- nsl_simulation.logging.log_info("mode is "& nsl_data.text.to_string(mode));
          rin.cpha     <= mode(0);
          rin.cpol     <= mode(1);
          rin.parser   <= nsl_data.cbor.reset;
          rin.state    <= ST_SELECTED_PRE;
        end if;   

      when ST_DATA_GET =>
        if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
          rin.mosi <= cmd_i.data(0)(width_c);
          rin.shreg <= cmd_i.data(0);
          rin.state <= ST_SHIFT_FIRST_HALF;
          -- prepare SHIFT_OUT or SHIFT_IO
          if r.word_count = 0 and r.minus /= 0 then
            rin.bit_count <= r.minus - 1;
          else
            rin.bit_count <= width_c;
          end if;
        end if;
        
      when ST_SELECTED_PRE =>
        if tick_i = '1' then
          rin.state <= ST_SELECTED_POST;
          rin.mosi <= '0';
        end if;
        
      when ST_SELECTED_POST =>
        if tick_i = '1' then
          rin.state <= ST_CMD_END;
        end if;
        
      when ST_SHIFT_FIRST_HALF =>
        if tick_i = '1' then
          rin.state <= ST_SHIFT_SECOND_HALF;
          rin.shreg <= r.shreg(width_c-1 downto 0) & miso_i;
        end if;

      when ST_SHIFT_SECOND_HALF =>
        if tick_i = '1' then
          if r.bit_count /= 0 then
            rin.bit_count <= r.bit_count - 1;
          else
            rin.bit_count <= width_c;
          end if;

          if r.bit_count /= 0 then
            if r.has_mosi then
              rin.mosi <= r.shreg(width_c);
            else
              rin.mosi <= '0';
            end if;
            rin.state <= ST_SHIFT_FIRST_HALF;
          else
            if r.has_miso then
              rin.state <= ST_DATA_PUT;
            else
              if r.word_count /= 0 then
                rin.word_count <= r.word_count - 1;
                rin.bit_count <= width_c;
                if r.word_count = 1 and r.minus /= 0 then
                  rin.bit_count <= r.minus - 1;
                end if;
                if r.has_mosi then
                  rin.state <= ST_DATA_GET;
                else
                  rin.state <= ST_SHIFT_FIRST_HALF;
                end if;
              else
                rin.state <= ST_CMD_END;
              end if;
            end if;
          end if;
         end if;

      when ST_DATA_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          if r.word_count /= 0 then
            rin.word_count <= r.word_count - 1;
            rin.bit_count <= width_c;
            if r.word_count = 1 and r.minus /= 0 then
              rin.bit_count <= r.minus - 1;
            end if;
            if r.has_miso and not r.has_mosi then
              rin.shreg <= (others => '0');
              rin.state <= ST_SHIFT_FIRST_HALF;
            elsif r.has_mosi then -- SPI_CMD_SHIFT_IO
              rin.state <= ST_DATA_GET;
            end if;
          else
            rin.state <= ST_CMD_END;
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
        rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_bstr_hdr(length => to_unsigned(r.word_count+1, 12) ) );
        rin.state <= ST_RSP_BSTR_HDR_PUT;
        rin.last  <= false;

      when ST_RSP_BSTR_HDR_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          if nsl_amba.axi4_stream.is_last(buffer_cfg_c, r.encoded) then
            if r.has_mosi then
              rin.state <= ST_DATA_GET;
            else
              rin.state <= ST_SHIFT_FIRST_HALF;
            end if;
          end if;
          rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
        end if;
          
      when ST_RSP_BREAK_PREP=>
        rin.shreg  <= nsl_data.cbor.cbor_break(0);
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

      when others =>
          null;
    end case;
  end process;

  moore: process(r)
    variable rsp_data : std_ulogic_vector(7 downto 0);
  begin
    cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, false);
    rsp_o <= nsl_amba.axi4_stream.transfer_defaults(stream_config_c);
    rsp_o.valid <= '0';
    rsp_o.last <= '-';
    rsp_o.data(0) <= (others => '-');

    for i in cs_n_o'range
    loop
      if r.selected = i then
        cs_n_o(i).drain_n <= '0';
      else
        cs_n_o(i).drain_n <= '1';
      end if;
    end loop;
    
    mosi_o <= nsl_io.io.to_tristated(r.mosi, r.selected < slave_count_c);
    sck_o <= r.cpol;

    case r.state is
      when ST_RESET | ST_SELECTED_PRE | ST_SELECTED_POST =>
        null;

      when ST_ARRAY_ENTER | ST_CMD_EXEC | ST_CMD_END =>
        null;

      when ST_SHIFT_FIRST_HALF =>
        if r.tag /= 10 then
          sck_o <= r.cpol xor r.cpha;
        end if;

      when ST_SHIFT_SECOND_HALF =>
        if r.tag /= 10 then
          sck_o <= r.cpol xnor r.cpha;
        end if;

      when ST_ARRAY_GET | ST_CMD_GET | ST_DATA_GET  | ST_ERROR_DRAIN =>
        cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, true);

      when ST_CMD_GET_MODE | ST_CMD_GET_CS =>
        if not nsl_data.cbor.is_done(r.parser) then
          cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, true);
        end if;

      when ST_DATA_PUT =>
        if r.has_miso then -- should never get here without r.has_miso being true..
          if r.minus = 0 then
            rsp_o <= nsl_amba.axi4_stream.transfer( cfg => stream_config_c, bytes => nsl_data.bytestream.from_suv(r.shreg), last => false);
          else
            -- report "in ST_DATA_PUT Word count is " & integer'image(r.word_count) & "; minus is " & integer'image(r.minus);
            if r.word_count = 0 and r.minus /= 0 then
              rsp_data := (others => '0');
              rsp_data(r.minus-1 downto 0) := r.shreg(r.minus-1 downto 0);
              -- report "r.shreg is " & nsl_data.text.to_string(r.shreg) & " r.shreg(r.minus-1 downto 0) "& nsl_data.text.to_string(r.shreg(r.minus-1 downto 0));
            else
              rsp_data := r.shreg;
            end if;
            rsp_o <= nsl_amba.axi4_stream.transfer( cfg => stream_config_c, bytes => nsl_data.bytestream.from_suv(rsp_data), last => false);
          end if;
        end if;
    
    when ST_RSP_BREAK_PUT =>
      rsp_o <= nsl_amba.axi4_stream.transfer( cfg => stream_config_c, bytes => nsl_data.bytestream.from_suv(r.shreg), last => r.last);

    when ST_RSP_ARRAY_HDR_PREP | ST_RSP_BSTR_HDR_PREP | ST_RSP_BREAK_PREP =>
    
    when ST_RSP_ARRAY_HDR_PUT | ST_RSP_BSTR_HDR_PUT =>
      rsp_o <= nsl_amba.axi4_stream.next_beat(cfg => buffer_cfg_c, b => r.encoded, last => r.last);

    end case;
  end process;
  
end architecture;
