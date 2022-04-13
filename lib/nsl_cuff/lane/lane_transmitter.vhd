library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_cuff, nsl_line_coding;
use nsl_line_coding.ibm_8b10b.all;
use nsl_cuff.protocol.all;
use nsl_cuff.lane.all;
  
entity lane_transmitter is
  generic(
    lane_index_c : natural;
    lane_count_c : natural;
    mtu_l2_c : natural range 0 to 15;
    ibm_8b10b_implementation_c : string := "logic"
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    data_i : in cuff_data_t;
    lane_o : out cuff_code_word_t;

    state_i: in lane_state_t
    );
end entity;

architecture beh of lane_transmitter is

  type regs_t is
  record
    data: cuff_data_t;
    state: lane_state_t;
    sync_index: integer range 0 to 4;
    frame_counter: unsigned(3 downto 0);
  end record;

  signal to_enc_s: nsl_line_coding.ibm_8b10b.data_t;
  
  signal r, rin: regs_t;
  
begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.sync_index <= 0;
      r.frame_counter <= x"0";
    end if;
  end process;

  transition: process(r, data_i, state_i) is
  begin
    rin <= r;

    rin.data <= data_i;
    rin.state <= state_i;
    if r.sync_index /= 4 then
      rin.sync_index <= r.sync_index + 1;
    else
      rin.sync_index <= 0;
      rin.frame_counter <= r.frame_counter + 1;
    end if;
  end process;

  moore: process(r) is
  begin
    case r.state is
      when LANE_BIT_ALIGN | LANE_BUS_ALIGN | LANE_BUS_ALIGN_READY =>
        case r.sync_index is
          when 0 =>
            if lane_index_c /= 0 then
              to_enc_s <= CUFF_SYNC_SOF_SEC;
            elsif r.state = LANE_BUS_ALIGN_READY then
              to_enc_s <= CUFF_SYNC_SOF_READY;
            else
              to_enc_s <= CUFF_SYNC_SOF_MAIN;
            end if;
          when 1 =>
            if lane_index_c = 0 then
              to_enc_s <= data(std_ulogic_vector(to_unsigned(mtu_l2_c, 4))
                               & std_ulogic_vector(to_unsigned(lane_count_c-1, 4)));
            else
              to_enc_s <= CUFF_SYNC_FILL;
            end if;
          when 2 =>
            to_enc_s <= data(std_ulogic_vector(to_unsigned(lane_index_c, 4))
                             & std_ulogic_vector(r.frame_counter));
          when 3 =>
            to_enc_s <= CUFF_SYNC_BITSYNC;
          when 4 =>
            to_enc_s <= CUFF_SYNC_EOF;
        end case;

      when LANE_DATA =>
        to_enc_s <= cuff_data_encode(r.data);
    end case;
  end process;

  enc: nsl_line_coding.ibm_8b10b.ibm_8b10b_encoder
    generic map(
      implementation_c => ibm_8b10b_implementation_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      data_i => to_enc_s,
      data_o => lane_o
      );

end architecture;
