library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking;

entity interdomain_fifo_slice is
  generic(
    data_width_c   : integer
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic_vector(0 to 1);

    out_data_o  : out std_ulogic_vector(data_width_c-1 downto 0);
    out_ready_i : in  std_ulogic;
    out_valid_o : out std_ulogic;

    in_data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
    in_valid_i : in  std_ulogic;
    in_ready_o : out std_ulogic
    );
end entity;

architecture beh of interdomain_fifo_slice is

  subtype data_t is std_ulogic_vector(data_width_c-1 downto 0);
  
  signal i2o_data_in_s, i2o_data_out_s : data_t;
  signal i2o_toggle_in_s, i2o_toggle_out_s : std_ulogic;
  signal o2i_toggle_in_s, o2i_toggle_out_s : std_ulogic;
  
  signal reset_n_s : std_ulogic_vector(0 to 1);

begin

  reset_sync: nsl_clocking.async.async_multi_reset
    generic map(
      domain_count_c => 2,
      debounce_count_c => 5
      )
    port map(
      clock_i => clock_i,
      master_i => reset_n_i,
      slave_o => reset_n_s
      );

  in_side: block is
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_WAIT
      );

    type regs_t is
    record
      state : state_t;
      toggle: std_ulogic;
      data : data_t;
    end record;

    signal r, rin : regs_t;
  begin
    regs: process(clock_i(0), reset_n_s(0))
    begin
      if rising_edge(clock_i(0)) then
        r <= rin;
      end if;

      if reset_n_s(0) = '0' then
        r.state <= ST_RESET;
        r.toggle <= '0';
      end if;
    end process;

    transition: process(r, in_data_i, in_valid_i, o2i_toggle_in_s)
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          if in_valid_i = '1' then
            rin.state <= ST_WAIT;
            rin.data <= in_data_i;
            rin.toggle <= not r.toggle;
          end if;

        when ST_WAIT =>
          if o2i_toggle_in_s = r.toggle then
            rin.state <= ST_IDLE;
          end if;
      end case;
    end process;

    i2o_data_in_s <= r.data;
    i2o_toggle_in_s <= r.toggle;
    in_ready_o <= '1' when r.state = ST_IDLE else '0';
  end block;

  in2out: block is
  begin
    toggle: nsl_clocking.interdomain.interdomain_reg
      generic map(
        cycle_count_c => 2,
        data_width_c => 1
        )
      port map(
        clock_i => clock_i(1),
        data_i(0) => i2o_toggle_in_s,
        data_o(0) => i2o_toggle_out_s
        );

    data: nsl_clocking.async.async_sampler
      generic map(
        data_width_c => data_t'length
        )
      port map(
        clock_i => clock_i(1),
        data_i => i2o_data_in_s,
        data_o => i2o_data_out_s
        );
  end block;

  out2in: block is
  begin
    toggle: nsl_clocking.interdomain.interdomain_reg
      generic map(
        cycle_count_c => 2,
        data_width_c => 1
        )
      port map(
        clock_i => clock_i(0),
        data_i(0) => o2i_toggle_out_s,
        data_o(0) => o2i_toggle_in_s
        );
  end block;
  
  out_side: block is
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_WAIT
      );

    type regs_t is
    record
      state : state_t;
      toggle : std_ulogic;
      data : data_t;
    end record;
    
    signal r, rin: regs_t;
  begin
    regs: process(clock_i(1), reset_n_s(1))
    begin
      if rising_edge(clock_i(1)) then
        r <= rin;
      end if;

      if reset_n_s(1) = '0' then
        r.state <= ST_RESET;
        r.toggle <= '0';
      end if;
    end process;

    transition: process(r, i2o_data_out_s, i2o_toggle_out_s, out_ready_i)
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          if i2o_toggle_out_s /= r.toggle then
            rin.state <= ST_WAIT;
            rin.data <= i2o_data_out_s;
          end if;

        when ST_WAIT =>
          if out_ready_i = '1' then
            rin.state <= ST_IDLE;
            rin.toggle <= not r.toggle;
          end if;
      end case;
    end process;

    o2i_toggle_out_s <= r.toggle;
    out_valid_o <= '1' when r.state = ST_WAIT else '0';
    out_data_o <= r.data;
  end block;
end architecture;
