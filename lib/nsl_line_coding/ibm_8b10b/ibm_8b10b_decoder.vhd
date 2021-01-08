library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_line_coding, nsl_logic, nsl_memory;
use nsl_line_coding.ibm_8b10b.all;
use nsl_logic.bool.all;

entity ibm_8b10b_decoder is
  generic(
    implementation_c : string := "logic";
    strict_c : boolean := true
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    data_i : in std_ulogic_vector(9 downto 0);

    data_o : out std_ulogic_vector(7 downto 0);
    control_o : out std_ulogic;
    code_error_o : out std_ulogic;
    disparity_error_o : out std_ulogic
    );
end entity;

architecture beh of ibm_8b10b_decoder is
begin

  use_logic: if implementation_c = "logic"
  generate
    use nsl_line_coding.ibm_8b10b_logic.all;

    type regs_t is
    record
      -- Stage 1
      c : classification_10b8b_t;
      data : code_word;

      -- Stage 2
      r : decoded_10b8b_t;
    end record;

    signal r, rin: regs_t;

    attribute rom_style: string;
    attribute rom_style of r: signal is "distributed";
    attribute syn_romstyle : string;
    attribute syn_romstyle of r: signal is "logic";
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.r.disparity <= '0';
      end if;
    end process;

    transition: process(r, data_i) is
    begin
      rin <= r;

      rin.c <= classify_10b8b(data_i);
      rin.data <= data_i;
      
      rin.r <= merge_10b8b(r.data, r.r.disparity, r.c, strict_c);
    end process;

    data_o <= r.r.data;
    disparity_error_o <= r.r.disparity_error;
    code_error_o <= r.r.code_error;
    control_o <= r.r.control;
  end generate;

  use_spec: if implementation_c = "spec"
  generate
    type regs_t is
    record
      rd: std_ulogic;
      control, code_error, disparity_error: std_ulogic;
      data: data_word;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.rd <= '0';
      end if;
    end process;

    transition: process(r, data_i) is
      variable d_o : data_word;
      variable rd_o, err_o, rderr_o, k_o : std_ulogic;
    begin
      rin <= r;

      nsl_line_coding.ibm_8b10b_spec.decode(data_i, r.rd,
                                            d_o, rd_o, k_o, err_o, rderr_o);
      rin.rd <= rd_o;
      rin.data <= d_o;
      rin.control <= k_o;
      rin.code_error <= err_o;
      rin.disparity_error <= rderr_o;
    end process;

    data_o <= r.data;
    control_o <= r.control;
    code_error_o <= r.code_error;
    disparity_error_o <= r.disparity_error;
  end generate;

  use_lut: if implementation_c = "lut"
  generate
    type regs_t is
    record
      rd: std_ulogic;
      control, code_error, disparity_error: std_ulogic;
      data: data_word;
    end record;

    signal r, rin: regs_t;

    attribute rom_style: string;
    attribute rom_style of r: signal is "distributed";
    attribute syn_romstyle : string;
    attribute syn_romstyle of r: signal is "logic";
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.rd <= '0';
      end if;
    end process;

    transition: process(r, data_i) is
      variable d_o : data_word;
      variable rd_o, err_o, rderr_o, k_o : std_ulogic;
    begin
      rin <= r;

      nsl_line_coding.ibm_8b10b_table.decode(data_i, r.rd,
                                             d_o, rd_o, k_o, err_o, rderr_o);
      rin.rd <= rd_o;
      rin.data <= d_o;
      rin.control <= k_o;
      rin.code_error <= err_o;
      rin.disparity_error <= rderr_o;
    end process;

    data_o <= r.data;
    control_o <= r.control;
    code_error_o <= r.code_error;
    disparity_error_o <= r.disparity_error;
  end generate;
  
  use_rom: if implementation_c = "rom"
  generate
    use nsl_line_coding.ibm_8b10b_table.all;

    type regs_t is
    record
      data: data_word;
      code_err, rd_err, rd, k : std_ulogic;
    end record;

    signal k_s, rd_toggle_s : std_ulogic;
    signal data_s : data_word;
    signal dec_err_s, rd_err_s : std_ulogic_vector(0 to 1);

    signal r, rin : regs_t;
    
    function lut_populate return std_ulogic_vector
    is
      variable ret : std_ulogic_vector(0 to 14 * 1024 - 1);
      variable idx: unsigned(9 downto 0);
      variable d_i: code_word;
      variable rd_i, k_o, rd_toggle_o : std_ulogic;
      variable dec_err_o, rd_err_o : std_ulogic_vector(0 to 1);
      variable d_o : data_word;
    begin
      for w in 0 to 1024
      loop
        d_i := std_ulogic_vector(to_unsigned(w, 10));
        idx := unsigned(d_i);
        nsl_line_coding.ibm_8b10b_table.decode_lookup(
          d_i,
          d_o, rd_err_o, dec_err_o, k_o, rd_toggle_o);
        rd_toggle_o := to_logic(rd_toggle_o = '1');
        k_o := to_logic(k_o = '1');
        ret(to_integer(idx)*14 to (to_integer(idx)+1)*14 - 1)
          := rd_toggle_o & k_o & dec_err_o & rd_err_o & d_o;
      end loop;
      return ret;
    end function;
    
  begin
    lut: nsl_memory.lut_sync.lut_sync_1p
      generic map(
        input_width_c => 10,
        output_width_c => 14,
        contents_c => lut_populate
        )
      port map(
        clock_i => clock_i,
        enable_i => '1',
        data_i => data_i,
        data_o(13) => rd_toggle_s,
        data_o(12) => k_s,
        data_o(11 downto 10) => dec_err_s,
        data_o(9 downto 8) => rd_err_s,
        data_o(7 downto 0) => data_s
        );

    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.rd <= '0';
      end if;
    end process;

    transition: process(r, data_s, rd_toggle_s, dec_err_s, rd_err_s, k_s) is
    begin
      rin <= r;

      rin.k <= k_s;
      rin.data <= data_s;
      if r.rd = '0' then
        rin.code_err <= dec_err_s(0);
        rin.rd_err <= rd_err_s(0);
        rin.rd <= rd_toggle_s xor r.rd xor rd_err_s(0);
      else
        rin.code_err <= dec_err_s(1);
        rin.rd_err <= rd_err_s(1);
        rin.rd <= rd_toggle_s xor r.rd xor rd_err_s(1);
      end if;
    end process;

    data_o <= r.data;
    control_o <= r.k;
    code_error_o <= r.code_err;
    disparity_error_o <= r.rd_err;
  end generate;

  use_unknown: if implementation_c /= "rom" and implementation_c /= "spec" and implementation_c /= "logic" and implementation_c /= "lut"
  generate
    assert false
      report "Unknown implementation requested: " & implementation_c
      severity failure;
  end generate;

end architecture;
