library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_line_coding, nsl_logic, nsl_memory;
use nsl_line_coding.ibm_8b10b.all;
use nsl_logic.bool.all;

entity ibm_8b10b_encoder is
  generic(
    implementation_c : string := "logic"
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    data_i : in data_t;
    data_o : out code_word_t
    );
end entity;

architecture beh of ibm_8b10b_encoder is

begin

  use_logic: if implementation_c = "logic"
  generate
    use nsl_line_coding.ibm_8b10b_logic.all;

    type regs_t is
    record
      -- Stage 1
      cl5 : classification_5b6b_t;
      cl3 : classification_3b4b_t;
      control : std_ulogic;

      -- Stage 2
      ret : encoded_8b10b_t;
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
        r.ret.rd <= '0';
        r.control <= '0';
      end if;
    end process;

    transition: process(r, data_i) is
    begin
      rin <= r;

      rin.cl5 <= classify_5b6b(data_i.data(4 downto 0), data_i.control);
      rin.cl3 <= classify_3b4b(data_i.data(7 downto 5), data_i.control);
      rin.control <= data_i.control;

      rin.ret <= merge_8b10b(r.ret.rd, r.control, r.cl5, r.cl3);
    end process;

    data_o <= r.ret.data;
  end generate;

  use_spec: if implementation_c = "spec"
  generate
    use nsl_line_coding.ibm_8b10b_logic.all;

    type regs_t is
    record
      rd: std_ulogic;
      data: code_word_t;
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
      variable d_o : code_word_t;
      variable rd_o : std_ulogic;
    begin
      rin <= r;

      nsl_line_coding.ibm_8b10b_spec.encode(data_i, r.rd, d_o, rd_o);
      rin.rd <= to_logic(rd_o = '1');
      rin.data <= d_o;
    end process;

    data_o <= r.data;
  end generate;

  use_lut: if implementation_c = "lut"
  generate
    use nsl_line_coding.ibm_8b10b_logic.all;

    type regs_t is
    record
      rd: std_ulogic;
      data: code_word_t;
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
      variable d_o : code_word_t;
      variable rd_o : std_ulogic;
    begin
      rin <= r;

      nsl_line_coding.ibm_8b10b_table.encode(data_i, r.rd, d_o, rd_o);
      rin.rd <= to_logic(rd_o = '1');
      rin.data <= d_o;
    end process;

    data_o <= r.data;
  end generate;
  
  use_rom: if implementation_c = "rom"
  generate
    use nsl_line_coding.ibm_8b10b_table.all;

    signal rd : std_ulogic;

    function lut_populate return std_ulogic_vector
    is
      variable ret : std_ulogic_vector(0 to 11 * 1024 - 1);
      variable idx: unsigned(9 downto 0);
      variable d_i: data_t;
      variable rd_i, rd_o : std_ulogic;
      variable d_o : code_word_t;
    begin
      for din in 0 to 1
      loop
        for k in 0 to 1
        loop
          for d in 0 to 255
          loop
            d_i.data := std_ulogic_vector(to_unsigned(d, 8));
            rd_i := to_logic(din = 1);
            d_i.control := to_logic(k = 1);
            idx := unsigned(rd_i & d_i.control & d_i.data);
            nsl_line_coding.ibm_8b10b_table.encode(d_i, rd_i, d_o, rd_o);
            ret(to_integer(idx)*11 to (to_integer(idx)+1)*11 - 1) := rd_o & d_o;
          end loop;
        end loop;
      end loop;
      return ret;
    end function;
    
  begin
    lut: nsl_memory.lut_sync.lut_sync_1p
      generic map(
        input_width_c => 10,
        output_width_c => 11,
        contents_c => lut_populate
        )
      port map(
        clock_i => clock_i,
        enable_i => '1',
        data_i(9) => rd,
        data_i(8) => data_i.control,
        data_i(7 downto 0) => data_i.data,
        data_o(10) => rd,
        data_o(9 downto 0) => data_o
        );
  end generate;

  use_unknown: if implementation_c /= "rom" and implementation_c /= "spec" and implementation_c /= "logic" and implementation_c /= "lut"
  generate
    assert false
      report "Unknown implementation requested: " & implementation_c
      severity failure;
  end generate;
    
end architecture;
