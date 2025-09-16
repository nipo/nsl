library ieee, nsl_data, nsl_logic, nsl_amba;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use nsl_data.bytestream.all;
use nsl_amba.axi4_stream.all;
use nsl_logic.logic.xor_reduce;
use nsl_data.crc.all;
use nsl_data.prbs.all;
use nsl_logic.bool.all;
use nsl_data.endian.all;
use ieee.std_logic_misc.all;
use nsl_data.text.all;

-- Generic random_pkt_checker implementation
package random_pkt_checker is

    constant HEADER_SIZE : integer := 8;
    constant HEADER_CRC_SIZE : integer := 2;
    constant CMD_SIZE : integer := 4;
    constant STATS_SIZE : integer := 8;

    constant HEADER_SEQ_NUM_OFFSET : integer := 0;
    constant HEADER_SIZE_OFFSET : integer := 2;
    constant HEADER_RANDOM_DATA_OFFSET : integer := 4;
    constant HEADER_CRC_OFFSET : integer := 6;

    constant ZERO_BYTE : std_ulogic_vector(7 downto 0) := (others => '0');

    type header_t is 
        record
            seq_num : unsigned(15 downto 0);
            pkt_size : unsigned(15 downto 0);
            rand_data : unsigned(15 downto 0);
            crc : unsigned(15 downto 0);
        end record;

    type stats_t is
        record
            stats_seqnum : unsigned(15 downto 0);
            stats_pkt_size : unsigned(15 downto 0);
            stats_header_valid : boolean;
            stats_payload_valid : boolean;
            stats_index_data_ko : unsigned(15 downto 0);
        end record;

    type cmd_t is
        record
            cmd_seqnum : unsigned(15 downto 0);
            cmd_pkt_size : unsigned(15 downto 0);
        end record;

    function header_unpack(header : byte_string; valid_len : natural) return header_t;
    function cmd_unpack(cmd : byte_string) return cmd_t;
    function is_valid_rand_data(header : header_t) return boolean;
    function is_header_valid(rx_header_size : unsigned;
                             header : header_t; 
                             seq_num : unsigned(15 downto 0); 
                             header_crc_params_c: crc_params_t) return boolean; 
    function is_header_valid_vector(rx_header_size : unsigned;
                                    header : header_t; 
                                    seq_num : unsigned(15 downto 0); 
                                    header_crc_params_c: crc_params_t) return std_ulogic_vector; 

    function ref_header(rx_header_size : unsigned;
                        header : header_t;
                        seq_num : unsigned(15 downto 0);
                        header_crc_params_c: crc_params_t) return byte_string;
    function to_prbs_state(u : unsigned) return prbs_state;
    function stats_unpack(b : byte_string) return stats_t;
    function stats_pack(s : stats_t) return byte_string;
    function status_generator(stats : stats_t) return boolean;
    function max(a, b : unsigned) return unsigned;
    function header_pack(seq_num : unsigned;
                         pkt_size : unsigned;
                         filler_header_crc  : crc_state_t;
                         header_crc_params_c : crc_params_t) return byte_string;

    function count_valid_bytes(tkeep : std_ulogic_vector) return natural;

    component random_cmd_generator is
        generic (
          mtu_c: integer := 1500;
          header_prbs_init: prbs_state := x"d"&"111";
          header_prbs_poly: prbs_state := prbs7;
          config_c : config_t := config(2, last => true)
          );
        port (
          clock_i : in std_ulogic;
          reset_n_i : in std_ulogic;
          --
          enable_i : in std_ulogic;
          --
          out_o : out master_t;
          out_i : in slave_t
          );
      end component;

    component random_pkt_generator is
        generic (
            mtu_c: integer := 1500;
            config_c: config_t;
            data_prbs_init: prbs_state := x"deadbee"&"111";
            data_prbs_poly: prbs_state := prbs31;
            header_crc_params_c: crc_params_t
            );
        port (
            clock_i : in std_ulogic;
            reset_n_i : in std_ulogic;
            --
            in_i : in master_t;
            in_o : out slave_t;
            --
            out_o : out master_t;
            out_i : in slave_t
            );
    end component;

    component random_pkt_validator is
        generic (
            mtu_c: integer := 1500;
            config_c: config_t;
            data_prbs_init: prbs_state := x"deadbee"&"111";
            data_prbs_poly: prbs_state := prbs31;
            header_crc_params_c: crc_params_t
            );
          port (
            clock_i : in std_ulogic;
            reset_n_i : in std_ulogic;
            --
            in_i : in master_t;
            in_o : out slave_t;
            --
            out_o : out master_t;
            out_i : in slave_t
            );
        end component;

    component random_stats_asserter is
        generic (
        mtu_c: integer := 1500;
        config_c: config_t
        );
        port (
        clock_i : in std_ulogic;
        reset_n_i : in std_ulogic;
        --
        in_i : in master_t;
        in_o : out slave_t;
        --
        out_o : out master_t;
        out_i : in slave_t
        );
  end component;


end package;

package body random_pkt_checker is

    function header_unpack(header : byte_string; valid_len : natural) return header_t is
        variable ret : header_t;
        variable idx : natural := 0;
    begin
        -- Initialize fields to zero
        ret.seq_num   := (others => '0');
        ret.pkt_size  := (others => '0');
        ret.rand_data := (others => '0');
        ret.crc       := (others => '0');
    
        -- === seq_num ===
        if valid_len > idx then
            ret.seq_num := (7 downto 0 => '0') & unsigned(header(idx));  -- LSB = received byte
            idx := idx + 1;
        end if;
        if valid_len > idx then
            ret.seq_num := unsigned(header(idx)) & ret.seq_num(7 downto 0); -- MSB received
            idx := idx + 1;
        end if;
    
        -- === pkt_size ===
        if valid_len > idx then
            ret.pkt_size := (7 downto 0 => '0') & unsigned(header(idx));
            idx := idx + 1;
        end if;
        if valid_len > idx then
            ret.pkt_size := unsigned(header(idx)) & ret.pkt_size(7 downto 0);
            idx := idx + 1;
        end if;
    
        -- === rand_data ===
        if valid_len > idx then
            ret.rand_data := (7 downto 0 => '0') & unsigned(header(idx));
            idx := idx + 1;
        end if;
        if valid_len > idx then
            ret.rand_data := unsigned(header(idx)) & ret.rand_data(7 downto 0);
            idx := idx + 1;
        end if;
    
        -- === crc ===
        if valid_len > idx then
            ret.crc := (7 downto 0 => '0') & unsigned(header(idx));
            idx := idx + 1;
        end if;
        if valid_len > idx then
            ret.crc := unsigned(header(idx)) & ret.crc(7 downto 0);
            idx := idx + 1;
        end if;
    
        return ret;
    end function;

    function header_pack(seq_num : unsigned;
                         pkt_size : unsigned;
                         filler_header_crc  : crc_state_t;
                         header_crc_params_c : crc_params_t) return byte_string
    is
        variable ret: byte_string(0 to HEADER_SIZE- 1) := (others => (others => '0'));
        variable rand_data_v : byte_string(0 to 1) := prbs_byte_string(to_prbs_state(pkt_size(14 downto 0)), prbs15, 2);
    begin 
        ret(0) := std_ulogic_vector(seq_num(7 downto 0));
        ret(1) := std_ulogic_vector(seq_num(15 downto 8));
        ret(2) := std_ulogic_vector(pkt_size(7 downto 0));
        ret(3) := std_ulogic_vector(pkt_size(15 downto 8));
        ret(4) := rand_data_v(1);
        ret(5) := rand_data_v(0); 
        ret(6) := crc_spill(header_crc_params_c, crc_update(header_crc_params_c, 
                                filler_header_crc,
                                ret(0 to 5)))(0);
        ret(7) := crc_spill(header_crc_params_c, crc_update(header_crc_params_c, 
                                filler_header_crc,
                                ret(0 to 5)))(1);
        return ret;
    end function;


    function cmd_unpack(cmd : byte_string) return cmd_t 
    is
        variable ret: cmd_t;
    begin
        ret.cmd_seqnum := unsigned(cmd(3)) & unsigned(cmd(2));
        ret.cmd_pkt_size := unsigned(cmd(1)) & unsigned(cmd(0));
        return ret;
    end function;

    function stats_unpack(b : byte_string) return stats_t
    is
        variable ret: stats_t;
    begin 
        ret.stats_seqnum := unsigned(b(1)) & unsigned(b(0));
        ret.stats_pkt_size := unsigned(b(3)) & unsigned(b(2));
        ret.stats_header_valid := to_boolean(b(4)(7));
        ret.stats_payload_valid := to_boolean(b(5)(7));
        ret.stats_index_data_ko := unsigned(b(7)) & unsigned(b(6));
        return ret;
    end function;

    function stats_pack(s : stats_t) return byte_string
    is
        variable ret: byte_string(0 to 7) := (others =>(others => '0'));
    begin 
        ret(0 to 1) := to_le(s.stats_seqnum);
        ret(2 to 3) := to_le(s.stats_pkt_size);
        ret(4)(7) := to_logic(s.stats_header_valid);
        ret(5)(7) := to_logic(s.stats_payload_valid);
        ret(6 to 7) := to_le(s.stats_index_data_ko);
        return ret;
    end function;

    -- Convert unsigned to prbs_state
    function to_prbs_state(u : unsigned) return prbs_state is
        variable result : prbs_state(14 downto 0);
    begin
        for i in u'range loop
            result(i) := std_ulogic(u(i));
        end loop;
        return result;
    end function;

    function is_valid_rand_data(header : header_t) return boolean is
        variable rand_data_v : byte_string(0 to 1) := prbs_byte_string(to_prbs_state(header.pkt_size(14 downto 0)), prbs15, 2);
    begin 
        return from_suv(std_ulogic_vector(header.rand_data)) = rand_data_v;
    end function;

    function is_header_valid(rx_header_size : unsigned;
                             header : header_t;
                             seq_num : unsigned(15 downto 0);
                             header_crc_params_c: crc_params_t) return boolean 
    is 
        variable ret : std_ulogic_vector(3 downto 0) := (others => '1');
        variable rand_data_v : byte_string(0 to 1) := prbs_byte_string(to_prbs_state(header.pkt_size(14 downto 0)), prbs15, 2);
        variable header_byte_str_v : byte_string(0 to 5) := to_le(header.seq_num) & to_le(header.pkt_size) & rand_data_v(1) & rand_data_v(0);
        variable crc_0_v : byte :=  crc_spill(header_crc_params_c, crc_update(header_crc_params_c, 
                                                                              crc_init(header_crc_params_c),
                                                                              header_byte_str_v))(1);
        variable crc_1_v : byte :=  crc_spill(header_crc_params_c, crc_update(header_crc_params_c, 
                                                                              crc_init(header_crc_params_c),
                                                                              header_byte_str_v))(0);
    begin        
        -- SeqNum test
        if rx_header_size = 1 then
            ret(3) := to_logic(header.seq_num(7 downto 0) = seq_num(7 downto 0));
        else
            ret(3) := to_logic(header.seq_num = seq_num);
        end if;

        -- size test
        if rx_header_size >= 3 and rx_header_size < HEADER_SIZE then
            ret(2) := to_logic(header.pkt_size = rx_header_size);
        end if;

        -- Random data test
        if rx_header_size = 5 then
            ret(1) := to_logic(to_be(header.rand_data)(0) = rand_data_v(0));
        elsif rx_header_size > 5 then
            ret(1) := to_logic(is_valid_rand_data(header));
        end if;

        -- CRC test 
        if rx_header_size = 7 then
            ret(0) := to_logic(header.crc(15 downto 8) = unsigned(crc_0_v));
        elsif rx_header_size > 7 then
            ret(0) := to_logic(header.crc(15 downto 8) = unsigned(crc_0_v)) and 
                      to_logic(header.crc(7 downto 0) = unsigned(crc_1_v));
        end if;

        return to_boolean(and_reduce(ret));
    end function;

    function is_header_valid_vector(rx_header_size : unsigned;
                                    header : header_t;
                                    seq_num : unsigned(15 downto 0);
                                    header_crc_params_c: crc_params_t) return std_ulogic_vector 
    is 
        variable ret : std_ulogic_vector(3 downto 0) := (others => '1');
        variable rand_data_v : byte_string(0 to 1) := prbs_byte_string(to_prbs_state(header.pkt_size(14 downto 0)), prbs15, 2);
        variable header_byte_str_v : byte_string(0 to 5) := to_le(header.seq_num) & to_le(header.pkt_size) & rand_data_v(1) & rand_data_v(0);
        variable crc_0_v : byte :=  crc_spill(header_crc_params_c, crc_update(header_crc_params_c, 
                                                                              crc_init(header_crc_params_c),
                                                                              header_byte_str_v))(1);
        variable crc_1_v : byte :=  crc_spill(header_crc_params_c, crc_update(header_crc_params_c, 
                                                                              crc_init(header_crc_params_c),
                                                                              header_byte_str_v))(0);
    begin 
        -- SeqNum test
        if rx_header_size = 1 then
            ret(3) := to_logic(header.seq_num(7 downto 0) = seq_num(7 downto 0));
        else
            ret(3) := to_logic(header.seq_num = seq_num);
        end if;

        -- size test
        if rx_header_size >= 2 and rx_header_size < HEADER_SIZE then
            ret(2) := to_logic(header.pkt_size = rx_header_size);
        end if;

        -- Random data test
        if rx_header_size = 4 then
            ret(1) := to_logic(to_be(header.rand_data)(0) = rand_data_v(0));
        elsif rx_header_size > 4 then
            ret(1) := to_logic(is_valid_rand_data(header));
        end if;

        -- CRC test 
        if rx_header_size = 6 then
            ret(0) := to_logic(header.crc(15 downto 8) = unsigned(crc_0_v));
        elsif rx_header_size > 6 then
            ret(0) := to_logic(header.crc(15 downto 8) = unsigned(crc_0_v)) and 
                        to_logic(header.crc(7 downto 0) = unsigned(crc_1_v));
        end if;
        return ret;
    end function;

    function ref_header(rx_header_size : unsigned;
                        header : header_t;
                        seq_num : unsigned(15 downto 0);
                        header_crc_params_c: crc_params_t) return byte_string 
    is 
        variable ret : byte_string(0 to HEADER_SIZE-1) := (others => (others => '-'));
        variable rand_data_v : byte_string(0 to 1) := reverse(prbs_byte_string(to_prbs_state(header.pkt_size(14 downto 0)), prbs15, 2));
        variable header_byte_str_v : byte_string(0 to 5) := to_le(header.seq_num) & to_le(header.pkt_size) & rand_data_v(0) & rand_data_v(1);
        variable crc_0_v : byte :=  crc_spill(header_crc_params_c, crc_update(header_crc_params_c, 
                                                                              crc_init(header_crc_params_c),
                                                                              header_byte_str_v))(1);
        variable crc_1_v : byte :=  crc_spill(header_crc_params_c, crc_update(header_crc_params_c, 
                                                                              crc_init(header_crc_params_c),
                                                                              header_byte_str_v))(0);
    begin 
        case to_integer(rx_header_size) is
            when 1 =>
                ret(0) := to_be(seq_num(7 downto 0))(0);
            when 2 => 
                ret(0 to 1) := to_be(seq_num(7 downto 0)) & to_be(seq_num(15 downto 8));
            when 3 => 
                ret(0 to 2) := to_be(seq_num(7 downto 0)) & to_be(seq_num(15 downto 8)) & to_be(header.pkt_size(7 downto 0));
            when 4 => 
                ret(0 to 3) := to_be(seq_num(7 downto 0)) & to_be(seq_num(15 downto 8)) & to_be(header.pkt_size(7 downto 0)) & to_be(header.pkt_size(15 downto 8));
            when 5 => 
                ret(0 to 4) := to_be(seq_num(7 downto 0)) & to_be(seq_num(15 downto 8)) & to_be(header.pkt_size(7 downto 0)) & to_be(header.pkt_size(15 downto 8)) & rand_data_v(0);
            when 6 => 
                ret(0 to 5) := to_be(seq_num(7 downto 0)) & to_be(seq_num(15 downto 8)) & to_be(header.pkt_size(7 downto 0)) & to_be(header.pkt_size(15 downto 8)) & rand_data_v(0) & rand_data_v(1);
            when 7 => 
                ret(0 to 6) := to_be(seq_num(7 downto 0)) & to_be(seq_num(15 downto 8)) & to_be(header.pkt_size(7 downto 0)) & to_be(header.pkt_size(15 downto 8)) & rand_data_v & crc_0_v;
            when 8 => 
                ret(0 to 7) := to_be(seq_num(7 downto 0)) & to_be(seq_num(15 downto 8)) & to_be(header.pkt_size(7 downto 0)) & to_be(header.pkt_size(15 downto 8)) & rand_data_v & crc_1_v & crc_0_v;
            when others =>
        end case;
        return ret;
    end function;

    function status_generator(stats : stats_t) return boolean 
    is
    begin 
        return stats.stats_header_valid and stats.stats_payload_valid;
    end function;
    
    function max(a, b : unsigned) return unsigned is
    begin
        if a > b then
            return a;
        else
            return b;
        end if;
    end function;

    function count_valid_bytes(tkeep : std_ulogic_vector) return natural is
        variable cnt : natural := 0;
    begin
        for i in tkeep'range loop
            if tkeep(i) = '1' then
                cnt := cnt + 1;
            end if;
        end loop;
        return cnt;
    end function;
    

end package body;
