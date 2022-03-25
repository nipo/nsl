library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_math;
use nsl_bnoc.framed.all;

entity framed_funnel is
  generic(
    source_count_c : natural
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    enable_i : in std_ulogic := '1';
    selected_o  : out natural range 0 to source_count_c - 1;
    
    in_i   : in framed_req_array(0 to source_count_c - 1);
    in_o   : out framed_ack_array(0 to source_count_c - 1);

    out_o   : out framed_req;
    out_i   : in framed_ack
    );
end entity;

architecture rtl of framed_funnel is

  type state_t is (
    STATE_RESET,
    STATE_ELECT_FAIR,
    STATE_ELECT,
    STATE_FORWARD
    );

  type regs_t is record
    state : state_t;
    elected : natural range 0 to source_count_c - 1;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= STATE_RESET;
    end if;
  end process;

  transition: process(in_i, out_i, r, enable_i)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_ELECT;

      when STATE_ELECT_FAIR =>
        rin.state <= STATE_ELECT;
        if enable_i = '1' then
          for i in source_count_c - 1 downto 0 loop
            if in_i(i).valid = '1' and i /= r.elected then
              rin.elected <= i;
              rin.state <= STATE_FORWARD;
            end if;
          end loop;
        end if;

      when STATE_ELECT =>
        if enable_i = '1' then
          for i in source_count_c-1 downto 0 loop
            if in_i(i).valid = '1' then
              rin.elected <= i;
              rin.state <= STATE_FORWARD;
            end if;
          end loop;
        end if;

      when STATE_FORWARD =>
        if in_i(r.elected).valid = '1' and out_i.ready = '1' and in_i(r.elected).last = '1' then
          rin.state <= STATE_ELECT_FAIR;
        end if;
    end case;
  end process;

  mux: process(r, in_i, out_i)
  begin
    in_o <= (others => (ready => '0'));
    out_o.valid <= '0';
    out_o.data <= (others => '-');
    out_o.last <= '-';
    selected_o <= r.elected;

    case r.state is
      when STATE_FORWARD =>
        out_o <= in_i(r.elected);
        in_o(r.elected) <= out_i;

      when others =>
        null;
    end case;
  end process;
end architecture;
