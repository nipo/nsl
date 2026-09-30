library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ps7_axi3_wid_tracker is
  generic(
    id_width_c : positive;
    depth_c : positive
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    aw_valid_i : in std_ulogic;
    aw_id_i : in std_ulogic_vector(id_width_c-1 downto 0);
    aw_valid_o : out std_ulogic;
    aw_ready_i : in std_ulogic;
    aw_ready_o : out std_ulogic;

    w_valid_i : in std_ulogic;
    w_last_i : in std_ulogic;
    w_valid_o : out std_ulogic;
    w_ready_i : in std_ulogic;
    w_ready_o : out std_ulogic;
    w_id_o : out std_ulogic_vector(id_width_c-1 downto 0)
    );
end entity;

architecture beh of ps7_axi3_wid_tracker is

  subtype id_t is std_ulogic_vector(id_width_c-1 downto 0);
  type id_vector is array (natural range <>) of id_t;
  subtype ptr_t is integer range 0 to depth_c-1;

  type regs_t is
  record
    id: id_vector(0 to depth_c-1);
    wptr, rptr: ptr_t;
    count: integer range 0 to depth_c;
    -- A write data burst completed with the ID of the write address
    -- the master presents, before its handshake.
    w_ahead: boolean;
  end record;

  signal r, rin: regs_t;

  function next_ptr(p: ptr_t) return ptr_t
  is
  begin
    if p = depth_c - 1 then
      return 0;
    end if;
    return p + 1;
  end function;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.wptr <= 0;
      r.rptr <= 0;
      r.count <= 0;
      r.w_ahead <= false;
    end if;
  end process;

  transition: process(r, aw_valid_i, aw_id_i, aw_ready_i,
                      w_valid_i, w_last_i, w_ready_i) is
    variable aw_done, w_done, w_open: boolean;
  begin
    rin <= r;

    w_open := r.count /= 0 or (not r.w_ahead and aw_valid_i = '1');
    aw_done := r.count /= depth_c and aw_valid_i = '1' and aw_ready_i = '1';
    w_done := w_open and w_valid_i = '1' and w_ready_i = '1' and w_last_i = '1';

    if r.w_ahead then
      if aw_done then
        rin.w_ahead <= false;
      end if;
    elsif r.count = 0 and w_done and not aw_done then
      rin.w_ahead <= true;
    else
      if aw_done then
        rin.id(r.wptr) <= aw_id_i;
        rin.wptr <= next_ptr(r.wptr);
      end if;

      if w_done then
        rin.rptr <= next_ptr(r.rptr);
      end if;

      if aw_done and not w_done then
        rin.count <= r.count + 1;
      elsif w_done and not aw_done then
        rin.count <= r.count - 1;
      end if;
    end if;
  end process;

  mealy: process(r, aw_valid_i, aw_id_i, aw_ready_i, w_valid_i, w_ready_i) is
    variable not_full, w_open: std_ulogic;
  begin
    not_full := '0';
    if r.count /= depth_c then
      not_full := '1';
    end if;

    w_open := '0';
    if r.count /= 0 or (not r.w_ahead and aw_valid_i = '1') then
      w_open := '1';
    end if;

    aw_valid_o <= aw_valid_i and not_full;
    aw_ready_o <= aw_ready_i and not_full;
    w_valid_o <= w_valid_i and w_open;
    w_ready_o <= w_ready_i and w_open;
    if r.count /= 0 then
      w_id_o <= r.id(r.rptr);
    else
      w_id_o <= aw_id_i;
    end if;
  end process;

end architecture;
