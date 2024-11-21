library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity committed_statistics is
  generic(
    interframe_saturate_c : boolean := false
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    req_i : in work.committed.committed_req_t;
    ack_i : in work.committed.committed_ack_t;

    frame_ok_o : out std_ulogic;
    interframe_count_o : out unsigned;
    flit_count_o : out unsigned;
    pause_count_o : out unsigned;
    backpressure_count_o : out unsigned;

    valid_o : out std_ulogic
    );
end entity;

architecture beh of committed_statistics is

  type regs_t is
  record
    frame_started : boolean;
    interframe_count: unsigned(interframe_count_o'length-1 downto 0);
    flit_count: unsigned(flit_count_o'length-1 downto 0);
    pause_count: unsigned(pause_count_o'length-1 downto 0);
    backpressure_count: unsigned(backpressure_count_o'length-1 downto 0);
  end record;
  
  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.frame_started <= false;
      r.interframe_count <= (others => '0');
      r.flit_count <= (others => '0');
      r.pause_count <= (others => '0');
      r.backpressure_count <= (others => '0');
    end if;
  end process;

  transition: process(r, req_i, ack_i) is
  begin
    rin <= r;

    if not r.frame_started then
      if req_i.valid = '0' then
        if not interframe_saturate_c or r.interframe_count /= (r.interframe_count'range => '1') then
          rin.interframe_count <= r.interframe_count + 1;
        end if;
      else
        rin.frame_started <= true;
      end if;
    end if;

    if req_i.valid = '0' then
      if r.frame_started then
        rin.pause_count <= r.pause_count + 1;
      end if;
    elsif ack_i.ready = '0' then
      rin.backpressure_count <= r.backpressure_count + 1;
    elsif req_i.last = '1' then
      rin.interframe_count <= (others => '0');
      rin.flit_count <= (others => '0');
      rin.pause_count <= (others => '0');
      rin.backpressure_count <= (others => '0');
      rin.frame_started <= false;
    else
      rin.flit_count <= r.flit_count + 1;
    end if;
  end process;

  interframe_count_o <= r.interframe_count;
  flit_count_o <= r.flit_count;
  pause_count_o <= r.pause_count;
  backpressure_count_o <= r.backpressure_count;
  valid_o <= req_i.valid and req_i.last and ack_i.ready;
  frame_ok_o <= req_i.data(0);
  
end architecture;
