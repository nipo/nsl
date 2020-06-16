library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_ti, nsl_data, nsl_i2c;
use nsl_ti.tla202x.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
  
entity tla202x_master is
  port(
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    cmd_o : out nsl_bnoc.framed.framed_req;
    cmd_i : in  nsl_bnoc.framed.framed_ack;
    rsp_i : in  nsl_bnoc.framed.framed_req;
    rsp_o : out nsl_bnoc.framed.framed_ack;

    saddr_i : in unsigned(7 downto 1);

    mux_i         : in  unsigned(2 downto 0) := MUX_0G;
    pga_i         : in  unsigned(2 downto 0) := PGA_1mV;
    dr_i          : in  unsigned(2 downto 0) := DR_1600;
    single_shot_i : in  std_ulogic           := '1';
    valid_i       : in  std_ulogic;
    ready_o       : out std_ulogic;

    sample_o : out unsigned(11 downto 0);
    valid_o  : out std_ulogic;
    ready_i  : in  std_ulogic
    );
end entity;

architecture beh of tla202x_master is

  constant REG_ADDR_CONVERSION : unsigned(7 downto 0) := X"00";
  constant REG_ADDR_CONFIGURATION : unsigned(7 downto 0) := X"01";
  
  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_CONFIG_CMD,
    ST_CONFIG_RSP,
    ST_DATA_CMD,
    ST_DATA_RSP,
    ST_DONE
    );

  function config_serialize(mux, pga, dr : unsigned(2 downto 0);
                            single_shot : std_ulogic) return byte_string is
    variable ret : unsigned(15 downto 0);
  begin
    ret(15) := single_shot;
    ret(14 downto 12) := mux;
    ret(11 downto 9) := pga;
    ret(8) := single_shot;
    ret(7 downto 5) := dr;
    ret(4 downto 0) := "00011";
    
    return to_be(ret);
  end function;

  function sample_parse(data : byte_string) return unsigned is
    variable value : unsigned(15 downto 0);
  begin
    value := from_be(data);
    return value(15 downto 4);
  end function;

  type regs_t is
  record
    state : state_t;
    config : byte_string(0 to 1);
    data : byte_string(0 to 1);
  end record;

  signal config_i : byte_string(0 to 1);

  signal i2c_addr_o  : unsigned(7 downto 0);
  signal i2c_wdata_o, i2c_rdata_i : nsl_data.bytestream.byte_string(0 to 1);
  signal i2c_valid_o, i2c_ready_i, i2c_write_o : std_ulogic;
  signal i2c_valid_i, i2c_ready_o, i2c_error_i : std_ulogic;
  
  signal r, rin: regs_t;

begin

  config_i <= config_serialize(mux_i, pga_i, dr_i, single_shot_i);
  
  regs: process(clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, config_i, valid_i, ready_i, single_shot_i,
                      i2c_rdata_i, i2c_valid_i, i2c_ready_i, i2c_error_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.config <= (x"00", x"00");

      when ST_IDLE =>
        if valid_i = '1' then
          if config_i /= r.config or single_shot_i = '1' then
            rin.state <= ST_CONFIG_CMD;
          else
            rin.state <= ST_DATA_CMD;
          end if;
          rin.config <= config_i;
        end if;
        
      when ST_CONFIG_CMD =>
        if i2c_ready_i = '1' then
          rin.state <= ST_CONFIG_RSP;
        end if;

      when ST_CONFIG_RSP =>
        if i2c_valid_i = '1' then
          rin.state <= ST_DATA_CMD;
        end if;

      when ST_DATA_CMD =>
        if i2c_ready_i = '1' then
          rin.state <= ST_DATA_RSP;
        end if;

      when ST_DATA_RSP =>
        if i2c_valid_i = '1' then
          rin.state <= ST_DONE;
          rin.data <= i2c_rdata_i;
        end if;

      when ST_DONE =>
        if ready_i = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    ready_o <= '0';
    valid_o <= '0';
    sample_o <= sample_parse(r.data);
    i2c_addr_o <= "--------";
    i2c_wdata_o <= r.config;
    i2c_valid_o <= '0';
    i2c_write_o <= '-';
    i2c_ready_o <= '0';

    case r.state is
      when ST_RESET =>
        null;

      when ST_IDLE =>
        ready_o <= '1';
        
      when ST_CONFIG_CMD =>
        i2c_write_o <= '1';
        i2c_valid_o <= '1';
        i2c_addr_o <= REG_ADDR_CONFIGURATION;

      when ST_DATA_CMD =>
        i2c_write_o <= '0';
        i2c_valid_o <= '1';
        i2c_addr_o <= REG_ADDR_CONVERSION;

      when ST_CONFIG_RSP | ST_DATA_RSP =>
        i2c_ready_o <= '1';

      when ST_DONE =>
        valid_o <= '1';
    end case;
  end process;    

  transactor: nsl_i2c.transactor.framed_addressed_controller
    generic map(
      addr_byte_count_c => 1,
      big_endian_c => true,
      txn_byte_count_max_c => 2
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      cmd_i => cmd_i,
      cmd_o => cmd_o,
      rsp_i => rsp_i,
      rsp_o => rsp_o,

      valid_i => i2c_valid_o,
      ready_o => i2c_ready_i,
      saddr_i => saddr_i,
      addr_i => i2c_addr_o,
      write_i => i2c_write_o,
      wdata_i => i2c_wdata_o,
      data_byte_count_i => 2,

      valid_o => i2c_valid_i,
      ready_i => i2c_ready_o,
      rdata_o => i2c_rdata_i,
      error_o => i2c_error_i
      );
  
end architecture;
