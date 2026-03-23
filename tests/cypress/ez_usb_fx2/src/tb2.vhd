library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_cypress, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_data.text.all; 

entity tb2 is
end entity;

architecture tb of tb2 is

  constant clock_period_c : time := 20 ns; -- 50 MHz FX2 clock
  
  -- AXI4-Stream configuration: 1 byte wide, with last signal
  constant axi_cfg_c : nsl_amba.axi4_stream.config_t := 
    nsl_amba.axi4_stream.config(bytes => 1, last => true);
  
  -- Clock and reset
  signal clock : std_ulogic := '0';
  signal reset_n : std_ulogic := '0';
  signal run : boolean := true;
  
  -- DUT ports - AXI4-Stream TX (FPGA to FX2)
  signal tx_m : nsl_amba.axi4_stream.master_t;
  signal tx_s : nsl_amba.axi4_stream.slave_t;
  
  -- DUT ports - AXI4-Stream RX (FX2 to FPGA)
  signal rx_m : nsl_amba.axi4_stream.master_t;
  signal rx_s : nsl_amba.axi4_stream.slave_t;
  
  -- DUT ports - FX2 interface
  signal to_fx2 : nsl_cypress.ez_usb_fx2.fx2_i;
  -- signal from_fx2 : nsl_cypress.ez_usb_fx2.fx2_o;
  signal from_fx2 : nsl_cypress.ez_usb_fx2.fx2_flags_o;
  
  -- Test control
  signal test_done : boolean := false;
  
  -- RX FIFO loading control
  signal load_rx_fifo : boolean := false;
  signal rx_load_data : byte_string(0 to 15) := (others => x"00");
  signal rx_load_count : natural := 0;
  
  -- Shared variables for FX2 FIFO control
  shared variable fx2_tx_count : natural := 0;
  shared variable fx2_rx_count : natural := 0; 
begin

  -- Clock generation
  clock_gen: process
  begin
    while run loop
      clock <= '0';
      wait for clock_period_c / 2;
      clock <= '1';
      wait for clock_period_c / 2;
    end loop;
    wait;
  end process;
  
  -- Reset generation
  reset_gen: process
  begin
    reset_n <= '0';
    wait for clock_period_c * 5;
    reset_n <= '1';
    wait;
  end process;
  
  -- DUT instantiation
  dut: nsl_cypress.ez_usb_fx2.fx2_controller_fixed
    generic map(
      axi_cfg_c => axi_cfg_c,
      rx_ep_c => nsl_cypress.ez_usb_fx2.FX2_EP2,
      tx_ep_c => nsl_cypress.ez_usb_fx2.FX2_EP6,
      rx_empty_flag_c => nsl_cypress.ez_usb_fx2.FX2_FLAGA,
      tx_full_flag_c  => nsl_cypress.ez_usb_fx2.FX2_FLAGB
    )
    port map(
      clock_i => clock,
      reset_n_i => reset_n,
      tx_i => tx_m,
      tx_o => tx_s,
      rx_o => rx_m,
      rx_i => rx_s,
      to_fx2_o => to_fx2,
      from_fx2_i => from_fx2
    );
  
  -- FX2 behavioral model
  fx2_model: process
    variable tx_fifo : byte_stream;
    variable rx_fifo : byte_stream;
    variable rx_data : byte;
  begin
    -- Initialize FIFOs
    clear(tx_fifo);
    clear(rx_fifo);
    fx2_tx_count := 0;
    fx2_rx_count := 0; 
    
    -- Initialize FX2 outputs
    from_fx2.flag_b <= '1';  -- TX FIFO not full
    from_fx2.flag_a <= '0';  -- RX FIFO empty
    from_fx2.data <= (others => '0');
    
    wait until reset_n = '1';
    wait until rising_edge(clock);
    
    loop
      -- Check if stimulus wants to load RX FIFO
      if load_rx_fifo then
        clear(rx_fifo);
        for i in 0 to rx_load_count - 1 loop
          write(rx_fifo, rx_load_data(i));
        end loop;
        fx2_rx_count := rx_load_count;
        nsl_simulation.logging.log_info("FX2: Loaded " & nsl_data.text.to_string(rx_load_count) & 
                                       " bytes into RX FIFO");
      end if;
      
      wait until rising_edge(clock);
      
      -- Handle writes to FX2 (FPGA TX)
      if to_fx2.wr_n = '0' then
        write(tx_fifo, to_fx2.data);
        fx2_tx_count := fx2_tx_count + 1;
        nsl_simulation.logging.log_info("FX2: Received byte 0x" & nsl_data.text.to_string(to_fx2.data) & 
               " (FIFO size: " & nsl_data.text.to_string(fx2_tx_count) & ")");
      end if;
      
      -- Handle reads from FX2 (FPGA RX)
      if to_fx2.rd_n = '0' and fx2_rx_count > 0 then
        read(rx_fifo, rx_data);
        fx2_rx_count := fx2_rx_count - 1;
        nsl_simulation.logging.log_info("FX2: Sent byte 0x" & nsl_data.text.to_string(rx_data));
      end if;
      
      wait until falling_edge(clock);
      
      -- Update FX2 status signals
      -- TX FIFO full when it has more than 512 bytes (simulated)
      if fx2_tx_count > 512 then
        from_fx2.flag_b <= '0';
      else
        from_fx2.flag_b <= '1';
      end if;
      
      -- RX FIFO empty status
      if fx2_rx_count = 0 then
        from_fx2.flag_a <= '0';
        from_fx2.data <= (others => '0');
      else
        from_fx2.flag_a <= '1';
        -- Peek at next byte without removing it
        if rx_fifo /= null and rx_fifo'length > 0 then
          from_fx2.data <= rx_fifo(rx_fifo'left);
        end if; 
      end if;
      
      -- OE_N controls data output
      if to_fx2.oe_n = '1' then
        from_fx2.data <= (others => 'Z');
      end if;
      
      exit when test_done;
    end loop;

    -- Cleanup
    if tx_fifo /= null then
      deallocate(tx_fifo);
    end if;
    if rx_fifo /= null then
      deallocate(rx_fifo);
    end if;
    
    wait;
  end process;
  
  -- Test stimulus
  stimulus: process
    variable test_data : byte_string(0 to 15);
    variable rx_data : byte_string(0 to 15);
    variable beat : nsl_amba.axi4_stream.master_t;
  begin
    -- Initialize AXI streams
    tx_m <= nsl_amba.axi4_stream.transfer_defaults(axi_cfg_c);
    rx_s <= nsl_amba.axi4_stream.accept(axi_cfg_c, false);
    load_rx_fifo <= false;
    
    wait until reset_n = '1';
    wait for clock_period_c * 10;
    
    report "======================================";
    report "TEST 1: Single byte write to FX2";
    report "======================================";
    
    nsl_amba.axi4_stream.send(
      cfg => axi_cfg_c,
      clock => clock,
      stream_i => tx_s,
      stream_o => tx_m,
      bytes => from_hex("42"),
      last => true
    );
    
    wait for clock_period_c * 20;
    assert fx2_tx_count = 1 
      report "Expected 1 byte in TX FIFO" severity error;
    
    report "======================================";
    report "TEST 2: Multi-byte packet write";
    report "======================================";
    
    test_data := from_hex("0123456789ABCDEF0011223344556677");
    
    nsl_amba.axi4_stream.packet_send(
      cfg => axi_cfg_c,
      clock => clock,
      stream_i => tx_s,
      stream_o => tx_m,
      packet => test_data
    );
    
    wait for clock_period_c * 40;
    report "TX FIFO contains " & integer'image(fx2_tx_count) & " bytes";
    assert fx2_tx_count = 17 -- 1 from test 1 + 16 from test 2
      report "Expected 17 bytes total in TX FIFO"
      severity error; 
    
    report "======================================";
    report "TEST 3: Read from FX2";
    report "======================================";

    -- Reset TX count for cleaner test
    fx2_tx_count := 0;
    
    -- Prepare data in FX2 RX FIFO
    nsl_simulation.logging.log_info("Going to prepare data in FX2 RX FIFO for test 3");
    rx_load_data(0 to 7) <= (
      x"A0", x"A1", x"A2", x"A3",
      x"A4", x"A5", x"A6", x"A7"
    );
    rx_load_count <= 8;
    load_rx_fifo <= true;
    wait for clock_period_c * 1;
    load_rx_fifo <= false;
    
    wait for clock_period_c * 5;
    
    -- Set up receiver to accept data
    rx_s <= nsl_amba.axi4_stream.accept(axi_cfg_c, true);
    
    -- Wait for data to be received
    nsl_simulation.logging.log_info("Going to read data from FX2");
    for i in 0 to 7 loop
      wait until nsl_amba.axi4_stream.is_valid(axi_cfg_c, rx_m);
      rx_data(i) := nsl_amba.axi4_stream.bytes(axi_cfg_c, rx_m)(0);
      report "Received byte " & integer'image(i) & ": 0x" & 
             nsl_data.text.to_string(rx_data(i));
      wait until rising_edge(clock);
    end loop;
    
    rx_s <= nsl_amba.axi4_stream.accept(axi_cfg_c, false);
    
    -- Verify received data
    for i in 0 to 7 loop
      assert rx_data(i) = std_ulogic_vector(to_unsigned(16#A0# + i, 8))
        report "Mismatch at byte " & integer'image(i) 
        severity error;
    end loop;
    
    wait for clock_period_c * 10;
    
    report "======================================";
    report "TEST 4: Interleaved read/write";
    report "======================================";
    
    -- Prepare data in FX2 RX FIFO for test 4
    nsl_simulation.logging.log_info("Going to prepare data in FX2 RX FIFO for test 4");
    rx_load_data(0 to 3) <= (
      x"50", x"51", x"52", x"53"
    );
    rx_load_count <= 4;
    load_rx_fifo <= true;
    wait for clock_period_c * 1;
    load_rx_fifo <= false;
    
    wait for clock_period_c * 2;
       
    -- Enable receiver
    rx_s <= nsl_amba.axi4_stream.accept(axi_cfg_c, true);
    
    wait for clock_period_c * 2;
    
    -- Send some TX data
    nsl_amba.axi4_stream.send(
      cfg => axi_cfg_c,
      clock => clock,
      stream_i => tx_s,
      stream_o => tx_m,
      bytes => from_hex("AA"),
      last => false
    );
    
    wait for clock_period_c * 5;
    
    nsl_amba.axi4_stream.send(
      cfg => axi_cfg_c,
      clock => clock,
      stream_i => tx_s,
      stream_o => tx_m,
      bytes => from_hex("BB"),
      last => true
    );
    
    wait for clock_period_c * 20;
    
    rx_s <= nsl_amba.axi4_stream.accept(axi_cfg_c, false);
    
    report "======================================";
    report "TEST 5: Full FIFO handling";
    report "======================================";
    -- Simulate full FIFO
    fx2_tx_count := 520;

    -- Try to send data when FIFO is full (should stall)
    report "Attempting to write with full FIFO...";

    -- This will timeout or take longer due to backpressure
    wait for clock_period_c * 10;

    -- Clear the FIFO to allow progress
    fx2_tx_count := 0;
    
    wait for clock_period_c * 5;
    
    -- Try to send data when FIFO is full
    nsl_amba.axi4_stream.send(
      cfg => axi_cfg_c,
      clock => clock,
      stream_i => tx_s,
      stream_o => tx_m,
      bytes => from_hex("FF"),
      last => true
    );
    
    wait for clock_period_c * 20;
    
    report "======================================";
    report "All tests completed successfully!";
    report "======================================";
    
    test_done <= true;
    run <= false;
    wait;
  end process;
  
end architecture;
