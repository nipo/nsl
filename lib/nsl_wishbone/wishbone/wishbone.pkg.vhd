library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_math;
use nsl_logic.bool.all;

-- This package defines wishbone bus signals and accessors.
--
-- As this is cumbersome (and not yet really portable) to have
-- generics in packages for VHDL, do this another way:
--
-- Package defines the worst case of 64-bit address, 64-bit data,
-- 64-bit tags.  Signals will convey this worst case.  Then modules
-- may use only a subset.  In order to agree on the subset they use,
-- encapsutate parameters and pass them as generics to every WB
-- component.  For simple protocols evolutions like Classic-standard
-- vs.  Classic-pipelined, this can also enable every component to
-- handle both cases.
--
-- In case a component has multiple WB ports with different
-- configurations (like a bus adapter), it should be passed multiple
-- configurations with a clear association of which port is of which
-- configuration.
--
-- By using accessors for setting and for extracting useful data out
-- of bus signals, we ensure bits that are not used in the current
-- configuration are never set / read, leaving opportunity to
-- optimizer to strip them.
package wishbone is

  constant wb_max_address_width_c: natural := 64;
  constant wb_min_data_width_c: natural := 8;
  constant wb_max_data_width_c: natural := 64;
  constant wb_max_tag_width_c: natural := 64;
  constant wb_min_data_width_l2_c: natural := nsl_math.arith.log2(wb_min_data_width_c);
  constant wb_max_data_width_l2_c: natural := nsl_math.arith.log2(wb_max_data_width_c);
  
  subtype wb_data_t is std_ulogic_vector(wb_max_data_width_c-1 downto 0);
  subtype wb_addr_t is unsigned(wb_max_address_width_c-1 downto 0);
  subtype wb_tag_t is std_ulogic_vector(wb_max_tag_width_c-1 downto 0);
  subtype wb_sel_t is std_ulogic_vector(7 downto 0);
  subtype wb_cti_t is std_ulogic_vector(2 downto 0);
  subtype wb_bte_t is std_ulogic_vector(1 downto 0);

  -- WB spec versions. Only B4 is supported for now.
  type wb_version_t is (
    WB_B4
  );

  -- Bus endianness
  type wb_endian_t is (
    WB_ENDIAN_LITTLE,
    WB_ENDIAN_BIG
    );

  -- Cycle type definition in Registered mode
  type wb_cycle_type_t is (
    WB_CYCLE_CLASSIC,
    WB_CYCLE_CONSTANT,
    WB_CYCLE_INCREMENT,
    WB_CYCLE_END
    );

  function to_logic(c: wb_cycle_type_t) return wb_cti_t;
  function to_cycle_type(c: wb_cti_t) return wb_cycle_type_t;

  -- Burst type in Registered mode
  type wb_burst_type_t is (
    WB_BURST_LINEAR,
    WB_BURST_4,
    WB_BURST_8,
    WB_BURST_16
    );

  function to_logic(c: wb_burst_type_t) return wb_bte_t;
  function to_burst_type(c: wb_bte_t) return wb_burst_type_t;

  -- Termination type. This is an enum matching the permitted
  -- encodings of ack/rty/err signals. When converted to actual wire
  -- encoding, rty would fallback to error and error to ack if they
  -- are not supported.
  type wb_term_t is (
    -- Do not terminate the command
    WB_TERM_NONE,
    -- ack = 1
    WB_TERM_ACK,
    -- rty = 1 (if supported)
    WB_TERM_RETRY,
    -- err = 1 (if supported)
    WB_TERM_ERROR
    );

  -- Bus type.
  type wb_bus_type_t is (
    -- WB B4 Chapter 3.1.3.1
    WB_CLASSIC_STANDARD,
    -- WB B4 Chapter 3.1.3.2
    WB_CLASSIC_PIPELINED,
    -- WB B4 Chapter 4
    WB_REGISTERED
    );

  -- Parameters, they need to be shared between master and slave
  -- connected on the same signals.
  type wb_config_t is
  record
    version: wb_version_t;
    bus_type: wb_bus_type_t;

    adr_width: integer range 0 to wb_max_address_width_c;

    -- These are log2 of the actual values (32 maps to 5, for instance)
    port_size_l2: integer range wb_min_data_width_l2_c to wb_max_data_width_l2_c;
    -- In bits
    port_granularity_l2: integer range wb_min_data_width_l2_c to wb_max_data_width_l2_c;
    max_op_size_l2: integer range wb_min_data_width_l2_c to wb_max_data_width_l2_c;

    endian: wb_endian_t;

    error_supported: boolean;
    retry_supported: boolean;

    -- Tags
    tga_width: integer range 0 to wb_max_tag_width_c;
    req_tgd_width: integer range 0 to wb_max_tag_width_c;
    ack_tgd_width: integer range 0 to wb_max_tag_width_c;
    tgc_width: integer range 0 to wb_max_tag_width_c;

    -- Bus timeout from the master perspective.
    timeout  : natural;

    -- Registered Feedback Bus Cycle features
    burst_supported: boolean;
    wrap_supported: boolean;
  end record;

  -- Wishbone Classic signals, either pipelined or not, depends on config
  type wb_req_t is
  record
    cyc: std_ulogic;
    lock: std_ulogic;
    tgc: wb_tag_t;

    adr: wb_addr_t;
    tga: wb_tag_t;

    stb: std_ulogic;

    we: std_ulogic;
    dat: wb_data_t;
    sel: wb_sel_t;
    tgd: wb_tag_t;

    -- Registered Feedback Bus Cycle features
    cti: wb_cti_t;
    bte: wb_bte_t;
  end record;
    
  type wb_ack_t is
  record
    dat: wb_data_t;
    ack, stall, err, rty: std_ulogic;
    tgd: wb_tag_t;
  end record;

  type wb_bus_t is
  record
    req: wb_req_t;
    ack: wb_ack_t;
  end record;
  
  type wb_req_vector is array (natural range <>) of wb_req_t;
  type wb_ack_vector is array (natural range <>) of wb_ack_t;
  type wb_bus_vector is array (natural range <>) of wb_bus_t;

  constant na_suv: std_ulogic_vector := (1 to 0 => '-');
  constant na_u: unsigned := (1 to 0 => '-');

  -- Generic helpers to extract bus parameters from the config record
  function wb_sel_width(config: wb_config_t) return natural;
  function wb_data_width(config: wb_config_t) return natural;
  function wb_address_msb(config: wb_config_t) return natural;
  function wb_address_lsb(config: wb_config_t) return natural;
  function wb_word_address_size(config: wb_config_t) return natural;
  function wbc_dat_endian_swap(config: wb_config_t;
                              v: std_ulogic_vector) return std_ulogic_vector;
  function wbc_sel_endian_swap(config: wb_config_t;
                              v: std_ulogic_vector) return std_ulogic_vector;
                               
  
  -- WB Classic IO helpers

  --  Command serialization helpers

  -- Cycle is not asserted
  function wbc_req_idle(config: wb_config_t) return wb_req_t;
  -- Cycle is asserted, maybe lock as well. Tag is optional.
  function wbc_cycle(config: wb_config_t;
                     lock: boolean := false;
                     cycle_tag: std_ulogic_vector := na_suv) return wb_req_t;
  -- Read cycle
  function wbc_read(config: wb_config_t;
                    address: unsigned := na_u;
                    lock: boolean := false;
                    address_tag: std_ulogic_vector := na_suv;
                    cycle_tag: std_ulogic_vector := na_suv) return wb_req_t;
  -- Write cycle
  function wbc_write(config: wb_config_t;
                     address: unsigned := na_u;
                     sel: std_ulogic_vector := na_suv;
                     data: std_ulogic_vector := na_suv;
                     lock: boolean := false;
                     address_tag: std_ulogic_vector := na_suv;
                     data_tag: std_ulogic_vector := na_suv;
                     cycle_tag: std_ulogic_vector := na_suv) return wb_req_t;

  -- Response extraction helpers

  -- Tells whether the request is accepted. In pipelined mode, this
  -- boils down to non-assertion of stall. In standard mode, this is
  -- termination of request.
  function wbc_is_accepted(config: wb_config_t; ack: wb_ack_t) return boolean;
  -- Tells whether termination is asserted (i.e. either ack, rty or err). Tells
  -- we have an useful cycle from slave to master.
  function wbc_term(config: wb_config_t; ack: wb_ack_t) return wb_term_t;
  -- Retrieves data from a ack.
  function wbc_data(config: wb_config_t; ack: wb_ack_t) return std_ulogic_vector;
  -- Retrieves data tag from a ack.
  function wbc_data_tag(config: wb_config_t; ack: wb_ack_t) return std_ulogic_vector;

  -- Command extraction helpers

  -- Tells whether cycle is asserted
  function wbc_is_cycle(config: wb_config_t; req: wb_req_t) return boolean;
  -- Tells whether cycle is locked
  function wbc_is_locked(config: wb_config_t; req: wb_req_t) return boolean;
  -- Tells whether cycle and stb are asserted
  function wbc_is_active(config: wb_config_t; req: wb_req_t) return boolean;
  -- Tells whether cycle, stb, and read are asserted
  function wbc_is_read(config: wb_config_t; req: wb_req_t) return boolean;
  -- Tells whether cycle, stb, and write are asserted
  function wbc_is_write(config: wb_config_t; req: wb_req_t) return boolean;
  -- Extracts data from a request. Only returns the number of data
  -- bits defined in the configuration
  function wbc_data(config: wb_config_t; req: wb_req_t) return std_ulogic_vector;
  -- Extracts sel from a request.  Only returns the number of sel
  -- bits defined in the configuration (port size / granularity)
  function wbc_sel(config: wb_config_t; req: wb_req_t) return std_ulogic_vector;
  -- Extracts address from a request.   Returns the number of address
  -- bits defined in the configuration (down to index 0)
  function wbc_address(config: wb_config_t; req: wb_req_t) return unsigned;
  -- Extracts address, stripping LSBs that are unused because of port
  -- size.  Returns the number of address bits defined in the
  -- configuration (down to index of log2(port size))
  function wbc_word_address(config: wb_config_t; req: wb_req_t) return unsigned;
  -- Extracts cycle tag from a request. Only returns cycle tag size bits.
  function wbc_cycle_tag(config: wb_config_t; req: wb_req_t) return std_ulogic_vector;
  -- Extracts address tag from a request. Only returns address tag size bits.
  function wbc_address_tag(config: wb_config_t; req: wb_req_t) return std_ulogic_vector;
  -- Extracts data tag from a request. Only returns request data tag size bits.
  function wbc_data_tag(config: wb_config_t; req: wb_req_t) return std_ulogic_vector;

  -- Response serialization helper

  -- Setting stall in standard mode is forbidden.  If setting err /
  -- rty termination on buses that do not support, this is either
  -- transformed to error or ack.
  function wbc_ack(config: wb_config_t;
                   stall: boolean := false;
                   term: wb_term_t := WB_TERM_NONE;
                   data: std_ulogic_vector := na_suv;
                   data_tag: std_ulogic_vector := na_suv)
     return wb_ack_t;
  
end package;

package body wishbone is
  
  function wb_sel_width(config: wb_config_t) return natural
  is
  begin
    return 2**(config.port_size_l2 - config.port_granularity_l2);
  end function;

  function wb_data_width(config: wb_config_t) return natural
  is
  begin
    return 2**config.port_size_l2;
  end function;

  function wb_address_msb(config: wb_config_t) return natural
  is
  begin
    return config.adr_width-1;
  end function;
  
  function wb_address_lsb(config: wb_config_t) return natural
  is
  begin
    return config.port_size_l2 - 3;
  end function;

  function wb_word_address_size(config: wb_config_t) return natural
  is
  begin
    return wb_address_msb(config) - wb_address_lsb(config) + 1;
  end function;
  
  function tag_serialize(tag: std_ulogic_vector;
                       width: integer range 0 to 64)
    return wb_tag_t
  is
    variable ret: wb_tag_t := (others => '-');
  begin
    if tag'length = 0 then
      return ret;
    end if;

    assert tag'length = width
      report "Bad tag width, had " & integer'image(tag'length) & " bits, expected "
      & integer'image(width)
      severity failure;

    ret(tag'length-1 downto 0) := tag;
    return ret;
  end function;

  
  function wbc_dat_endian_swap(config: wb_config_t;
                               v: std_ulogic_vector) return std_ulogic_vector
  is
    alias xv: std_ulogic_vector(v'length-1 downto 0) is v;
    variable ret : std_ulogic_vector(wb_data_width(config)-1 downto 0);
    constant g_size: natural := 2 ** config.port_granularity_l2;
    variable a_off, d_off: natural;
  begin
    assert xv'length = ret'length
      report "Bad data width"
      severity failure;

    for g in 0 to wb_sel_width(config)-1
    loop
      a_off := g * g_size;
      d_off := (wb_sel_width(config) - 1 - g) * g_size;

      ret(a_off + g_size - 1 downto a_off) := xv(d_off + g_size - 1 downto d_off);
    end loop;

    return ret;
  end function;
      
  function wbc_sel_endian_swap(config: wb_config_t;
                               v: std_ulogic_vector) return std_ulogic_vector
  is
    alias xv: std_ulogic_vector(v'length-1 downto 0) is v;
    variable ret : std_ulogic_vector(wb_sel_width(config)-1 downto 0);
    variable a_off, d_off: natural;
  begin
    assert xv'length = ret'length
      report "Bad sel width"
      severity failure;

    for g in 0 to wb_sel_width(config)-1
    loop
      a_off := g;
      d_off := (wb_sel_width(config) - 1 - g);

      ret(a_off) := xv(d_off);
    end loop;

    return ret;
  end function;



  -- Command serialization helpers

  function wbc_req_idle(config: wb_config_t) return wb_req_t
  is
  begin
    assert config.bus_type /= WB_REGISTERED
      report "Cannot use class helper functions and datatypes for REGISTERED cycle type"
      severity failure;

    return (
      cyc => '0',
      lock => '0',
      tgc => (others => '-'),

      adr => (others => '0'),
      tga => (others => '-'),

      stb => '0',

      we => '-',
      dat => (others => '-'),
      sel => (others => '-'),
      tgd => (others => '-'),

      cti => (others => '0'),
      bte => (others => '0')
      );
  end function;
  
  function wbc_cycle(config: wb_config_t;
                     lock: boolean := false;
                     cycle_tag: std_ulogic_vector := na_suv)
    return wb_req_t
  is
    variable req: wb_req_t := wbc_req_idle(config);
  begin
    req.cyc := '1';
    req.lock := to_logic(lock);
    req.tgc := tag_serialize(cycle_tag, config.tgc_width);

    return req;
  end function;
  
  function wbc_read(config: wb_config_t;
                    address: unsigned := na_u;
                    lock: boolean := false;
                    address_tag: std_ulogic_vector := na_suv;
                    cycle_tag: std_ulogic_vector := na_suv)
    return wb_req_t
  is
    variable req: wb_req_t := wbc_cycle(config => config,
                                         lock => lock,
                                         cycle_tag => cycle_tag);
  begin
    req.stb := '1';
    req.we := '0';

    if address'length /= 0 then
      req.adr(address'length-1 downto 0) := address;
      -- LSBs under port size are insignificant
      req.adr(wb_address_lsb(config)-1 downto 0) := (others => '0');
    end if;

    req.tga := tag_serialize(address_tag, config.tga_width);

    return req;
  end function;
  
  function wbc_write(config: wb_config_t;
                     address: unsigned := na_u;
                     sel: std_ulogic_vector := na_suv;
                     data: std_ulogic_vector := na_suv;
                     lock: boolean := false;
                     address_tag: std_ulogic_vector := na_suv;
                     data_tag: std_ulogic_vector := na_suv;
                     cycle_tag: std_ulogic_vector := na_suv)
    return wb_req_t
  is
    variable req: wb_req_t := wbc_read(config => config,
                                        address => address,
                                        lock => lock,
                                        address_tag => address_tag,
                                        cycle_tag => cycle_tag);
  begin
    req.we := '1';

    assert sel'length = wb_sel_width(config)
      report "Bad sel width " & integer'image(sel'length) & ", expected " & integer'image(wb_sel_width(config))
      severity failure;

    assert data'length = wb_data_width(config)
      report "Bad data width " & integer'image(data'length) & ", expected " & integer'image(wb_data_width(config))
      severity failure;

    req.sel(wb_sel_width(config)-1 downto 0) := sel;
    req.dat(wb_data_width(config)-1 downto 0) := data;
    req.tgd := tag_serialize(data_tag, config.req_tgd_width);
    
    return req;
  end function;

  -- Response serialization helper
  
  function wbc_ack(config: wb_config_t;
                   stall: boolean := false;
                   term: wb_term_t := WB_TERM_NONE;
                   data: std_ulogic_vector := na_suv;
                   data_tag: std_ulogic_vector := na_suv)
    return wb_ack_t
  is
    variable ack: wb_ack_t := (
      dat => (others => '-'),
      ack => '0',
      stall => '0',
      tgd => (others => '-'),
      err => '0',
      rty => '0'
      );
  begin
    assert config.bus_type /= WB_REGISTERED
      report "Cannot use class helper functions and datatypes for REGISTERED cycle type"
      severity failure;

    if term = WB_TERM_NONE then
      null;
    elsif term = WB_TERM_ACK then
      ack.ack := '1';
      ack.dat(data'length-1 downto 0) := data;
      ack.tgd := tag_serialize(data_tag, config.ack_tgd_width);
    elsif config.error_supported and term = WB_TERM_ERROR then
      ack.err := '1';
    elsif config.retry_supported and term = WB_TERM_RETRY then
      ack.rty := '1';
    else
      -- Error/retry cases when error/retry is unsupported
      ack.ack := '1';
    end if;

    if config.bus_type = WB_CLASSIC_PIPELINED then
      ack.stall := to_logic(stall);
    else
      assert not stall
        report "Cannot stall in non-pipelined mode"
        severity failure;
    end if;
    
    return ack;
  end function;


  -- Command extraction helpers
  
  function wbc_is_cycle(config: wb_config_t; req: wb_req_t) return boolean
  is
  begin
    return req.cyc = '1';
  end function;

  function wbc_is_locked(config: wb_config_t; req: wb_req_t) return boolean
  is
  begin
    return req.lock = '1';
  end function;

  function wbc_is_active(config: wb_config_t; req: wb_req_t) return boolean
  is
  begin
    return req.cyc = '1' and req.stb = '1';
  end function;

  function wbc_is_read(config: wb_config_t; req: wb_req_t) return boolean
  is
  begin
    return req.cyc = '1' and req.stb = '1' and req.we /= '1';
  end function;

  function wbc_is_write(config: wb_config_t; req: wb_req_t) return boolean
  is
  begin
    return req.cyc = '1' and req.stb = '1' and req.we = '1';
  end function;

  function wbc_data(config: wb_config_t; req: wb_req_t) return std_ulogic_vector
  is
  begin
    return req.dat(wb_data_width(config)-1 downto 0);
  end function;

  function wbc_sel(config: wb_config_t; req: wb_req_t) return std_ulogic_vector
  is
  begin
    return req.sel(wb_sel_width(config)-1 downto 0);
  end function;

  function wbc_address(config: wb_config_t; req: wb_req_t) return unsigned
  is
  begin
    return req.adr(wb_address_msb(config) downto 0);
  end function;

  function wbc_word_address(config: wb_config_t; req: wb_req_t) return unsigned
  is
  begin
    return req.adr(wb_address_msb(config) downto wb_address_lsb(config));
  end function;

  function wbc_cycle_tag(config: wb_config_t; req: wb_req_t) return std_ulogic_vector
  is
  begin
    return req.tgc(config.tgc_width-1 downto 0);
  end function;

  function wbc_address_tag(config: wb_config_t; req: wb_req_t) return std_ulogic_vector
  is
  begin
    return req.tga(config.tga_width-1 downto 0);
  end function;

  function wbc_data_tag(config: wb_config_t; req: wb_req_t) return std_ulogic_vector
  is
  begin
    return req.tgd(config.req_tgd_width-1 downto 0);
  end function;

  -- Response extraction helpers
  
  function wbc_is_accepted(config: wb_config_t; ack: wb_ack_t) return boolean
  is
  begin
    if config.bus_type = WB_CLASSIC_PIPELINED then
      return ack.stall = '0';
    end if;

    if config.retry_supported then
      if ack.rty = '1' then
        return true;
      end if;
    end if;

    if config.error_supported then
      if ack.err = '1' then
        return true;
      end if;
    end if;

    return ack.ack = '1';
  end function;

  function wbc_term(config: wb_config_t; ack: wb_ack_t) return wb_term_t
  is
  begin
    if config.error_supported and ack.err = '1' then
      return WB_TERM_ERROR;
    end if;

    if config.retry_supported and ack.rty = '1' then
      return WB_TERM_ERROR;
    end if;

    if ack.ack = '1' then
      return WB_TERM_ACK;
    end if;

    return WB_TERM_NONE;
  end function;

  function wbc_data(config: wb_config_t; ack: wb_ack_t) return std_ulogic_vector
  is
  begin
    return ack.dat(wb_data_width(config)-1 downto 0);
  end function;

  function wbc_data_tag(config: wb_config_t; ack: wb_ack_t) return std_ulogic_vector
  is
  begin
    return ack.tgd(config.ack_tgd_width-1 downto 0);
  end function;


  -- Registered feedback conversion helpers
  
  function to_logic(c: wb_cycle_type_t)
    return wb_cti_t
  is
  begin
    case c is
      when WB_CYCLE_CLASSIC => return "000";
      when WB_CYCLE_CONSTANT => return "001";
      when WB_CYCLE_INCREMENT => return "010";
      when WB_CYCLE_END => return "111";
    end case;
  end function;
                           
  function to_cycle_type(c: wb_cti_t)
    return wb_cycle_type_t
  is
  begin
    case c is
      when "001" => return WB_CYCLE_CONSTANT;
      when "010" => return WB_CYCLE_INCREMENT;
      when "111" => return WB_CYCLE_END;
      -- RULE 4.10
      when others => return WB_CYCLE_CLASSIC;
    end case;
  end function;

  function to_logic(c: wb_burst_type_t)
    return wb_bte_t
  is
  begin
    case c is
      when WB_BURST_LINEAR => return "00";
      when WB_BURST_4 => return "01";
      when WB_BURST_8 => return "10";
      when WB_BURST_16 => return "11";
    end case;
  end function;

  function to_burst_type(c: wb_bte_t)
    return wb_burst_type_t
  is
  begin
    case c is
      when "00" => return WB_BURST_LINEAR;
      when "01" => return WB_BURST_4;
      when "10" => return WB_BURST_8;
      when others => return WB_BURST_16;
    end case;
  end function;

end package body wishbone;
