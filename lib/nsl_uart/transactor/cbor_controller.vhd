library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;       

library nsl_uart, nsl_bnoc, nsl_amba, nsl_data, nsl_simulation, nsl_logic;
use nsl_data.cbor.all;

entity cbor_controller is
  generic(
    system_clock_c     : natural;
    axi_s_cfg_c        : nsl_amba.axi4_stream.config_t;
    stop_count_c       : natural range 1 to 2 := 1;
    parity_c           : nsl_uart.serdes.parity_t := nsl_uart.serdes.PARITY_NONE;
    handshake_active_c : std_ulogic := '0';
    divisor_c          : unsigned(31 downto 0);
    timeout_c          : unsigned(31 downto 0);
    bstr_max_size_c    : natural range 0 to 511
    );
  port (
    reset_n_i    : in std_ulogic;
    clock_i      : in std_ulogic;
    
    tx_o   : out std_ulogic;
    cts_i  : in std_ulogic := handshake_active_c;
    rx_i   : in  std_ulogic;
    rts_o  : out std_ulogic;

    cmd_i  : in  nsl_amba.axi4_stream.master_t;
    cmd_o  : out nsl_amba.axi4_stream.slave_t;
    rsp_i  : in  nsl_amba.axi4_stream.slave_t;
    rsp_o  : out nsl_amba.axi4_stream.master_t
    );
end entity;

architecture rtl of cbor_controller is

  constant OP_SUCCESS : std_ulogic_vector(7 downto 0) := X"F5";
  constant OP_FAILURE : std_ulogic_vector(7 downto 0) := X"F4";

  function max(a, b : natural) return natural is
  begin
    if a > b then return a; else return b; end if;
  end function;

  constant item_count_max_c : natural := max(bstr_max_size_c, 7);
  constant cbr_max_size_c : natural := 30; -- max payload is the response with
                                           -- the configuration map
  constant buffer_cfg_c   : nsl_amba.axi4_stream.buffer_config_t := nsl_amba.axi4_stream.buffer_config(axi_s_cfg_c, 30);

  constant FLOW_CTRL_STR_C : string := "flow-ctrl";
  constant PARITY_STR_C    : string := "parity";
  constant BAUD_RATE_STR_C : string := "baud-rate";
  constant NONE_STR_C      : string := "none";
  constant CTS_STR_C       : string := "cts";
  constant N_STR_C         : string := "n";
  constant E_STR_C         : string := "e";
  constant O_STR_C         : string := "o";
  
  constant DIV_300     : unsigned := to_unsigned(system_clock_c / 300,     20);
  constant DIV_1200    : unsigned := to_unsigned(system_clock_c / 1200,    20);
  constant DIV_2400    : unsigned := to_unsigned(system_clock_c / 2400,    20);
  constant DIV_4800    : unsigned := to_unsigned(system_clock_c / 4800,    20);
  constant DIV_9600    : unsigned := to_unsigned(system_clock_c / 9600,    20);
  constant DIV_19200   : unsigned := to_unsigned(system_clock_c / 19200,   20);
  constant DIV_38400   : unsigned := to_unsigned(system_clock_c / 38400,   20);
  constant DIV_57600   : unsigned := to_unsigned(system_clock_c / 57600,   20);
  constant DIV_115200  : unsigned := to_unsigned(system_clock_c / 115200,  20);
  constant DIV_230400  : unsigned := to_unsigned(system_clock_c / 230400,  20);
  constant DIV_460800  : unsigned := to_unsigned(system_clock_c / 460800,  20);
  constant DIV_921600  : unsigned := to_unsigned(system_clock_c / 921600,  20);
  constant DIV_1000000 : unsigned := to_unsigned(system_clock_c / 1000000, 20);
  constant DIV_2000000 : unsigned := to_unsigned(system_clock_c / 2000000, 20);
  constant DIV_3000000 : unsigned := to_unsigned(system_clock_c / 3000000, 20);

  -- Lookup table function to convert baud rate to divisor without runtime division
  -- Supports common baud rates; unknown rates default to 115200
  function baud_to_divisor(baud_rate : unsigned(31 downto 0)) return unsigned is
  begin
    case to_integer(baud_rate) is
      when 300     => return DIV_300;
      when 1200    => return DIV_1200;
      when 2400    => return DIV_2400;
      when 4800    => return DIV_4800;
      when 9600    => return DIV_9600;
      when 19200   => return DIV_19200;
      when 38400   => return DIV_38400;
      when 57600   => return DIV_57600;
      when 115200  => return DIV_115200;
      when 230400  => return DIV_230400;
      when 460800  => return DIV_460800;
      when 921600  => return DIV_921600;
      when 1000000 => return DIV_1000000;
      when 2000000 => return DIV_2000000;
      when 3000000 => return DIV_3000000;
      when others  => return DIV_115200;
    end case;
  end function;

  -- Lookup table function to convert divisor to baud rate
  -- Supports common baud rates; unknown divisors default to 115200
  function divisor_to_baud(divisor : unsigned(19 downto 0)) return unsigned is
  begin
    if    divisor = DIV_300     then return to_unsigned(300,     32);
    elsif divisor = DIV_1200    then return to_unsigned(1200,    32);
    elsif divisor = DIV_2400    then return to_unsigned(2400,    32);
    elsif divisor = DIV_4800    then return to_unsigned(4800,    32);
    elsif divisor = DIV_9600    then return to_unsigned(9600,    32);
    elsif divisor = DIV_19200   then return to_unsigned(19200,   32);
    elsif divisor = DIV_38400   then return to_unsigned(38400,   32);
    elsif divisor = DIV_57600   then return to_unsigned(57600,   32);
    elsif divisor = DIV_115200  then return to_unsigned(115200,  32);
    elsif divisor = DIV_230400  then return to_unsigned(230400,  32);
    elsif divisor = DIV_460800  then return to_unsigned(460800,  32);
    elsif divisor = DIV_921600  then return to_unsigned(921600,  32);
    elsif divisor = DIV_1000000 then return to_unsigned(1000000, 32);
    elsif divisor = DIV_2000000 then return to_unsigned(2000000, 32);
    elsif divisor = DIV_3000000 then return to_unsigned(3000000, 32);
    else
      return to_unsigned(115200, 32);
    end if;
  end function;

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_CONFIG_ITEM_GET,
    ST_CONFIG_STR_GET,
    ST_CONFIG_STR_DRAIN,
    ST_MESSAGE_ROUTE,
    ST_RSP_BSTR_HDR_PREP,
    ST_RSP_BSTR_HDR_PUT,
    ST_RSP_DATA_PUT,
    ST_RSP_PUT,
    ST_RSP_CONFIG_PREP,
    ST_RSP_CONFIG_PUT,
    ST_ERROR_DRAIN
    );
  
  type map_parsing_state_t is (
    MAP_NONE,
    MAP_KEY,
    MAP_KEY_FC,   -- Parsing "flow-ctrl" key
    MAP_KEY_PAR,  -- Parsing "parity" key
    MAP_KEY_BR,   -- Parsing "baud-rate" key
    MAP_VAL_FC,   -- Parsing flow-ctrl value
    MAP_VAL_PAR,  -- Parsing parity value
    MAP_VAL_BR    -- Parsing baud-rate value
    );
  
  type regs_t is
  record
    state       : state_t;
    
    map_state   : map_parsing_state_t;
    parser      : nsl_data.cbor.parser_t;
    item_count  : natural range 0 to item_count_max_c;
    len         : natural range 0 to 15;   -- String length countdown

    parity      : nsl_uart.serdes.parity_t;
    hs          : std_ulogic;
    stop_count  : natural range 1 to 2;
    divisor     : unsigned(19 downto 0);

    count       : natural range 0 to bstr_max_size_c;
    flush_count : natural range 0 to bstr_max_size_c;
    bit_timer   : unsigned(19 downto 0);  -- Counts down one bit time (divisor clocks)
    timeout     : unsigned(15 downto 0);  -- Counts bit times until flush
    fifo        : nsl_data.bytestream.byte_string(0 to bstr_max_size_c - 1);
    
    encoded     : nsl_amba.axi4_stream.buffer_t;
    last        : boolean;
    rsp_success : boolean;
  end record;

  signal r, rin: regs_t;

  signal bnoc_tx_s, bnoc_rx_s: nsl_bnoc.pipe.pipe_bus_t;

  signal parity_s, stop_count_s : unsigned(1 downto 0);
begin
  
  reg: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(cmd_i, r, bnoc_rx_s, bnoc_tx_s, rsp_i)
      variable cbr_encoded : nsl_data.bytestream.byte_stream;
      variable cbr_len : natural;
  begin
    rin <= r;

    rin.fifo <= nsl_data.fifo.fifo_shift_data(storage => r.fifo,
                                              fillness => r.count,
                                              min_fill => 0,
                                              valid => bnoc_rx_s.req.valid = '1', -- push
                                              data => bnoc_rx_s.req.data,
                                              ready => false -- no pop
                                              );
    rin.count <=  nsl_data.fifo.fifo_shift_fillness(storage => r.fifo,
                                                    fillness => r.count,
                                                    min_fill => 0,
                                                    valid => bnoc_rx_s.req.valid = '1', -- push
                                                    data => bnoc_rx_s.req.data,
                                                    ready => false -- no pop
                                                    );
    
    case r.state is
      when ST_RESET =>
        rin.state      <= ST_IDLE;
        rin.parser     <= nsl_data.cbor.reset;
        rin.parity     <= parity_c;
        rin.hs         <= handshake_active_c;
        rin.stop_count <= stop_count_c;
        rin.map_state  <= MAP_NONE;
        rin.divisor    <= resize(divisor_c, 20);
        rin.last       <= false;
        rin.len        <= 0;
        rin.count      <= 0;
        rin.bit_timer  <= resize(divisor_c, 20);
        rin.timeout    <= resize(timeout_c, 16);
 
      when ST_IDLE =>
        -- Prescaler-based timeout: bit_timer counts clocks, timeout counts bit times
        if r.count > 0 then
          if r.bit_timer > 0 then
            rin.bit_timer <= r.bit_timer - 1;
          else
            -- One bit time elapsed, reload and decrement timeout
            rin.bit_timer <= r.divisor;
            if r.timeout > 0 then
              rin.timeout <= r.timeout - 1;
            end if;
          end if;
        end if;

        if (r.count > 0 and r.timeout = 0) or not nsl_data.fifo.fifo_can_push(storage => r.fifo, fillness => r.count) then
          -- Send loopback data when timeout expires or FIFO is full
          rin.flush_count <= r.count;
          rin.state       <= ST_RSP_BSTR_HDR_PREP;
          rin.bit_timer   <= r.divisor;
          rin.timeout     <= resize(timeout_c, 16);
        else
          if not nsl_data.cbor.is_done(r.parser) then
            if cmd_i.valid = '1' then
              rin.parser <= nsl_data.cbor.feed(r.parser, cmd_i.data(0));
            end if;
          else
            if nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_MAP then
              rin.item_count <= nsl_data.cbor.arg_int(r.parser);
              rin.map_state <= MAP_KEY;
              rin.state <= ST_CONFIG_ITEM_GET;
            elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_BSTR then
              rin.item_count <= nsl_data.cbor.arg_int(r.parser);
              rin.state <= ST_MESSAGE_ROUTE;
            elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_NULL then
              rin.item_count <= 0;
              rin.state <= ST_RSP_CONFIG_PREP;
            else
              -- Unknown CBOR type - drain input and send failure response
              rin.state <= ST_ERROR_DRAIN;
            end if;
            rin.parser <= nsl_data.cbor.reset;
          end if;
        end if;

      when ST_CONFIG_ITEM_GET =>
        if not nsl_data.cbor.is_done(r.parser) then
          if nsl_amba.axi4_stream.is_valid(axi_s_cfg_c, cmd_i) then
            rin.parser <= nsl_data.cbor.feed(r.parser, cmd_i.data(0));
          end if;
        else
          if nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_TSTR then
            rin.len <= nsl_data.cbor.arg_int(r.parser);
            rin.state <= ST_CONFIG_STR_GET;
          elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_POSITIVE then
            if r.map_state = MAP_VAL_BR then
              rin.divisor <= baud_to_divisor(nsl_data.cbor.arg(r.parser, 32));
              if r.item_count = 0 then
                rin.map_state <= MAP_NONE;
                rin.state <= ST_RSP_PUT;
                rin.rsp_success <= true;
              else
                rin.state <= ST_CONFIG_ITEM_GET;
              end if;
            end if;
          end if;
          rin.parser <= nsl_data.cbor.reset;
        end if;

      when ST_CONFIG_STR_GET =>
        if cmd_i.valid = '1' then
          if r.map_state = MAP_KEY then
            if r.len = 9 and cmd_i.data(0) = x"66" then     -- 'f' = flow-ctrl
              rin.map_state <= MAP_KEY_FC;
            elsif r.len = 6 and cmd_i.data(0) = x"70" then  -- 'p' = parity
              rin.map_state <= MAP_KEY_PAR;
            elsif r.len = 9 and cmd_i.data(0) = x"62" then  -- 'b' = baud-rate
              rin.map_state <= MAP_KEY_BR;
            end if;

          elsif r.map_state = MAP_VAL_FC then
            if r.len = 4 and cmd_i.data(0) = x"6E" then     -- 'n' = none
              rin.hs <= '0';
            elsif r.len = 3 and cmd_i.data(0) = x"63" then  -- 'c' = cts
              rin.hs <= '1';
            elsif r.len = 3 and cmd_i.data(0) = x"78" then  -- 'x' = xon
              rin.hs <= '0';
            end if;

          elsif r.map_state = MAP_VAL_PAR then
            if cmd_i.data(0) = x"6E" then      -- 'n' = none
              rin.parity <= nsl_uart.serdes.PARITY_NONE;
            elsif cmd_i.data(0) = x"65" then   -- 'e' = even
              rin.parity <= nsl_uart.serdes.PARITY_EVEN;
            elsif cmd_i.data(0) = x"6F" then   -- 'o' = odd
              rin.parity <= nsl_uart.serdes.PARITY_ODD;
            end if;

          end if;

          rin.len <= r.len - 1;
          if r.len = 1 then
            -- Single char string, handle completion
            case r.map_state is
              when MAP_KEY | MAP_KEY_FC | MAP_KEY_PAR | MAP_KEY_BR =>
                -- Key parsed (shouldn't happen for single char, but handle it)
                rin.item_count <= r.item_count - 1;
                case r.map_state is
                  when MAP_KEY_FC => rin.map_state <= MAP_VAL_FC;
                  when MAP_KEY_PAR => rin.map_state <= MAP_VAL_PAR;
                  when MAP_KEY_BR => rin.map_state <= MAP_VAL_BR;
                  when others => null;
                end case;
                rin.state <= ST_CONFIG_ITEM_GET;
              when MAP_VAL_FC | MAP_VAL_PAR | MAP_VAL_BR =>
                -- Value parsed, back to key state
                rin.map_state <= MAP_KEY;
                if r.item_count = 0 then
                  rin.map_state <= MAP_NONE;
                  rin.state <= ST_RSP_PUT;
                  rin.rsp_success <= true;
                else
                  rin.state <= ST_CONFIG_ITEM_GET;
                end if;
              when others => null;
            end case;
          else
            -- More chars to drain
            rin.state <= ST_CONFIG_STR_DRAIN;
          end if;
        end if;

      when ST_CONFIG_STR_DRAIN =>
        -- Drain remaining characters of the string
        if cmd_i.valid = '1' then
          rin.len <= r.len - 1;
          if r.len = 1 then
            -- Done draining, handle completion
            case r.map_state is
              when MAP_KEY_FC | MAP_KEY_PAR | MAP_KEY_BR =>
                -- Key parsed, transition to value state and decrement item_count
                rin.item_count <= r.item_count - 1;
                case r.map_state is
                  when MAP_KEY_FC => rin.map_state <= MAP_VAL_FC;
                  when MAP_KEY_PAR => rin.map_state <= MAP_VAL_PAR;
                  when MAP_KEY_BR => rin.map_state <= MAP_VAL_BR;
                  when others => null;
                end case;
                rin.state <= ST_CONFIG_ITEM_GET;
              when MAP_VAL_FC | MAP_VAL_PAR | MAP_VAL_BR =>
                -- Value parsed, back to key state
                rin.map_state <= MAP_KEY;
                if r.item_count = 0 then
                  rin.map_state <= MAP_NONE;
                  rin.state <= ST_RSP_PUT;
                  rin.rsp_success <= true;
                else
                  rin.state <= ST_CONFIG_ITEM_GET;
                end if;
              when others => null;
            end case;
          end if;
        end if;

      when ST_RSP_CONFIG_PREP =>
        rin.item_count <= r.item_count + 1;
        rin.last <= false;
        case r.item_count is
          when 0 =>
            rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_map_hdr(length => to_unsigned(3, 2)));
          when 1 =>
            rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_tstr(FLOW_CTRL_STR_C));
          when 2 =>
            case r.hs is
              when '0' => rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_tstr(NONE_STR_C));
              when '1' => rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_tstr(CTS_STR_C));
              when others => null;
            end case;
          when 3 =>
            rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_tstr(PARITY_STR_C));
          when 4 =>
            case r.parity is
              when nsl_uart.serdes.PARITY_NONE => rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_tstr(N_STR_C));
              when nsl_uart.serdes.PARITY_EVEN => rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_tstr(E_STR_C));
              when nsl_uart.serdes.PARITY_ODD  => rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_tstr(O_STR_C));
              when others => null;
            end case;
          when 5 =>
            rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_tstr(BAUD_RATE_STR_C));
          when 6 =>
            rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_number(divisor_to_baud(r.divisor)));
            rin.last <= true;
          when others =>
            rin.item_count <= 0;
            rin.state <= ST_IDLE;
        end case;        
        if r.item_count < 7 then
          rin.state <= ST_RSP_CONFIG_PUT;
        end if;

      when ST_MESSAGE_ROUTE =>
        if nsl_amba.axi4_stream.is_valid(axi_s_cfg_c, cmd_i) and bnoc_tx_s.ack.ready = '1' then
          rin.item_count <= r.item_count - 1;
          if r.item_count = 1 then
            -- Message TX complete, send F5 confirmation immediately
            rin.state <= ST_RSP_PUT;
            rin.rsp_success <= true;
          end if;
        end if;
             
      when ST_RSP_BSTR_HDR_PREP =>
        rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_bstr_hdr(length => to_unsigned(r.flush_count, 12)) );  
        rin.state <= ST_RSP_BSTR_HDR_PUT;

      when ST_RSP_BSTR_HDR_PUT =>
        if nsl_amba.axi4_stream.is_ready(axi_s_cfg_c, rsp_i) then
          if nsl_amba.axi4_stream.is_last(buffer_cfg_c, r.encoded) then
            rin.state <= ST_RSP_DATA_PUT;
          end if;
          rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
        end if;
                  
      when ST_RSP_DATA_PUT =>
        if r.flush_count > 0 and nsl_amba.axi4_stream.is_ready(axi_s_cfg_c, rsp_i) then
          rin.flush_count <= r.flush_count - 1;
          rin.fifo <= nsl_data.fifo.fifo_shift_data(
            storage => r.fifo,
            fillness => r.count,
            valid => bnoc_rx_s.req.valid = '1', -- continue pushing if there's valid data
            data => bnoc_rx_s.req.data,
            ready => true
            );
          rin.count <=  nsl_data.fifo.fifo_shift_fillness(
            storage => r.fifo,
            fillness => r.count,
            min_fill => 0,
            valid => bnoc_rx_s.req.valid = '1', -- continue pushing if there's valid data
            data => bnoc_rx_s.req.data,
            ready => true
            );
        else
          rin.state <= ST_IDLE;
        end if;
        
      when ST_RSP_CONFIG_PUT =>
        if nsl_amba.axi4_stream.is_ready(axi_s_cfg_c, rsp_i) then
          if nsl_amba.axi4_stream.is_last(cfg => buffer_cfg_c, b => r.encoded) and nsl_amba.axi4_stream.is_ready(axi_s_cfg_c, rsp_i) then
            rin.state <= ST_RSP_CONFIG_PREP;
          end if;
          rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
        end if;
        
      when ST_RSP_PUT =>
        if nsl_amba.axi4_stream.is_ready(axi_s_cfg_c, rsp_i) then
          rin.state <= ST_IDLE;
        end if;

      when ST_ERROR_DRAIN =>
        if nsl_amba.axi4_stream.is_valid(axi_s_cfg_c, cmd_i) and nsl_amba.axi4_stream.is_last(axi_s_cfg_c, cmd_i) then
          rin.state <= ST_RSP_PUT;
          rin.rsp_success <= false;
          rin.parser <= nsl_data.cbor.reset;
        end if;
        
    end case;
    
  end process;

  output: process(r, bnoc_tx_s, cmd_i)
  begin
    cmd_o <= nsl_amba.axi4_stream.accept(axi_s_cfg_c, false);
    rsp_o <= nsl_amba.axi4_stream.transfer_defaults( cfg => axi_s_cfg_c);

    bnoc_tx_s.req.valid <= '0';
    bnoc_tx_s.req.data <= (others => '-');
    bnoc_rx_s.ack.ready <= nsl_logic.bool.to_logic(nsl_data.fifo.fifo_can_push(storage => r.fifo, fillness => r.count));
    
    case r.state is
      when ST_RESET =>
                   
      when ST_IDLE =>
        cmd_o <= nsl_amba.axi4_stream.accept(axi_s_cfg_c, not nsl_data.cbor.is_done(r.parser));
        
      when ST_CONFIG_ITEM_GET =>
        cmd_o <= nsl_amba.axi4_stream.accept(axi_s_cfg_c, not nsl_data.cbor.is_done(r.parser));
        
      when ST_CONFIG_STR_GET =>
        cmd_o <= nsl_amba.axi4_stream.accept(axi_s_cfg_c, true);

      when ST_CONFIG_STR_DRAIN =>
        cmd_o <= nsl_amba.axi4_stream.accept(axi_s_cfg_c, r.len /= 0);

      when ST_MESSAGE_ROUTE =>
        cmd_o <= nsl_amba.axi4_stream.accept(axi_s_cfg_c, nsl_logic.bool.to_boolean(bnoc_tx_s.ack.ready));
        bnoc_tx_s.req.valid <= nsl_logic.bool.to_logic(nsl_amba.axi4_stream.is_valid(axi_s_cfg_c, cmd_i));
        bnoc_tx_s.req.data <= cmd_i.data(0);
              
      when ST_RSP_BSTR_HDR_PREP | ST_RSP_CONFIG_PREP =>
        
      when ST_RSP_BSTR_HDR_PUT =>
        rsp_o <= nsl_amba.axi4_stream.next_beat(cfg => buffer_cfg_c, b => r.encoded, last => false);

      when ST_RSP_CONFIG_PUT =>
        rsp_o <= nsl_amba.axi4_stream.next_beat(cfg => buffer_cfg_c, b => r.encoded, last => nsl_amba.axi4_stream.is_last(cfg => buffer_cfg_c, b => r.encoded) and r.last);

      when ST_RSP_DATA_PUT =>
        bnoc_rx_s.ack.ready <= '1';
        rsp_o <= nsl_amba.axi4_stream.transfer( cfg => axi_s_cfg_c, bytes => nsl_data.bytestream.from_suv(r.fifo(0)), last => r.flush_count = 1);

      when ST_RSP_PUT =>
        if r.rsp_success then
          rsp_o <= nsl_amba.axi4_stream.transfer( cfg => axi_s_cfg_c, bytes => nsl_data.bytestream.from_suv(OP_SUCCESS), last => true);
        else
          rsp_o <= nsl_amba.axi4_stream.transfer( cfg => axi_s_cfg_c, bytes => nsl_data.bytestream.from_suv(OP_FAILURE), last => true);
        end if;

      when ST_ERROR_DRAIN =>
        cmd_o <= nsl_amba.axi4_stream.accept(axi_s_cfg_c, true);

    end case;
  end process;

  stop_count_s <= to_unsigned(r.stop_count, 2);
  parity_s <= to_unsigned(nsl_uart.serdes.parity_t'pos(r.parity), 2);
  
  uart8: nsl_uart.transactor.uart8_no_generics
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      divisor_i  => r.divisor,

      tx_o   => tx_o,
      cts_i  => cts_i,
      rx_i   => rx_i,
      rts_o  => rts_o,

      -- Resync/deglitched raw signals
      cts_o => open,
      rx_o  => open,

      tx_data_i => bnoc_tx_s.req,
      tx_data_o => bnoc_tx_s.ack,
      rx_data_i => bnoc_rx_s.ack,
      rx_data_o => bnoc_rx_s.req,

      parity_error_o => open,
      break_o     => open,

      stop_count_i       => stop_count_s,
      parity_i           => parity_s,
      handshake_active_i => r.hs
    );

end architecture;
