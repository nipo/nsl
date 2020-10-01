library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory, nsl_axi;

entity axi_fifo16_ep is
  generic(
    master_buffer_depth: natural range 4 to 4096;
    slave_buffer_depth: natural range 4 to 4096
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic := '1';
    
    axi_i: in nsl_axi.axi4_lite.a32_d32_ms;
    axi_o: out nsl_axi.axi4_lite.a32_d32_sm;

    axis_m_i: in nsl_axi.stream.axis_16l_sm;
    axis_m_o: out nsl_axi.stream.axis_16l_ms;

    axis_s_i: in nsl_axi.stream.axis_16l_ms;
    axis_s_o: out nsl_axi.stream.axis_16l_sm
    );
begin

end entity;

architecture rtl of axi_fifo16_ep is

  signal s_axi_write, s_axi_read, s_axi_wready : std_ulogic;
  signal s_axi_addr : unsigned(3 downto 2);
  signal s_axi_wdata, s_axi_rdata : std_ulogic_vector(31 downto 0);

  signal to_master_buffer, from_slave_buffer: nsl_axi.stream.axis_16l;
  signal slave_available : integer range 0 to master_buffer_depth+1;
  signal master_free : integer range 0 to slave_buffer_depth;

begin

  master_buffer: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 17,
      word_count_c => master_buffer_depth,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,

      out_data_o(15 downto 0) => axis_m_o.tdata,
      out_data_o(16) => axis_m_o.tlast,
      out_ready_i => axis_m_i.tready,
      out_valid_o => axis_m_o.tvalid,

      in_data_i(15 downto 0) => to_master_buffer.m2s.tdata,
      in_data_i(16) => to_master_buffer.m2s.tlast,
      in_valid_i => to_master_buffer.m2s.tvalid,
      in_ready_o => to_master_buffer.s2m.tready,
      in_free_o => master_free
      );

  slave_buffer: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 17,
      word_count_c => slave_buffer_depth,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,

      out_data_o(15 downto 0) => from_slave_buffer.m2s.tdata,
      out_data_o(16) => from_slave_buffer.m2s.tlast,
      out_ready_i => from_slave_buffer.s2m.tready,
      out_valid_o => from_slave_buffer.m2s.tvalid,
      out_available_o => slave_available,

      in_data_i(15 downto 0) => axis_s_i.tdata,
      in_data_i(16) => axis_s_i.tlast,
      in_valid_i => axis_s_i.tvalid,
      in_ready_o => axis_s_o.tready
      );
  
  axi_slave: nsl_axi.axi4_lite.axi4_lite_a32_d32_slave
    generic map(
      addr_size => s_axi_addr'length + 2
      )
    port map(
      aclk => clock_i,
      aresetn => reset_n_i,

      p_axi_ms => axi_i,
      p_axi_sm => axi_o,

      p_addr => s_axi_addr,

      p_w_data => s_axi_wdata,
      p_w_ready => s_axi_wready,
      p_w_valid => s_axi_write,

      p_r_data => s_axi_rdata,
      p_r_ready => s_axi_read,
      p_r_valid => '1'
      );

  mealy: process(s_axi_wdata, s_axi_read, s_axi_write, s_axi_addr,
                 from_slave_buffer.m2s, to_master_buffer.s2m,
                 slave_available, master_free)
  begin
    to_master_buffer.m2s.tdata <= (others => '-');
    to_master_buffer.m2s.tlast <= '-';
    to_master_buffer.m2s.tvalid <= '0';
    from_slave_buffer.s2m.tready <= '0';
    s_axi_wready <= '0';
    s_axi_rdata <= (others => '0');

    case s_axi_addr is
      when "00" =>
        -- POP
        s_axi_rdata(15 downto 0) <= from_slave_buffer.m2s.tdata;
        s_axi_rdata(30) <= from_slave_buffer.m2s.tlast;
        s_axi_rdata(31) <= from_slave_buffer.m2s.tvalid;
        from_slave_buffer.s2m.tready <= s_axi_read;

      when "01" =>
        -- PUSH
        to_master_buffer.m2s.tdata <= s_axi_wdata(15 downto 0);
        to_master_buffer.m2s.tlast <= s_axi_wdata(30);
        to_master_buffer.m2s.tvalid <= s_axi_wdata(31) and s_axi_write;
        s_axi_wready <= to_master_buffer.s2m.tready;

      when "10" =>
        -- IN status
        s_axi_rdata(12 downto 0) <= std_ulogic_vector(to_unsigned(slave_available, 13));
        s_axi_rdata(30) <= from_slave_buffer.m2s.tlast;
        s_axi_rdata(31) <= from_slave_buffer.m2s.tvalid;

      when "11" =>
        -- OUT status
        s_axi_rdata(12 downto 0) <= std_ulogic_vector(to_unsigned(master_free, 13));
        s_axi_rdata(31) <= to_master_buffer.s2m.tready;
    end case;
  end process;
        
end architecture;
