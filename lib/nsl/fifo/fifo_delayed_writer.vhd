library ieee;
use ieee.std_logic_1164.all;

entity fifo_delayed_writer is
  generic(
    width : integer;
    latency    : natural range 1 to 8
    );
  port(
    p_resetn            : in  std_ulogic;
    p_clk               : in  std_ulogic;

    p_in_data           : in  std_ulogic_vector(width-1 downto 0);
    p_in_valid          : in  std_ulogic;
    p_in_ready          : out std_ulogic;

    p_out_data          : out std_ulogic_vector(width-1 downto 0);
    p_out_ready_delayed : in  std_ulogic;
    p_out_valid         : out std_ulogic
    );
end fifo_delayed_writer;

architecture rtl of fifo_delayed_writer is

  type data_t is
  record
    data: std_ulogic_vector(width-1 downto 0);
    valid: std_ulogic;
  end record;

  type pipe_vector is array(natural range <>) of data_t;

  type state_t is (
    ST_RESET,
    ST_PASSTHROUGH,
    ST_BLOCKED,
    ST_FLUSH,
    ST_FLUSH_GATHER
    );

  type regs_t is
  record
    state : state_t;
    delay_line : pipe_vector(0 to latency-1);
    flush_count : natural range 0 to latency - 1;
  end record;

  signal r, rin: regs_t;

  signal s_valid : std_ulogic_vector(0 to latency-1);

  signal s_busy : boolean;

begin

  outputs: process(r, p_in_data, p_in_valid, p_out_ready_delayed)
  begin
    case r.state is
      when ST_RESET =>
        p_out_data <= (others => '-');
        p_out_valid <= '0';
        p_in_ready <= '0';

      when ST_PASSTHROUGH =>
        p_out_data <= p_in_data;
        p_out_valid <= p_in_valid and p_out_ready_delayed;
        p_in_ready <= p_out_ready_delayed;

      when ST_BLOCKED | ST_FLUSH_GATHER =>
        p_out_data <= (others => '-');
        p_out_valid <= '0';
        p_in_ready <= '0';

      when ST_FLUSH =>
        p_out_data <= r.delay_line(0).data;
        p_out_valid <= r.delay_line(0).valid;
        p_in_ready <= '0';
    end case;
  end process;

  valid: for i in r.delay_line'range
  generate
    s_valid(i) <= r.delay_line(i).valid;
  end generate;

  s_busy <= s_valid /= (s_valid'range => '0');

  regs: process(p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_in_valid, p_in_data, p_out_ready_delayed, s_busy)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_BLOCKED;
        clr: for i in r.delay_line'range
        loop
          rin.delay_line(i).valid <= '0';
        end loop;

      when ST_PASSTHROUGH =>
        -- blocking state
        if p_out_ready_delayed = '0' then
          rin.state <= ST_BLOCKED;
        else
          -- delay line
          rin.delay_line(0 to latency-2) <= r.delay_line(1 to latency-1);
          rin.delay_line(latency-1).valid <= p_in_valid;
          rin.delay_line(latency-1).data <= p_in_data;
        end if;

      when ST_BLOCKED =>
        if p_out_ready_delayed = '1' then
          if s_busy then
            rin.state <= ST_FLUSH;
            rin.flush_count <= latency-1;
          else
            rin.state <= ST_PASSTHROUGH;
          end if;
        end if;

      when ST_FLUSH =>
        rin.delay_line(0 to latency-2) <= r.delay_line(1 to latency-1);
        rin.delay_line(latency-1) <= r.delay_line(0);

        if r.flush_count /= 0 then
          rin.flush_count <= r.flush_count - 1;
        else
          rin.flush_count <= latency-1;
          rin.state <= ST_FLUSH_GATHER;
        end if;

      when ST_FLUSH_GATHER =>
        rin.delay_line(0 to latency-2) <= r.delay_line(1 to latency-1);
        rin.delay_line(latency-1).data <= r.delay_line(0).data;
        rin.delay_line(latency-1).valid <= r.delay_line(0).valid and not p_out_ready_delayed;

        if r.flush_count /= 0 then
          rin.flush_count <= r.flush_count - 1;
        else
          rin.state <= ST_BLOCKED;
        end if;

    end case;
  end process;

end rtl;
