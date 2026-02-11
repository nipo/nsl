library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_spi, nsl_amba, nsl_simulation, nsl_data, nsl_event, nsl_io, nsl_memory;

architecture arch of tb is

  constant clock_period : time := 10 ns;
  
  constant cfg_c: nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(1, last => true);
  constant addr_byte_cnt: integer := 2;
  constant data_byte_cnt: integer := 2;

  signal s_cmd     : nsl_amba.axi4_stream.bus_t;
  signal s_rsp     : nsl_amba.axi4_stream.bus_t;
  signal s_rsp_pre : nsl_amba.axi4_stream.bus_t;

  signal spi_slave_i_s : nsl_spi.spi.spi_slave_i_vector(0 to 3);
  signal spi_slave_o_s : nsl_spi.spi.spi_slave_o_vector(0 to 3);

  signal spi_master_o_s : nsl_spi.spi.spi_master_o;
  signal spi_master_i_s : nsl_spi.spi.spi_master_i;
  signal cs_s_n  : nsl_io.io.opendrain_vector(0 to 4);
  
  signal s_clk    : std_ulogic := '0';
  signal s_resetn : std_ulogic;
  signal s_done   : std_ulogic_vector(0 to 0);

  signal   tick_s      : std_ulogic;
  signal   tick_i_hz_s : natural := 1;
  constant tick_divisor: unsigned(7 downto 0) := (others => '1');

  shared variable cmd_q, rsp_q: nsl_amba.axi4_stream.frame_queue_root_t;  
begin

  tick_i_hz_s <= 10e7/to_integer(tick_divisor);
  
  dut: nsl_spi.cbor_transactor.controller
    generic map(
      clock_i_hz_c   => 10e7,
      axi_s_cfg_c    => cfg_c,
      slave_count_c  => 5
      )
    port map(
      clock_i        => s_clk,
      reset_n_i      => s_resetn,

      tick_i_hz      => tick_i_hz_s,
      tick_i         => tick_s,

      sck_o          => spi_master_o_s.sck,
      cs_n_o         => cs_s_n,
      mosi_o         => spi_master_o_s.mosi,
      miso_i         => spi_master_i_s.miso,
      
      cmd_i          => s_cmd.m,
      cmd_o          => s_cmd.s,
      rsp_o          => s_rsp.m,
      rsp_i          => s_rsp.s
      -- rsp_o          => s_rsp_pre.m,
      -- rsp_i          => s_rsp_pre.s
      );
  
  slave_conn: for i in 0 to 3 generate
    spi_slave_i_s(i) <= nsl_spi.spi.to_slave(
      (sck => spi_master_o_s.sck, mosi => spi_master_o_s.mosi, cs_n => cs_s_n(i)));
  end generate;

  spi_master_i_s <= nsl_spi.spi.to_master(spi_slave_o_s(0)) when cs_s_n(0).drain_n = '0' else
                    nsl_spi.spi.to_master(spi_slave_o_s(1)) when cs_s_n(1).drain_n = '0' else
                    nsl_spi.spi.to_master(spi_slave_o_s(2)) when cs_s_n(2).drain_n = '0' else
                    nsl_spi.spi.to_master(spi_slave_o_s(3)) when cs_s_n(3).drain_n = '0' else
                    (miso => spi_master_o_s.mosi.v) when cs_s_n(4).drain_n = '0' else --loopback
                    (miso => 'Z');
  
  -- rsp_pacer : nsl_amba.stream_traffic.axi4_stream_pacer
  --   generic map(
  --     config_c => cfg_c,
  --     probability_c => 0.1
  --     )
  -- port map(
  --   clock_i => s_clk,
  --   reset_n_i => s_resetn,

  --   in_i => s_rsp_pre.m,
  --   in_o => s_rsp_pre.s,

  --   out_o => s_rsp.m,
  --   out_i => s_rsp.s
  --   ); 

  slave_mode0: block is
    signal s_write            : std_ulogic;
    signal s_rdata, s_wdata   : std_ulogic_vector(8*data_byte_cnt-1 downto 0);
    signal s_wdata_bytestream : nsl_data.bytestream.byte_string(0 to data_byte_cnt-1);
    signal s_address          : unsigned(8*addr_byte_cnt-1 downto 0);
  begin
    slave: nsl_spi.slave.spi_memory_controller
      generic map(
        addr_bytes_c   => addr_byte_cnt,
        data_bytes_c   => data_byte_cnt,
        write_opcode_c => x"0b"
        )
      port map(
        clock_i    => s_clk,
        reset_n_i  => s_resetn,

        spi_i      => spi_slave_i_s(0),
        spi_o      => spi_slave_o_s(0),
        
        selected_o => open,

        addr_o     => s_address,

        cpol_i     => '0',
        cpha_i     => '0',

        rdata_i    => nsl_data.bytestream.from_suv(s_rdata),
        rready_o   => open,

        wdata_o    => s_wdata_bytestream,
        wvalid_o   => s_write
        );

    s_wdata <= s_wdata_bytestream(1) & s_wdata_bytestream(0);
    
    ram : nsl_memory.ram.ram_1p
      generic map (
        addr_size_c => 8*addr_byte_cnt,
        data_size_c => 8*data_byte_cnt
        )
      port map (
        clock_i      => s_clk,
        write_en_i   => s_write,
        address_i    => s_address,
        write_data_i => s_wdata,
        read_data_o  => s_rdata
        );  
  end block;

  
  slave_mode1: block is
    signal s_write            : std_ulogic;
    signal s_rdata, s_wdata   : std_ulogic_vector(8*data_byte_cnt-1 downto 0);
    signal s_wdata_bytestream : nsl_data.bytestream.byte_string(0 to data_byte_cnt-1);
    signal s_address          : unsigned(8*addr_byte_cnt-1 downto 0);
  begin
    slave: nsl_spi.slave.spi_memory_controller
      generic map(
        addr_bytes_c   => addr_byte_cnt,
        data_bytes_c   => data_byte_cnt,
        write_opcode_c => x"0b"
        )
      port map(
        clock_i    => s_clk,
        reset_n_i  => s_resetn,

        spi_i      => spi_slave_i_s(1),
        spi_o      => spi_slave_o_s(1),
        
        selected_o => open,

        addr_o     => s_address,

        cpol_i     => '0',
        cpha_i     => '1',

        rdata_i    => nsl_data.bytestream.from_suv(s_rdata),
        rready_o   => open,

        wdata_o    => s_wdata_bytestream,
        wvalid_o   => s_write
        );

    s_wdata <= s_wdata_bytestream(1) & s_wdata_bytestream(0);
    
    ram : nsl_memory.ram.ram_1p
      generic map (
        addr_size_c => 8*addr_byte_cnt,
        data_size_c => 8*data_byte_cnt
        )
      port map (
        clock_i      => s_clk,
        write_en_i   => s_write,
        address_i    => s_address,
        write_data_i => s_wdata,
        read_data_o  => s_rdata
        );  
  end block;

  slave_mode2: block is
    signal s_write            : std_ulogic;
    signal s_rdata, s_wdata   : std_ulogic_vector(8*data_byte_cnt-1 downto 0);
    signal s_wdata_bytestream : nsl_data.bytestream.byte_string(0 to data_byte_cnt-1);
    signal s_address          : unsigned(8*addr_byte_cnt-1 downto 0);
  begin
    slave: nsl_spi.slave.spi_memory_controller
      generic map(
        addr_bytes_c   => addr_byte_cnt,
        data_bytes_c   => data_byte_cnt,
        write_opcode_c => x"0b"
        )
      port map(
        clock_i    => s_clk,
        reset_n_i  => s_resetn,

        spi_i      => spi_slave_i_s(2),
        spi_o      => spi_slave_o_s(2),
        
        selected_o => open,

        addr_o     => s_address,

        cpol_i     => '1',
        cpha_i     => '0',

        rdata_i    => nsl_data.bytestream.from_suv(s_rdata),
        rready_o   => open,

        wdata_o    => s_wdata_bytestream,
        wvalid_o   => s_write
        );

    s_wdata <= s_wdata_bytestream(1) & s_wdata_bytestream(0);
    
    ram : nsl_memory.ram.ram_1p
      generic map (
        addr_size_c => 8*addr_byte_cnt,
        data_size_c => 8*data_byte_cnt
        )
      port map (
        clock_i      => s_clk,
        write_en_i   => s_write,
        address_i    => s_address,
        write_data_i => s_wdata,
        read_data_o  => s_rdata
        );  
  end block;
  
  slave_mode3: block is
    signal s_write            : std_ulogic;
    signal s_rdata, s_wdata   : std_ulogic_vector(8*data_byte_cnt-1 downto 0);
    signal s_wdata_bytestream : nsl_data.bytestream.byte_string(0 to data_byte_cnt-1);
    signal s_address          : unsigned(8*addr_byte_cnt-1 downto 0);
  begin
    slave: nsl_spi.slave.spi_memory_controller
      generic map(
        addr_bytes_c   => addr_byte_cnt,
        data_bytes_c   => data_byte_cnt,
        write_opcode_c => x"0b"
        )
      port map(
        clock_i    => s_clk,
        reset_n_i  => s_resetn,

        spi_i      => spi_slave_i_s(3),
        spi_o      => spi_slave_o_s(3),
        
        selected_o => open,

        addr_o     => s_address,

        cpol_i     => '1',
        cpha_i     => '1',

        rdata_i    => nsl_data.bytestream.from_suv(s_rdata),
        rready_o   => open,

        wdata_o    => s_wdata_bytestream,
        wvalid_o   => s_write
        );

    s_wdata <= s_wdata_bytestream(1) & s_wdata_bytestream(0);
    
    ram : nsl_memory.ram.ram_1p
      generic map (
        addr_size_c => 8*addr_byte_cnt,
        data_size_c => 8*data_byte_cnt
        )
      port map (
        clock_i      => s_clk,
        write_en_i   => s_write,
        address_i    => s_address,
        write_data_i => s_wdata,
        read_data_o  => s_rdata
        );  
  end block;
  
  driver: nsl_simulation.driver.simulation_driver
  generic map(
    clock_count => 1,
    reset_count => 1,
    done_count => 1
    )
  port map(
    clock_period(0) => 10 ns,
    reset_duration(0) => 30 ns,
    reset_n_o(0) => s_resetn,
    clock_o(0) => s_clk,
    done_i => s_done
    );

  tick_gen: nsl_event.tick.tick_generator_integer
    port map(
      clock_i => s_clk,
      reset_n_i => s_resetn,
      period_m1_i => tick_divisor,
      tick_o => tick_s
      );
 
  stim: process
    variable check_status : boolean := false;
    variable pass_count, fail_count : integer := 0;
  begin

    nsl_amba.axi4_stream.frame_queue_init(cmd_q);
    nsl_amba.axi4_stream.frame_queue_init(rsp_q);

    -- Let FSM reach IDLE
    wait for 50 ns;

    nsl_simulation.logging.log(
      level => nsl_simulation.logging.LOG_LEVEL_INFO,
      message => "======================================",
      color => nsl_simulation.logging.LOG_COLOR_CYAN
    );
    nsl_simulation.logging.log(
      level => nsl_simulation.logging.LOG_LEVEL_INFO,
      message => "SPI CBOR TRANSACTOR TEST SUITE",
      color => nsl_simulation.logging.LOG_COLOR_CYAN
    );
    nsl_simulation.logging.log(
      level => nsl_simulation.logging.LOG_LEVEL_INFO,
      message => "======================================",
      color => nsl_simulation.logging.LOG_COLOR_CYAN
    );

    -- Test 1: Write to RAM with mode 0 (CS0)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"84820000c9430b0000c942aa33f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Write to RAM with mode 0: address 0x00, data 0xaa33", check_status, pass_count, fail_count);
    
    wait for 10*clock_period;
    
    -- Test 2: Read from RAM with mode 0 (CS0)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"84820000c943030000c810f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000233aaff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Read from RAM with mode 0: address 0x00, expected data 0xaa33", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 3: Write to RAM with mode 1 (CS1)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"84820101c9430b0000c942aa33f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Write to RAM with mode 1: address 0x00, data 0xaa33", check_status, pass_count, fail_count);
    
    wait for 10*clock_period;
    
    -- Test 4: Read from RAM with mode 1 (CS1)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"84820101c943030000c810f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000233aaff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Read from RAM with mode 1: address 0x00, expected data 0xaa33", check_status, pass_count, fail_count);

    wait for 10*clock_period;


    -- Test 5: Write to RAM with mode 2 (CS2)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"84820202c9430b0000c942aa33f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Write to RAM with mode 2: address 0x00, data 0xaa33", check_status, pass_count, fail_count);
    
    wait for 10*clock_period;
    
    -- Test 6: Read from RAM with mode 2 (CS2)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"84820202c943030000c810f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000233aaff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Read from RAM with mode 2: address 0x00, expected data 0xaa33", check_status, pass_count, fail_count);

    wait for 10*clock_period;


    -- Test 7: Write to RAM with mode 3 (CS3)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"84820303c9430b0000c942aa33f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Write to RAM with mode 3: address 0x00, data 0xaa33", check_status, pass_count, fail_count);
    
    wait for 10*clock_period;
    
    -- Test 8: Read from RAM with mode 3 (CS3)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"84820303c943030000c810f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000233aaff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Read from RAM with mode 3: address 0x00, expected data 0xaa33", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 9: minus with bstr in the loopback mode
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83820400c54155f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000102ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Test 'minus' command", check_status, pass_count, fail_count);

    wait for 10*clock_period;
    
    -- Test 10: shift_no_miso with minus (checked in waveform)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83820400c9c241fff6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Test 'minus' command with no MISO", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 11: Full byte shift with MISO capture on loopback (CS4)
    -- Command: select CS4 mode 0, shift 0xaa, unselect
    -- 83 = array(3), 82 04 00 = [4, 0], 41 aa = bstr(0xaa), f6 = null
    -- Loopback returns same data
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"8382040041aaf6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f590001aaff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Full byte shift with MISO on loopback", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 12: SPI Mode 1 (CPOL=0, CPHA=1) on loopback
    -- 83 = array(3), 82 04 01 = [4, 1], 41 55 = bstr(0x55), f6 = null
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"838204014155f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000155ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("SPI Mode 1 shift on loopback", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 13: SPI Mode 2 (CPOL=1, CPHA=0) on loopback
    -- 83 = array(3), 82 04 02 = [4, 2], 41 33 = bstr(0x33), f6 = null
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"838204024133f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000133ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("SPI Mode 2 shift on loopback", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 14: SPI Mode 3 (CPOL=1, CPHA=1) on loopback
    -- 83 = array(3), 82 04 03 = [4, 3], 41 cc = bstr(0xcc), f6 = null
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"8382040341ccf6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f590001ccff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("SPI Mode 3 shift on loopback", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 15: Shift minus-1 (#6.1 = c1) on loopback - shift 7 bits
    -- 83 = array(3), 82 04 00 = [4, 0], c1 41 aa = tag1(bstr(0xaa)), f6 = null
    -- 0xaa = 10101010, shift 7 bits = 1010101 = 0x55
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83820400c141aaf6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000155ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Shift minus-1 on loopback (7 bits)", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 16: Shift minus-2 (#6.2 = c2) on loopback - shift 6 bits of last byte
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83820400c242fffff6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f590002ff3fff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Shift minus-2 on loopback (6 bits)", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 17: Shift minus-3 (#6.3 = c3) on loopback - shift 5 bits
    -- 0xf0 = 11110000, shift 5 bits = 11110 = 0x1e
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"9f820400c341f0f6ff"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f5900011eff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Shift minus-3 on loopback (5 bits)", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 18: Shift minus-4 (#6.4 = c4) on loopback - shift 4 bits
    -- 0xab = 10101011, shift 4 bits = 1010 = 0x0a
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83820400c441abf6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f5900010aff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Shift minus-4 on loopback (4 bits)", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 19: Shift minus-6 (#6.6 = c6) on loopback - shift 2 bits
    -- 0xc0 = 11000000, shift 2 bits = 11 = 0x03
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83820400c641c0f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000103ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Shift minus-6 on loopback (2 bits)", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 20: Shift minus-7 (#6.7 = c7) on loopback - shift 1 bit
    -- 0x80 = 10000000, shift 1 bit = 1 = 0x01
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83820400c74180f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000101ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Shift minus-7 on loopback (1 bit)", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 21: Pause command (#6.10 = ca) between operations with very small wait
    -- 85 = array(5): select, shift, pause(6 ticks), shift, unselect
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"858204004112ca064134f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f5900011259000134ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Pause between shifts on loopback", check_status, pass_count, fail_count);

    -- Test 22: Pause command (#6.10 = ca) between operations
    -- 85 = array(5): select, shift, pause(50 ticks), shift, unselect
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"858204004112ca18324134f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f5900011259000134ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Pause between shifts on loopback", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 23: Multi-byte shift on loopback
    -- 83 = array(3), 82 04 00 = [4, 0], 43 aabbcc = bstr(3 bytes), f6 = null
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"8382040043aabbccf6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f590003aabbccff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Multi-byte shift on loopback", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 24: Back-to-back shifts without unselect
    -- 84 = array(4), select, shift1, shift2, unselect
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"8482040041114122f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f5900011159000122ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Back-to-back shifts on loopback", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 25: Multi-CS operation: CS0 write then CS4 loopback
    -- 86 = array(6): select CS0, write no-miso, unselect, select CS4, shift, unselect
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"86820000c9430b0001f68204004177f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000177ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Multi-CS: write to RAM then loopback", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 26: Pause command with long delay (#6.10 = ca with 2-byte uint)
    -- 84 = array(4): select CS4, shift, pause(1000 ticks = 0x03e8), shift, unselect
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"858204004156ca1903e84178f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f5900015659000178ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*5000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Long pause (1000 ticks) between shifts", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 27: Write with no MISO followed by write with MISO
    -- 84 = array(4): select CS4, no-miso shift, regular shift, unselect
    -- c9 41 aa = #6.9(bstr(0xaa)) - no MISO capture
    -- 41 bb = bstr(0xbb) - with MISO capture (loopback returns 0xbb)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"84820400c941aa41bbf6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f590001bbff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("No-MISO shift then MISO shift", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 28: Mode change while CS is selected (mode 0 -> mode 1)
    -- 85 = array(5): select CS4 mode0, shift, select CS4 mode1, shift, unselect
    -- Note: Re-selecting same CS with different mode changes SPI timing mid-transaction
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"858204004199820401419af6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f590001995900019aff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Mode change while CS selected (mode0->mode1)", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 29: Tag=8 shift_cycles with non-multiple-of-8 (#6.8(12) = shift 12 bits, no MOSI)
    -- Tag=8 shifts N bits without MOSI data - MOSI stays at 0, loopback returns 0s
    -- Response: 2 bytes (ceiling(12/8)), last byte masked to 4 bits (bits 3-0)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83820400c80cf6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f5900020000ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Tag=8 shift_cycles 12 bits (non-multiple of 8)", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 30: Tag=8 shift_cycles with small count < 8 (#6.8(5) = shift 5 bits)
    -- Tag=8 shifts 5 bits without MOSI, loopback returns 0s masked to 5 bits
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83820400c805f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000100ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Tag=8 shift_cycles 5 bits (< 8)", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    -- Test 31: Tag=8 shift_cycles with exactly 8 bits (boundary case)
    -- Exactly 8 bits = 1 full byte, no masking needed
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83820400c808f6"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000100ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Tag=8 shift_cycles 8 bits (exact byte)", check_status, pass_count, fail_count);

    wait for 10*clock_period;

    nsl_simulation.logging.log_test_suite_summary("SPI CBOR TRANSACTOR TESTS", pass_count, fail_count);

    if fail_count > 0 then
      nsl_simulation.control.terminate(1);
    else
      nsl_simulation.control.terminate(0);
    end if;
  end process;

  cmd_queue: process
  begin
    -- Let FSM reach IDLE and queues be initialized
    wait for 70 ns;
    nsl_simulation.logging.log(level => nsl_simulation.logging.LOG_LEVEL_INFO, message => "Going to run frame_queue_master", color => nsl_simulation.logging.LOG_COLOR_MAGENTA);
    nsl_amba.axi4_stream.frame_queue_master(cfg => cfg_c, root => cmd_q, clock => s_clk,
                                            stream_i => s_cmd.s, stream_o => s_cmd.m, dt => clock_period);    
  end process;
  
  rsp_queue: process
  begin
    -- Let FSM reach IDLE and queues be initialized
    wait for 70 ns;
    nsl_simulation.logging.log(level => nsl_simulation.logging.LOG_LEVEL_INFO, message => "Going to run frame_queue_slave", color => nsl_simulation.logging.LOG_COLOR_CYAN);
    nsl_amba.axi4_stream.frame_queue_slave(cfg => cfg_c, root => rsp_q, clock => s_clk,
                                           stream_i => s_rsp.m, stream_o => s_rsp.s, dt => clock_period);   
  end process;

end architecture;
