library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory, nsl_math;
use nsl_math.arith.to_unsigned_auto;

entity delay_line_memory is
  generic(
    data_width_c : integer;
    cycles_c : integer
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i : in  std_ulogic;

    ready_o : out std_ulogic;
    valid_i : in  std_ulogic;
    data_i : in std_ulogic_vector(data_width_c-1 downto 0);
    data_o : out std_ulogic_vector(data_width_c-1 downto 0)
    );
end entity;

architecture beh of delay_line_memory is

  constant wrap_c: unsigned := to_unsigned_auto(cycles_c-1);

  type state_t is (
    ST_RESET,
    ST_CLEAR,
    ST_RUN
    );
  
  type regs_t is
  record
    state: state_t;
    waddr, raddr: unsigned(wrap_c'range);
    dout : std_ulogic_vector(data_i'range);
  end record;

  signal r, rin: regs_t;
  signal mem_wdata_s, mem_rdata_s: std_ulogic_vector(data_i'range);
  signal mem_wen_s: std_ulogic;
  
begin

  reg: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.waddr <= (others => '0');
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, valid_i, mem_rdata_s) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_CLEAR;
        rin.waddr <= (others => '0');
        rin.dout <= (others => '0');

      when ST_CLEAR =>
        if r.waddr = wrap_c then
          rin.waddr <= (others => '0');
          rin.raddr <= to_unsigned(1, rin.raddr'length);
          rin.state <= ST_RUN;
        else
          rin.waddr <= r.waddr + 1;
        end if;
        
      when ST_RUN =>
        if valid_i = '1' then
          rin.dout <= mem_rdata_s;
          rin.waddr <= r.raddr;
          if r.raddr = wrap_c then
            rin.raddr <= (others => '0');
          else
            rin.raddr <= r.raddr + 1;
          end if;
        end if;
    end case;
  end process;

  mealy: process(r, valid_i, data_i) is
  begin
    case r.state is
      when ST_RESET | ST_CLEAR =>
        mem_wdata_s <= (others => '0');
        mem_wen_s <= '1';
        ready_o <= '0';

      when ST_RUN =>
        mem_wdata_s <= data_i;
        mem_wen_s <= valid_i;
        ready_o <= '1';
    end case;
  end process;
  
  storage: nsl_memory.ram.ram_2p_r_w
    generic map(
      addr_size_c => wrap_c'length,
      data_size_c => data_i'length,
      clock_count_c => 1,
      registered_output_c => false
      )
    port map(
      clock_i(0) => clock_i,

      write_address_i => r.waddr,
      write_data_i => mem_wdata_s,
      write_en_i => mem_wen_s,

      read_address_i => r.raddr,
      read_data_o => mem_rdata_s,
      read_en_i => '1'
      );

  data_o <= r.dout;
  
end architecture;
