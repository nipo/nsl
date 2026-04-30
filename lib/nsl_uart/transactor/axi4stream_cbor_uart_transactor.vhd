library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;       

library nsl_uart, nsl_bnoc, nsl_amba, nsl_data, nsl_simulation, nsl_logic, nsl_event, nsl_signal_generator;
use nsl_data.cbor.all;

entity axi4stream_cbor_uart_transactor is
  generic(
    system_clock_c     : natural;
    stream_config_c    : nsl_amba.axi4_stream.config_t;
    stop_count_c       : natural range 1 to 2 := 1;
    parity_c           : nsl_uart.serdes.parity_t := nsl_uart.serdes.PARITY_NONE;
    handshake_active_c : std_ulogic := '0';
    baud_rate_c        : unsigned(23 downto 0);
    timeout_c          : unsigned(23 downto 0);
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

architecture rtl of axi4stream_cbor_uart_transactor is

  constant OP_SUCCESS : std_ulogic_vector(7 downto 0) := X"F5";
  constant OP_FAILURE : std_ulogic_vector(7 downto 0) := X"F4";

  function max(a, b : natural) return natural is
  begin
    if a > b then return a; else return b; end if;
  end function;

  constant item_count_max_c : natural := 511;
  constant cbr_max_size_c : natural := 30; -- max payload is the response with
                                           -- the configuration map
  constant buffer_cfg_c   : nsl_amba.axi4_stream.buffer_config_t := nsl_amba.axi4_stream.buffer_config(stream_config_c, 30);

  constant FLOW_CTRL_STR_C : string := "flow-ctrl";
  constant PARITY_STR_C    : string := "parity";
  constant BAUD_RATE_STR_C : string := "baud-rate";
  constant NONE_STR_C      : string := "none";
  constant CTS_STR_C       : string := "cts";
  constant N_STR_C         : string := "n";
  constant E_STR_C         : string := "e";
  constant O_STR_C         : string := "o";
  
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
    baudrate    : unsigned(23 downto 0);

    count       : natural range 0 to bstr_max_size_c + 8;
    flush_count : natural range 0 to bstr_max_size_c + 8;
    timeout     : unsigned(23 downto 0);  -- Counts 2x-baud ticks until flush
    fifo        : nsl_data.bytestream.byte_string(0 to bstr_max_size_c + 7);
    
    encoded     : nsl_amba.axi4_stream.buffer_t;
    last        : boolean;
    rsp_success : boolean;
  end record;

  signal r, rin: regs_t;

  signal bnoc_tx_s, bnoc_rx_s: nsl_bnoc.pipe.pipe_bus_t;

  signal baudrate_x2_s : unsigned(24 downto 0);
  signal baudratex2_s, tick_s: std_ulogic;
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

  transition: process(cmd_i, r, bnoc_rx_s, bnoc_tx_s, rsp_i, tick_s)
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
        rin.baudrate   <= baud_rate_c;
        rin.last       <= false;
        rin.len        <= 0;
        rin.count      <= 0;
        rin.timeout    <= timeout_c;
 
      when ST_IDLE =>
        -- Tick-based timeout: count 2x-baud ticks
        if r.count > 0 and tick_s = '1' then
          if r.timeout > 0 then
            rin.timeout <= r.timeout - 1;
          end if;
        end if;

        if (r.count > 0 and r.timeout = 0) or r.count >= bstr_max_size_c then
          -- Send loopback data when timeout expires or FIFO reaches max report size
          rin.flush_count <= r.count;
          rin.state       <= ST_RSP_BSTR_HDR_PREP;
          rin.timeout     <= timeout_c;
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
          if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) then
            rin.parser <= nsl_data.cbor.feed(r.parser, cmd_i.data(0));
          end if;
        else
          if nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_TSTR then
            rin.len <= nsl_data.cbor.arg_int(r.parser);
            rin.state <= ST_CONFIG_STR_GET;
          elsif nsl_data.cbor.kind(r.parser) = nsl_data.cbor.KIND_POSITIVE then
            if r.map_state = MAP_VAL_BR then
              rin.baudrate <= nsl_data.cbor.arg(r.parser, 24);
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
            rin.encoded <= nsl_amba.axi4_stream.reset(buffer_cfg_c, nsl_data.cbor.cbor_positive(r.baudrate));
            rin.last <= true;
          when others =>
            rin.item_count <= 0;
            rin.state <= ST_IDLE;
        end case;        
        if r.item_count < 7 then
          rin.state <= ST_RSP_CONFIG_PUT;
        end if;

      when ST_MESSAGE_ROUTE =>
        if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) and bnoc_tx_s.ack.ready = '1' then
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
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          if nsl_amba.axi4_stream.is_last(buffer_cfg_c, r.encoded) then
            rin.state <= ST_RSP_DATA_PUT;
          end if;
          rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
        end if;
                  
      when ST_RSP_DATA_PUT =>
        if r.flush_count > 0 and nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
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
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          if nsl_amba.axi4_stream.is_last(cfg => buffer_cfg_c, b => r.encoded) and nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
            rin.state <= ST_RSP_CONFIG_PREP;
          end if;
          rin.encoded <= nsl_amba.axi4_stream.shift(buffer_cfg_c, r.encoded);
        end if;
        
      when ST_RSP_PUT =>
        if nsl_amba.axi4_stream.is_ready(stream_config_c, rsp_i) then
          rin.state <= ST_IDLE;
        end if;

      when ST_ERROR_DRAIN =>
        if nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i) and nsl_amba.axi4_stream.is_last(stream_config_c, cmd_i) then
          rin.state <= ST_RSP_PUT;
          rin.rsp_success <= false;
          rin.parser <= nsl_data.cbor.reset;
        end if;
        
    end case;
    
  end process;

  output: process(r, bnoc_tx_s, cmd_i)
  begin
    cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, false);
    rsp_o <= nsl_amba.axi4_stream.transfer_defaults(cfg => stream_config_c);

    bnoc_tx_s.req.valid <= '0';
    bnoc_tx_s.req.data <= (others => '-');
    bnoc_rx_s.ack.ready <= nsl_logic.bool.to_logic(nsl_data.fifo.fifo_can_push(storage => r.fifo, fillness => r.count));
    
    case r.state is
      when ST_RESET =>
                   
      when ST_IDLE =>
        cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, not nsl_data.cbor.is_done(r.parser));
        
      when ST_CONFIG_ITEM_GET =>
        cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, not nsl_data.cbor.is_done(r.parser));
        
      when ST_CONFIG_STR_GET =>
        cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, true);

      when ST_CONFIG_STR_DRAIN =>
        cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, r.len /= 0);

      when ST_MESSAGE_ROUTE =>
        cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, nsl_logic.bool.to_boolean(bnoc_tx_s.ack.ready));
        bnoc_tx_s.req.valid <= nsl_logic.bool.to_logic(nsl_amba.axi4_stream.is_valid(stream_config_c, cmd_i));
        bnoc_tx_s.req.data <= cmd_i.data(0);
              
      when ST_RSP_BSTR_HDR_PREP | ST_RSP_CONFIG_PREP =>
        
      when ST_RSP_BSTR_HDR_PUT =>
        rsp_o <= nsl_amba.axi4_stream.next_beat(cfg => buffer_cfg_c, b => r.encoded, last => false);

      when ST_RSP_CONFIG_PUT =>
        rsp_o <= nsl_amba.axi4_stream.next_beat(cfg => buffer_cfg_c, b => r.encoded, last => nsl_amba.axi4_stream.is_last(cfg => buffer_cfg_c, b => r.encoded) and r.last);

      when ST_RSP_DATA_PUT =>
        bnoc_rx_s.ack.ready <= '1';
        rsp_o <= nsl_amba.axi4_stream.transfer(cfg =>stream_config_c, bytes => nsl_data.bytestream.from_suv(r.fifo(0)), last => r.flush_count = 1);

      when ST_RSP_PUT =>
        if r.rsp_success then
          rsp_o <= nsl_amba.axi4_stream.transfer(cfg =>stream_config_c, bytes => nsl_data.bytestream.from_suv(OP_SUCCESS), last => true);
        else
          rsp_o <= nsl_amba.axi4_stream.transfer(cfg =>stream_config_c, bytes => nsl_data.bytestream.from_suv(OP_FAILURE), last => true);
        end if;

      when ST_ERROR_DRAIN =>
        cmd_o <= nsl_amba.axi4_stream.accept(stream_config_c, true);

    end case;
  end process;

  uart8: nsl_uart.transactor.uart8_dynamic_config
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      tick_i => tick_s,

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

      stop_count_i       => r.stop_count,
      parity_i           => r.parity,
      handshake_active_i => r.hs
    );

    tick: nsl_event.tick.tick_extractor_clock
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        signal_i => baudratex2_s,
        tick_o => tick_s
      );

    baudrate_x2_s <= shift_left(resize(r.baudrate, 25), 1);

    baudrate_x2: nsl_signal_generator.frequency.frequency_generator
      generic map(
        clock_rate_c => system_clock_c
      )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        frequency_i => baudrate_x2_s,
        value_o => baudratex2_s
      );

end architecture;
