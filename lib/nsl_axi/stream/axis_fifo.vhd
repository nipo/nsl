library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory;

entity axis_fifo is
  generic(
    depth        : natural;
    data_bytes   : natural;
    tid_width    : natural := 0;
    tdest_width  : natural := 0;
    tuser_width  : natural := 0;
    clk_count    : natural range 1 to 2
    );
  port(
    aresetn     : in  std_ulogic;

    s_clk       : in std_ulogic;
    s_tvalid    : in std_ulogic;
    s_tready    : out std_ulogic;
    s_tdata     : in std_ulogic_vector(data_bytes * 8 - 1 downto 0);
    s_tstrb     : in std_ulogic_vector(data_bytes - 1 downto 0) := (data_bytes - 1 downto 0 => '1');
    s_keep      : in std_ulogic_vector(data_bytes - 1 downto 0) := (data_bytes - 1 downto 0 => '1');
    s_last      : in std_ulogic;
    s_tid       : in std_ulogic_vector(tid_width - 1 downto 0) := (tid_width - 1 downto 0 => '0');
    s_tdest     : in std_ulogic_vector(tdest_width - 1 downto 0) := (tdest_width - 1 downto 0 => '0');
    s_tuser     : in std_ulogic_vector(tuser_width - 1 downto 0) := (tuser_width - 1 downto 0 => '0');

    m_clk       : in std_ulogic := '-';
    m_tvalid    : out std_ulogic;
    m_tready    : in std_ulogic;
    m_tdata     : out std_ulogic_vector(data_bytes * 8 - 1 downto 0);
    m_tstrb     : out std_ulogic_vector(data_bytes - 1 downto 0);
    m_keep      : out std_ulogic_vector(data_bytes - 1 downto 0);
    m_last      : out std_ulogic;
    m_tid       : out std_ulogic_vector(tid_width - 1 downto 0);
    m_tdest     : out std_ulogic_vector(tdest_width - 1 downto 0);
    m_tuser     : out std_ulogic_vector(tuser_width - 1 downto 0);
    );
end entity;

architecture rtl axis_fifo is

  signal s_in_data, s_out_data : std_ulogic_vector(8 downto 0);

begin

  fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => depth,
      data_width_c => data_bytes * 8,
      clock_count_c => clk_count
      )
    port map(
      reset_n_i => p_resetn,
      clock_i => p_clk,
      out_data_o => s_out_data,
      out_ready_i => p_out_ack.ack,
      out_valid_o => p_out_val.val,
      in_data_i => s_in_data,
      in_valid_i => p_in_val.val,
      in_ready_o => p_in_ack.ack
      );

  s_in_data <= p_in_val.more & p_in_val.data;
  p_out_val.more <= s_out_data(8);
  p_out_val.data <= s_out_data(7 downto 0);

end architecture;
