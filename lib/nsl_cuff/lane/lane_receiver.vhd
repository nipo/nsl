library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_cuff, nsl_line_coding;
use nsl_line_coding.ibm_8b10b.all;
use nsl_cuff.lane.all;
use nsl_cuff.protocol.all;

entity lane_receiver is
  generic(
    lane_index_c : natural;
    lane_count_c : natural;
    mtu_l2_c : natural range 0 to 15;
    ibm_8b10b_implementation_c : string := "logic"
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    lane_i : in cuff_code_word_t;
    data_o : out cuff_data_t;

    align_restart_o : out std_ulogic;
    align_valid_o : out std_ulogic;
    align_ready_i : in std_ulogic;

    sync_sof_o, sync_eof_o: out std_ulogic;
    
    state_o: out lane_state_t
    );
end entity;

architecture beh of lane_receiver is

  function is_word_expected(d: data_t) return boolean
  is
  begin
    if d.control = '1' then
      if lane_index_c = 0 then
        return d = CUFF_SYNC_SOF_MAIN or d = CUFF_SYNC_SOF_READY or d = CUFF_SYNC_EOF;
      else
        return d = CUFF_SYNC_SOF_SEC or d = CUFF_SYNC_FILL or d = CUFF_SYNC_EOF;
      end if;
    else
      if lane_index_c = 0 then
        return d = D21_5
          or d.data = (std_ulogic_vector(to_unsigned(mtu_l2_c, 4))
                         & std_ulogic_vector(to_unsigned(lane_count_c-1, 4)))
          or d.data(7 downto 4) = std_ulogic_vector(to_unsigned(lane_index_c, 4));
      else
        return d = D21_5
          or d.data(7 downto 4) = std_ulogic_vector(to_unsigned(lane_index_c, 4));
      end if;
    end if;
  end function;
  
  type regs_t is
  record
    state: lane_state_t;
    sync_index: integer range 0 to 4;
    align_restart: std_ulogic;

    code_error, disparity_error : std_ulogic;
    data: nsl_line_coding.ibm_8b10b.data_t;
  end record;

  signal r, rin: regs_t;

  signal data_s: nsl_line_coding.ibm_8b10b.data_t;
  signal code_error_s, disparity_error_s: std_ulogic;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= LANE_BIT_ALIGN;
    end if;
  end process;

  transition: process(r, align_ready_i, code_error_s, data_s, disparity_error_s) is
  begin
    rin <= r;

    rin.data <= data_s;
    rin.disparity_error <= disparity_error_s;
    rin.code_error <= code_error_s;
    rin.align_restart <= '0';

    case r.state is
      when LANE_BIT_ALIGN =>
        if disparity_error_s /= '0' or code_error_s /= '0' then
          rin.sync_index <= 0;
        elsif (lane_index_c = 0 and r.data = CUFF_SYNC_SOF_MAIN)
          or (lane_index_c /= 0 and r.data = CUFF_SYNC_SOF_SEC) then
          rin.sync_index <= 1;
          if align_ready_i = '1' then
            rin.state <= LANE_BUS_ALIGN;
          end if;
        elsif r.sync_index < 4 then
          rin.sync_index <= r.sync_index + 1;
        else
          rin.sync_index <= 0;
        end if;

      when LANE_BUS_ALIGN | LANE_BUS_ALIGN_READY =>
        if r.sync_index < 4 then
          rin.sync_index <= r.sync_index + 1;
        else
          rin.sync_index <= 0;
        end if;

        if disparity_error_s /= '0' or code_error_s /= '0' then
          rin.sync_index <= 0;
          rin.state <= LANE_BIT_ALIGN;
          rin.align_restart <= '1';
        end if;
        if r.data = CUFF_DATA_IDLE then
          rin.state <= LANE_DATA;
        else
          case r.sync_index is
            when 0 =>
              if lane_index_c = 0 then
                if r.data = CUFF_SYNC_SOF_READY then
                  rin.state <= LANE_BUS_ALIGN_READY;
                elsif r.data /= CUFF_SYNC_SOF_MAIN and r.data /= CUFF_SYNC_SOF_READY then
                  rin.state <= LANE_BIT_ALIGN;
                  rin.align_restart <= '1';
                end if;
              else
                if r.data /= CUFF_SYNC_SOF_SEC then
                  rin.state <= LANE_BIT_ALIGN;
                  rin.align_restart <= '1';
                end if;
              end if;

            when 1 =>
              if lane_index_c = 0 then
                if r.data /= data(std_ulogic_vector(to_unsigned(mtu_l2_c, 4))
                                  & std_ulogic_vector(to_unsigned(lane_count_c-1, 4))) then
                  rin.state <= LANE_BIT_ALIGN;
                  rin.align_restart <= '1';
                end if;
              else
                if r.data /= CUFF_SYNC_FILL then
                  rin.state <= LANE_BIT_ALIGN;
                  rin.align_restart <= '1';
                end if;
              end if;

            when 2 =>
              if r.data.control = '1'
                or r.data.data(7 downto 4) /= std_ulogic_vector(to_unsigned(lane_index_c, 4)) then
                rin.state <= LANE_BIT_ALIGN;
                rin.align_restart <= '1';
              end if;

            when 3 =>
              if r.data /= CUFF_SYNC_BITSYNC then
                rin.state <= LANE_BIT_ALIGN;
                rin.align_restart <= '1';
              end if;

            when 4 =>
              if r.data /= CUFF_SYNC_EOF then
                rin.state <= LANE_BIT_ALIGN;
                rin.align_restart <= '1';
              end if;
          end case;
        end if;

      when LANE_DATA =>
        if disparity_error_s /= '0' or code_error_s /= '0' then
          rin.sync_index <= 0;
          rin.state <= LANE_BIT_ALIGN;
          rin.align_restart <= '1';
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    if disparity_error_s = '0' and code_error_s = '0' and is_word_expected(data_s) then
      align_valid_o <= '1';
    else
      align_valid_o <= '0';
    end if;

    data_o.control <= CUFF_IDLE;
    data_o.data <= "--------";

    align_restart_o <= r.align_restart;
    state_o <= r.state;

    sync_sof_o <= '0';
    sync_eof_o <= '0';

    case r.state is
      when LANE_BIT_ALIGN =>
        null;

      when LANE_BUS_ALIGN | LANE_BUS_ALIGN_READY =>
        if r.sync_index = 0 then
          sync_sof_o <= '1';
        end if;
        
        if r.sync_index = 4 then
          sync_eof_o <= '1';
        end if;

      when LANE_DATA =>
        data_o <= cuff_data_decode(r.data);
    end case;
  end process;

  decoder: nsl_line_coding.ibm_8b10b.ibm_8b10b_decoder
    generic map(
      implementation_c => ibm_8b10b_implementation_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      data_i => lane_i,
      data_o => data_s,
      code_error_o => code_error_s,
      disparity_error_o => disparity_error_s
      );

end architecture;
  
