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

    type error_feedback_array_t is array (natural range <>) of error_feedback_t;


    function header_unpack(header : byte_string; valid_len : natural) return header_t;
    function cmd_unpack(cmd : byte_string) return cmd_t;
    function ref_header(rx_header_size : unsigned;
                        header : header_t;
                        seq_num : unsigned(15 downto 0);
                        header_crc_params_c: crc_params_t) return byte_string;
    function to_prbs_state(u : unsigned) return prbs_state;
    function stats_unpack(b : byte_string) return stats_t;
    function stats_pack(s : stats_t) return byte_string;
    function max(a, b : unsigned) return unsigned;
    function header_pack(seq_num : unsigned;
                         pkt_size : unsigned;
                         filler_header_crc  : crc_state_t;
                         header_crc_params_c : crc_params_t) return byte_string;

    function count_valid_bytes(tkeep : std_ulogic_vector) return natural;
    function to_slv(bstr : byte_string) return std_ulogic_vector;
    function is_seqnum_corrupted(index_ko : unsigned) return boolean;
    function is_size_corrupted(index_ko : unsigned) return boolean;
    function is_rand_data_corrupted(index_ko : unsigned) return boolean;
    function is_header_corrupted(index_ko : unsigned) return boolean;
    -- ================================================================
    -- Random Packet Generation & Validation Pipeline
    -- ================================================================
    --
    -- Data flows sequentially through four components:
    -- random_cmd_generator -> random_pkt_generator -> random_pkt_validator -> random_stats_asserter
    --
    --   +------------------------+
    --   |  random_cmd_generator  |
    --   |------------------------|
    --   | Inputs: clock_i        |
    --   |         reset_n_i      |
    --   |         enable_i       |
    --   | Outputs: out_o --------+-----------------------------+
    --   |         out_i          |                             |
    --   +------------------------+                             |
    --                                                           |
    --                                                           v
    --   +------------------------+
    --   |  random_pkt_generator  |
    --   |------------------------|
    --   | Inputs: clock_i        |
    --   |         reset_n_i      |
    --   |         in_i  <--------+  <- from cmd_generator
    --   | Outputs: out_o --------+-----------------------------+
    --   |         in_o           |
    --   +------------------------+
    --                                                           |
    --                                                           v
    --   +------------------------+
    --   |  random_pkt_validator  |
    --   |------------------------|
    --   | Inputs: clock_i        |
    --   |         reset_n_i      |
    --   |         in_i  <--------+  <- from pkt_generator
    --   | Outputs: out_o --------+-----------------------------+
    --   |         in_o           |
    --   +------------------------+
    --                                                           |
    --                                                           v
    --   +------------------------+
    --   |  random_stats_asserter |
    --   |------------------------|
    --   | Inputs: clock_i        |
    --   |         reset_n_i      |
    --   |         in_i  <--------+  <- from pkt_validator
    --   |         feedback_i     |
    --   | Outputs: assert_error_o|
    --   +------------------------+
    --
    -- ================================================================
    -- Notes:
    -- 1. random_cmd_generator:
    --    - Generates pseudo-random commands (seq_num + random pkt_size)
    -- 2. random_pkt_generator:
    --    - Generates packet data using PRBS, prepends header (seq_num, pkt_size, rand_data, crc)
    -- 3. random_pkt_validator:
    --    - Recreates reference data from received header using PRBS
    --    - Compares with received packet to detect corruption or loss
    -- 4. random_stats_asserter:
    --    - Produces std_ulogic error signal from validator feedback
    --    - Can be used as a hardware trigger
    -- ================================================================
    -- Generate a pseudo-random command formed by concatenating
    -- a packet sequence number with a random size in the range 1 to mtu_c.
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
    -- Uses the "random_cmd_generator" output as a seed to generate random
    -- packets of length cmd.size based on a PRBS sequence. A header is added
    -- at the beginning (if size permits) with the following fields:
    --
    --   +----------------+----------------+----------------+----------------+
    --   |   seq_num      |   pkt_size     |   rand_data    |      crc       |
    --   |   16 bits      |   16 bits      |   16 bits      |   16 bits      |
    --   +----------------+----------------+----------------+----------------+
    --
    -- Total header size = 64 bits (8 bytes)
    -- The rand_data field is generated by seeding a PRBS with both
    -- the seq_num and pkt_size fields.
    -- Seq_num and pkt_size fields are from the received command.
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
    -- Reuses the random_pkt_generator PRBS polynomial, seeded with values
    -- from the received header. The generated reference data is compared
    -- against the received data to detect corruption, while sequence number
    -- checks allow detection of lost packets.
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
    -- Generate a std_ulogic error signal by comparing feedback with status
    -- from random_pkt_validator. Can be used as a hardware trigger.
    component random_stats_asserter is
        generic (
            config_c: config_t
            );
            port (
            clock_i : in std_ulogic;
            reset_n_i : in std_ulogic;
            --
            in_i : in master_t;
            in_o : out slave_t;
            --
            feedback_i : in error_feedback_t;
            assert_error_o : out std_ulogic
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
        ret.cmd_seqnum := unsigned(cmd(1)) & unsigned(cmd(0));
        ret.cmd_pkt_size := unsigned(cmd(3)) & unsigned(cmd(2));
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

    function ref_header(rx_header_size : unsigned;
                        header : header_t;
                        seq_num : unsigned(15 downto 0);
                        header_crc_params_c: crc_params_t) return byte_string 
    is 
        variable ret : byte_string(0 to HEADER_SIZE-1) := (others => (others => '-'));
        variable rand_data_v : byte_string(0 to 1) := reverse(prbs_byte_string(to_prbs_state(rx_header_size(14 downto 0)), prbs15, 2));
        variable header_byte_str_v : byte_string(0 to 5) := to_le(header.seq_num) & to_le(rx_header_size) & rand_data_v(0) & rand_data_v(1);
        variable crc_0_v : byte :=  crc_spill(header_crc_params_c, crc_update(header_crc_params_c, 
                                                                              crc_init(header_crc_params_c),
                                                                              header_byte_str_v))(1);
        variable crc_1_v : byte :=  crc_spill(header_crc_params_c, crc_update(header_crc_params_c, 
                                                                              crc_init(header_crc_params_c),
                                                                              header_byte_str_v))(0);
    begin 
        ret(0 to 7) := to_be(seq_num(7 downto 0)) & to_be(seq_num(15 downto 8)) & to_be(rx_header_size(7 downto 0)) & to_be(rx_header_size(15 downto 8)) & rand_data_v & crc_1_v & crc_0_v;
        return ret;
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
    
    function to_slv(bstr : byte_string) return std_ulogic_vector is
        variable res : std_ulogic_vector(bstr'length*8 - 1 downto 0);
      begin
        for i in 0 to bstr'length-1 loop
          res((i+1)*8-1 downto i*8) := bstr(i);
        end loop;
        return res;
      end function;

      function is_seqnum_corrupted(index_ko : unsigned) return boolean is
      begin 
        return index_ko = 0 or index_ko = 1;
      end function;

      function is_size_corrupted(index_ko : unsigned) return boolean is
      begin
        return index_ko = 2 or index_ko = 3;
      end function;
      
      function is_rand_data_corrupted(index_ko : unsigned) return boolean is
      begin
        return index_ko = 4 or index_ko = 5;
      end function;

      function is_header_corrupted(index_ko : unsigned) return boolean is
      begin 
        return index_ko = 0 or index_ko = 1 or index_ko = 2 or index_ko = 3 or index_ko = 4 or index_ko = 5 or index_ko = 6 or index_ko = 7;
      end function;

end package body;
