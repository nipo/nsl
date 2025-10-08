library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, nsl_logic;
use nsl_data.bytestream.all;
use nsl_amba.axi4_stream.all;
use nsl_amba.stream_traffic.all;
use nsl_data.prbs.all;
use nsl_logic.bool.to_logic;

entity stream_error_inserter is
  generic(
    config_c : config_t;
    probability_denom_l2_c : natural range 1 to 31 := 7;
    probability_c : real := 0.95;
    mode_c : string := "RANDOM";
    mtu_c : integer := 1500
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    insert_error_i : in boolean := false;
    byte_index_i : in integer range 0 to config_c.data_width := 0;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t;

    feed_back_o : out error_feedback_t
    );
end entity;

architecture beh of stream_error_inserter is

  subtype probability_t is unsigned(probability_denom_l2_c-1 downto 0);
  subtype error_byte_index_t is unsigned(nsl_math.arith.log2(config_c.data_width)-1 downto 0);
  constant probability_threshold_c : probability_t := to_unsigned(integer(probability_c * 2.0 ** probability_denom_l2_c), probability_t'length);
  constant data_width_l2 : integer := nsl_math.arith.log2(config_c.data_width);

  function byte_error_inserter(data : byte_string; insert_error : boolean; index_error : error_byte_index_t) return byte_string
  is
    variable data_v : byte_string(data'range) := data;
  begin
    if insert_error then
        if index_error'length > 0 then
            data_v(to_integer(index_error))(0) := 
                not data(to_integer(index_error))(0);
            return data_v;
        else -- Case data_width = 1
            data_v(0)(0) := 
                not data(0)(0);
            return data_v;
        end if;
    end if;
    return data_v;
  end function;

  function imin(a, b : integer) return integer is
  begin
      if a < b then
          return a;
      else
          return b;
      end if;
  end function;

  type regs_t is
  record
    prbs : prbs_state(30 downto 0);
    insert_error: boolean;
    error_beat_byte_index : error_byte_index_t;
    pkt_byte_index, error_pkt_byte_index : integer range 0 to mtu_c+config_c.data_width;
    frm_cnt : integer;
  end record;

  signal r, rin: regs_t;

begin

    regs: process(clock_i, reset_n_i) is
    begin
        if rising_edge(clock_i) then
            r <= rin;
        end if;
        if reset_n_i = '0' then
            r.prbs <=  x"deedbee"&"111";
            r.insert_error <= false;
            r.error_beat_byte_index <= (others => '0');
            r.pkt_byte_index <= 0;
            r.error_pkt_byte_index <= 0;
            r.frm_cnt <= 0;
        end if;
    end process;
    
    transition: process(r, in_i, out_i, insert_error_i, byte_index_i) is
        variable probability_v: probability_t;
        variable error_beat_byte_index_v : error_byte_index_t;
    begin
        rin <= r;

        probability_v := unsigned(prbs_bit_string(r.prbs, prbs31, probability_v'length));
        error_beat_byte_index_v := probability_v(data_width_l2-1 downto 0);

        if is_valid(config_c, in_i) then
            if is_ready(config_c, out_i) then
                rin.pkt_byte_index <= r.pkt_byte_index + config_c.data_width;
                rin.insert_error <= false;
                if mode_c = "RANDOM" then
                    if is_ready(config_c, out_i) then 
                        rin.prbs <= prbs_forward(r.prbs, prbs31, probability_v'length);
                        if probability_v <= probability_threshold_c then
                            rin.error_beat_byte_index <= error_beat_byte_index_v;
                            if not is_last(config_c, in_i) then -- Test if next cycle has data
                                rin.error_pkt_byte_index <= imin(r.pkt_byte_index + config_c.data_width + to_integer(error_beat_byte_index_v), mtu_c);
                                rin.insert_error <= true;
                            end if;
                        end if;
                    end if;
                else
                    if not is_last(config_c, in_i) then -- Test if next cycle has data
                        rin.insert_error <= insert_error_i;
                        rin.error_pkt_byte_index <= imin(r.pkt_byte_index + config_c.data_width + byte_index_i, mtu_c);
                        rin.error_beat_byte_index <= to_unsigned(byte_index_i, r.error_beat_byte_index'length);
                    end if;
                end if;
            end if;
        end if;
        --
        if is_valid(config_c, in_i) then
            if is_ready(config_c, out_i) then
                if is_last(config_c, in_i) then
                    rin.error_pkt_byte_index <= 0;
                    rin.pkt_byte_index <= 0;
                    rin.frm_cnt <= r.frm_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    assert_proc: process(clock_i) is
    begin
        if rising_edge(clock_i) then
            assert mode_c = "RANDOM" or mode_c = "MANUAL"
            report "ERROR: Mode must be MANUAL or RANDOM."
            severity failure;
            --
            assert mtu_c mod 2 = 0
            report "ERROR: Bus must be a multiple of 2."
            severity failure;
            --
            assert r.error_pkt_byte_index <= mtu_c 
            report "ERROR: byte index cannot be supp to mtu."
            severity failure;
            --
            assert r.pkt_byte_index <= mtu_c 
            report "ERROR: Number of bytes cannot be supp to mtu."
            severity failure;
        end if;
    end process;

    out_o <= transfer(cfg => config_c, 
                      bytes => byte_error_inserter(bytes(config_c, in_i), r.insert_error, r.error_beat_byte_index),
                      keep => keep(config_c, in_i),
                      last => is_last(config_c, in_i),
                      valid => is_valid(config_c, in_i));

    in_o <= accept(config_c, is_ready(config_c, out_i));

    feed_back_o.error <= to_logic(r.insert_error) when is_valid(config_c, in_i) and 
                                                       is_ready(config_c, out_i) and
                                                       keep(config_c, in_i)(to_integer(r.error_beat_byte_index)) = '1' else'0';

    feed_back_o.pkt_index_ko <= to_unsigned(r.error_pkt_byte_index,feed_back_o.pkt_index_ko'length);

end architecture;
