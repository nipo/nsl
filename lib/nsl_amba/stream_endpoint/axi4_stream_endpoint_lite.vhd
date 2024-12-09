library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic;
use nsl_amba.stream_endpoint.all;
use nsl_amba.axi4_mm.all;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_logic.logic.all;
use nsl_logic.bool.all;

entity axi4_stream_endpoint_lite is
  generic (
    mm_config_c : nsl_amba.axi4_mm.config_t;
    stream_config_c : nsl_amba.axi4_stream.config_t;
    out_buffer_depth_c: natural range 4 to 4096;
    in_buffer_depth_c: natural range 4 to 4096
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    irq_n_o : out std_ulogic;

    mm_i : in nsl_amba.axi4_mm.master_t;
    mm_o : out nsl_amba.axi4_mm.slave_t;
    
    rx_i : in nsl_amba.axi4_stream.master_t;
    rx_o : out nsl_amba.axi4_stream.slave_t;
    
    tx_o : out nsl_amba.axi4_stream.master_t;
    tx_i : in nsl_amba.axi4_stream.slave_t
    );

begin

  assert mm_config_c.data_bus_width_l2 = 2
    report "Only a 32-bit data bus is supported on MM interface"
    severity failure;
  assert is_lite(mm_config_c)
    report "Only AXI4-Lite subset is allowed on MM interface"
    severity failure;
  assert (8 * (2**mm_config_c.data_bus_width_l2))
    > (8 * stream_config_c.data_width + 2)
    report "MM side is not large enough to hold "&to_string(stream_config_c.data_width)&" data bytes and handshake"
    severity failure;

end entity;

architecture beh of axi4_stream_endpoint_lite is

  signal reg_no_s: natural range 0 to 7;
  signal w_value_s, r_value_s : unsigned(31 downto 0);
  signal w_strobe_s, r_strobe_s : std_ulogic;

  signal in_data, in_status, out_status: unsigned(31 downto 0);
  constant irq_pad: unsigned(29 downto 0) := (others => '0');
  signal irq_state: std_ulogic_vector(1 downto 0);
  signal in_available_s : integer range 0 to out_buffer_depth_c+1;
  signal out_free_s : integer range 0 to in_buffer_depth_c;

  signal to_out_buffer_s, from_in_buffer_s: nsl_amba.axi4_stream.bus_t;
  
  type regs_t is
  record
    irq_mask : std_ulogic_vector(1 downto 0);
  end record;
  
  signal r, rin: regs_t;

  constant config_word : unsigned(31 downto 0)
    := to_unsigned(stream_config_c.data_width, 2)
    & to_unsigned(out_buffer_depth_c, 15)
    & to_unsigned(in_buffer_depth_c, 15);
  
begin

  writing: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.irq_mask <= (others => '0');
    end if;
  end process;

  transition: process(r, w_value_s, w_strobe_s, reg_no_s) is
  begin
    rin <= r;

    if w_strobe_s = '1' then
      case reg_no_s is
        when AXI4_STREAM_ENDPOINT_LITE_IRQ_MASK => rin.irq_mask <= std_ulogic_vector(w_value_s(rin.irq_mask'range));
        when others => null;
      end case;
    end if;
  end process;

  rx_rmap: process(from_in_buffer_s.m, to_out_buffer_s.s, in_available_s, out_free_s) is
  begin
    in_data <= (others => '0');
    in_data(stream_config_c.data_width * 8 - 1 downto 0) <= value(stream_config_c, from_in_buffer_s.m, endian => ENDIAN_LITTLE);
    in_data(30) <= to_logic(is_last(stream_config_c, from_in_buffer_s.m));
    in_data(31) <= to_logic(is_valid(stream_config_c, from_in_buffer_s.m));

    in_status <= (others => '0');
    in_status(12 downto 0) <= to_unsigned(in_available_s, 13);
    in_status(30) <= to_logic(is_last(stream_config_c, from_in_buffer_s.m));
    in_status(31) <= to_logic(is_valid(stream_config_c, from_in_buffer_s.m));

    out_status <= (others => '0');
    out_status(12 downto 0) <= to_unsigned(out_free_s, 13);
    out_status(31) <= to_logic(is_ready(stream_config_c, to_out_buffer_s.s));
  end process;

  from_in_buffer_s.s <= accept(stream_config_c,
                               ready => reg_no_s = AXI4_STREAM_ENDPOINT_LITE_IN_DATA and r_strobe_s = '1');

  to_out_buffer_s.m <= transfer(stream_config_c,
                                value => resize(w_value_s, 8 * stream_config_c.data_width),
                                endian => ENDIAN_LITTLE,
                                valid => reg_no_s = AXI4_STREAM_ENDPOINT_LITE_OUT_DATA and w_strobe_s = '1' and w_value_s(31) = '1',
                                last => w_value_s(30) = '1');

  irq_state(0) <= to_logic(is_valid(stream_config_c, from_in_buffer_s.m));
  irq_state(1) <= to_logic(is_ready(stream_config_c, to_out_buffer_s.s));

  irq_n_o <= not or_reduce(r.irq_mask and irq_state);
  
  with reg_no_s select r_value_s <=
    in_data                        when AXI4_STREAM_ENDPOINT_LITE_IN_DATA,
    in_status                      when AXI4_STREAM_ENDPOINT_LITE_IN_STATUS,
    out_status                     when AXI4_STREAM_ENDPOINT_LITE_OUT_STATUS,
    irq_pad & unsigned(irq_state)  when AXI4_STREAM_ENDPOINT_LITE_IRQ_STATE,
    irq_pad & unsigned(r.irq_mask) when AXI4_STREAM_ENDPOINT_LITE_IRQ_MASK,
    config_word                    when AXI4_STREAM_ENDPOINT_LITE_CONFIG,
    x"00000000"                    when others;

  regmap: nsl_amba.axi4_mm.axi4_mm_lite_regmap
    generic map(
      config_c => mm_config_c,
      reg_count_l2_c => 3
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      axi_i => mm_i,
      axi_o => mm_o,

      reg_no_o => reg_no_s,
      w_value_o => w_value_s,
      w_strobe_o => w_strobe_s,
      r_value_i => r_value_s,
      r_strobe_o => r_strobe_s
      );

  out_buffer: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => stream_config_c,
      depth_c => out_buffer_depth_c,
      clock_count_c => 1
      )
    port map(
      clock_i(0) => clock_i,
      reset_n_i => reset_n_i,

      in_i => to_out_buffer_s.m,
      in_o => to_out_buffer_s.s,
      in_free_o => out_free_s,

      out_o => tx_o,
      out_i => tx_i
      );

  in_buffer: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => stream_config_c,
      depth_c => in_buffer_depth_c,
      clock_count_c => 1
      )
    port map(
      clock_i(0) => clock_i,
      reset_n_i => reset_n_i,

      in_i => rx_i,
      in_o => rx_o,

      out_o => from_in_buffer_s.m,
      out_i => from_in_buffer_s.s,
      out_available_o => in_available_s
      );
  
end architecture;
