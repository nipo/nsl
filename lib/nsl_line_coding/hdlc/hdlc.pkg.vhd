library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_logic, nsl_bnoc;
use nsl_data.crc.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use nsl_data.endian.all;

package hdlc is

  -- HDLC frame format:
  -- - Flag,
  -- - Address byte,
  -- - Control byte,
  -- - Data,
  -- - FCS,
  -- - Flag.

  -- Line data is escaped when characters match flag, escape, ETX (0x03), XON,
  -- XOFF, XON*, XOFF* (XON/XOFF with high bit set). Escaped character has bit
  -- 5 toggled.

  constant flag_c : byte := x"7e";
  constant escape_byte_c : byte := x"7d";
  constant escape_mangle_c : byte := x"20";

  subtype fcs_t is crc_state(15 downto 0);
  constant fcs_init_c : fcs_t := x"0000";
  constant fcs_poly_c : fcs_t := x"8408";
  constant fcs_check_c : fcs_t := x"0f47";
  constant fcs_insert_msb_c : boolean := true;
  constant fcs_pop_lsb_c : boolean := true;
  constant fcs_complement_c : boolean := true;
  constant fcs_lsb_first_c : boolean := true;
  constant fcs_bit_reverse_c : boolean := false;

  subtype sequence_t is integer range 0 to 7;
  
  function is_escaped(v: byte) return boolean;
  -- Symmetric operation
  function escape(v: byte) return byte;

  -- User data frame
  function control_i(pf: boolean;
                     ns, nr: sequence_t) return byte;
  -- Supervisory frame
  function control_s(pf: boolean;
                     t: std_ulogic_vector(1 downto 0);
                     nr: sequence_t) return byte;
  constant s_rr  : std_ulogic_vector(1 downto 0) := "00";
  constant s_rnr : std_ulogic_vector(1 downto 0) := "01";
  constant s_rej : std_ulogic_vector(1 downto 0) := "10";

  -- Unnumbered frames
  function control_u(pf: boolean;
                     t: std_ulogic_vector(4 downto 0)) return byte;
  constant u_sabm  : std_ulogic_vector(4 downto 0) := "00111";
  constant u_sabme : std_ulogic_vector(4 downto 0) := "11111";
  constant u_disc  : std_ulogic_vector(4 downto 0) := "01000";
  constant u_ua    : std_ulogic_vector(4 downto 0) := "01100";
  constant u_frmr  : std_ulogic_vector(4 downto 0) := "10001";
  constant u_dm    : std_ulogic_vector(4 downto 0) := "00011";

  function control_pf_get(v: byte) return boolean;

  function control_is_i(v: byte) return boolean;
  function control_is_s(v: byte) return boolean;
  function control_is_u(v: byte) return boolean;

  function control_i_ns_get(v: byte) return sequence_t;
  function control_i_nr_get(v: byte) return sequence_t;
  function control_s_nr_get(v: byte) return sequence_t;
  function control_s_t_get(v: byte) return std_ulogic_vector;
  function control_u_t_get(v: byte) return std_ulogic_vector;

  function frame_build(
    address: integer;
    cmd: byte;
    data: byte_string;
    start_flag, end_flag: boolean := true) return byte_string;

  function escape(data: byte_string) return byte_string;
  
  -- On the frame side, committed frame will contain:
  -- - Address,
  -- - Control,
  -- - Data,
  -- - Status (validity bit), as required by committed.

  -- If frame is received broken, it will still be forwarded, but with
  -- validity clear.
  component hdlc_unframer is
    port(
      clock_i     : in std_ulogic;
      reset_n_i   : in std_ulogic;

      hdlc_i : in nsl_bnoc.pipe.pipe_req_t;
      hdlc_o : out nsl_bnoc.pipe.pipe_ack_t;

      frame_o : out nsl_bnoc.committed.committed_req;
      frame_i : in nsl_bnoc.committed.committed_ack
      );
  end component;

  -- A frame that goes out with validity bit cleared will be transmitted with
  -- broken FCS, on purpose.
  component hdlc_framer is
    generic(
      stuff_c : boolean := false
      );
    port(
      clock_i     : in std_ulogic;
      reset_n_i   : in std_ulogic;

      frame_i : in nsl_bnoc.framed.framed_req;
      frame_o : out nsl_bnoc.framed.framed_ack;

      hdlc_o : out nsl_bnoc.pipe.pipe_req_t;
      hdlc_i : in nsl_bnoc.pipe.pipe_ack_t
      );
  end component;
  
end package;

package body hdlc is

  function is_escaped(v: byte) return boolean
  is
  begin
    case v is
      when x"7e" | x"7d" | x"03"
        | x"11" | x"13" | x"91" | x"93" =>
        return true;

      when others =>
        return false;
    end case;
  end function;

  function escape(v: byte) return byte
  is
    variable b: byte;
  begin
    b := v xor escape_mangle_c;
    return b;
  end function;

  function control_i(pf: boolean;
                     ns, nr: sequence_t) return byte
  is
  begin
    return std_ulogic_vector(to_unsigned(nr, 3))
      & to_logic(pf)
      & std_ulogic_vector(to_unsigned(ns, 3))
      & '0';
  end function;

  function control_s(pf: boolean;
                     t: std_ulogic_vector(1 downto 0);
                     nr: sequence_t) return byte
  is
  begin
    return std_ulogic_vector(to_unsigned(nr, 3))
      & to_logic(pf)
      & t
      & "01";
  end function;

  function control_u(pf: boolean;
                     t: std_ulogic_vector(4 downto 0)) return byte
  is
    variable ret: byte;
  begin
    ret(7 downto 5) := t(4 downto 2);
    ret(4) := to_logic(pf);
    ret(3 downto 2) := t(1 downto 0);
    ret(1 downto 0) := "11";
    return ret;
  end function;

  function control_pf_get(v: byte) return boolean
  is
  begin
    return v(4) = '1';
  end function;

  function control_is_i(v: byte) return boolean
  is
  begin
    return v(0) = '0';
  end function;

  function control_is_s(v: byte) return boolean
  is
  begin
    return v(1 downto 0) = "01";
  end function;

  function control_is_u(v: byte) return boolean
  is
  begin
    return v(1 downto 0) = "11";
  end function;

  function control_i_ns_get(v: byte) return sequence_t
  is
  begin
    return to_integer(unsigned(v(3 downto 1)));
  end function;

  function control_i_nr_get(v: byte) return sequence_t
  is
  begin
    return to_integer(unsigned(v(7 downto 5)));
  end function;
  
  function control_s_nr_get(v: byte) return sequence_t
  is
  begin
    return to_integer(unsigned(v(7 downto 5)));
  end function;
  
  function control_s_t_get(v: byte) return std_ulogic_vector
  is
  begin
    return v(4 downto 3);
  end function;
  
  function control_u_t_get(v: byte) return std_ulogic_vector
  is
  begin
    return v(7 downto 5) & v(3 downto 2);
  end function;

  function frame_build(
    address: integer;
    cmd: byte;
    data: byte_string;
    start_flag, end_flag: boolean := true) return byte_string
  is
    constant header: byte_string(0 to 1) := (0 => to_byte(address), 1 => cmd);
    constant fcs_v: fcs_t := not crc_update(not fcs_init_c, fcs_poly_c, fcs_insert_msb_c, fcs_pop_lsb_c, header&data);
    constant fcs: byte_string(0 to 1) := to_le(unsigned(fcs_v));
    constant escaped: byte_string := escape(header & data & fcs);
  begin
    if start_flag and end_flag then
      return flag_c & escaped & flag_c;
    elsif start_flag then
      return flag_c & escaped;
    elsif end_flag then
      return escaped & flag_c;
    else
      return escaped;
    end if;
  end function;

  function escape(data: byte_string) return byte_string
  is
    variable ret: byte_string(0 to data'length*2-1) := (others => x"00");
    variable point: integer := 0;
  begin
    for i in data'range
    loop
      if is_escaped(data(i)) then
        ret(point) := escape_byte_c;
        ret(point+1) := escape(data(i));
        point := point + 2;
      else
        ret(point) := data(i);
        point := point + 1;
      end if;
    end loop;

    return ret(0 to point-1);
  end function;

end package body;
