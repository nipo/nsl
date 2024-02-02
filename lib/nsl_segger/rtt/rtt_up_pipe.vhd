library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight, nsl_bnoc, nsl_data, work;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.pipe.all;
use nsl_coresight.memap_mapper.all;
use work.rtt.all;

entity rtt_up_pipe is
  generic (
    offset_width_c : integer range 9 to 20 := 13;
    control_check_every_c : integer := 8
    );
  port (
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    enable_i: in std_ulogic;
    busy_o: out std_ulogic;
    error_o: out std_ulogic;

    interval_i: in unsigned;
    control_address_i: in unsigned(31 downto 2);
    channel_address_i: in unsigned(31 downto 2);

    data_o : out nsl_bnoc.pipe.pipe_req_t;
    data_i : in nsl_bnoc.pipe.pipe_ack_t;

    memap_cmd_o : out nsl_bnoc.framed.framed_req_t;
    memap_cmd_i : in nsl_bnoc.framed.framed_ack_t;
    memap_rsp_i : in nsl_bnoc.framed.framed_req_t;
    memap_rsp_o : out nsl_bnoc.framed.framed_ack_t
    );
end entity;

architecture beh of rtt_up_pipe is

  subtype interval_t is unsigned(interval_i'length-1 downto 0);
  subtype recheck_t is integer range 0 to control_check_every_c-1;
  subtype pointer_t is unsigned(31 downto 0);
  subtype offset_t is unsigned(offset_width_c-1 downto 0);
  
  type cmd_state_t is (
    CMD_RESET,
    CMD_IDLE,
    CMD_CONTROL_ADDR_CMD,
    CMD_CONTROL_ADDR_VALUE,
    CMD_CONTROL_READ_CMD,
    CMD_CONTROL_WAIT,
    CMD_CONTROL_DECIDE,
    CMD_CONTROL_INTERVAL,
    CMD_CHANNEL_ADDR_CMD,
    CMD_CHANNEL_ADDR_VALUE,
    CMD_CHANNEL_READ_CMD,
    CMD_CHANNEL_WAIT,
    CMD_CHANNEL_DECIDE,
    CMD_CHANNEL_INTERVAL,
    CMD_READ_PREPARE,
    CMD_READ_PREPARE2,
    CMD_READ_ADDR_CMD,
    CMD_READ_ADDR_VALUE,
    CMD_READ_CMD,
    CMD_READ_WAIT,
    CMD_CHANNEL_PTR_ADDR_CMD,
    CMD_CHANNEL_PTR_ADDR_VALUE,
    CMD_CHANNEL_PTR_VALUE_CMD,
    CMD_CHANNEL_PTR_VALUE_VALUE,
    CMD_ERROR
    );

  type rsp_state_t is (
    RSP_RESET,
    RSP_IDLE,
    RSP_ERROR,
    RSP_CONTROL_DATA,
    RSP_CONTROL_STATUS,
    RSP_CHANNEL_DATA,
    RSP_CHANNEL_STATUS,
    RSP_READ_PRE_PAD,
    RSP_READ_DATA_GET,
    RSP_READ_DATA_PUT,
    RSP_READ_POST_PAD,
    RSP_READ_STATUS,
    RSP_CHANNEL_PTR_STATUS
    );

  function aligned(u: unsigned) return unsigned
  is
    alias xu: unsigned(u'length-1 downto 0) is u;
    variable ret: unsigned(u'length-1 downto 0);
  begin
    ret := xu(ret'left downto 2) & "00";
    return ret;
  end function;

  function as32(u: unsigned) return unsigned
  is
    alias xu: unsigned(u'length-1 downto 0) is u;
    variable ret: unsigned(31 downto 0) := (others => '0');
  begin
    ret(xu'range) := xu;
    return ret;
  end function;

  type regs_t is
  record
    cmd_state: cmd_state_t;
    cmd_left: integer range 0 to 3;
    cmd_data: byte_string(0 to 3);
    cmd_recheck: recheck_t;
    cmd_interval: interval_t;

    offset_start_aligned, read_length_aligned, offset_stop_aligned, offset_stop: offset_t;

    rsp_mem_buffer: byte_string(0 to 15);

    rsp_state: rsp_state_t;
    rsp_data: byte;
    rsp_pre_pad: integer range 0 to 3;
    rsp_post_pad: integer range 0 to 3;
    rsp_left: integer range 0 to 255;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.cmd_state <= CMD_RESET;
      r.rsp_state <= RSP_RESET;
    end if;
  end process;

  transition: process(r, enable_i, interval_i,
                      control_address_i, channel_address_i,
                      data_i, memap_cmd_i, memap_rsp_i) is
    variable buffer_address_v: unsigned(31 downto 0);
    variable buffer_length_extra_v: unsigned(31 downto offset_width_c);
    variable buffer_wptr_extra_v: unsigned(31 downto offset_width_c);
    variable buffer_rptr_extra_v: unsigned(31 downto offset_width_c);
    variable buffer_length_v: offset_t;
    variable buffer_wptr_v: offset_t;
    variable buffer_rptr_v: offset_t;
    variable cmd_data_v: unsigned(31 downto 0);
  begin
    rin <= r;

    -- When we just loaded channel structure, in response buffer, we have:
    buffer_address_v := aligned(from_le(r.rsp_mem_buffer(0 to 3)));
    buffer_length_extra_v := from_le(r.rsp_mem_buffer(4 to 7))(31 downto offset_width_c);
    buffer_wptr_extra_v := from_le(r.rsp_mem_buffer(8 to 11))(31 downto offset_width_c);
    buffer_rptr_extra_v := from_le(r.rsp_mem_buffer(12 to 15))(31 downto offset_width_c);
    buffer_length_v := aligned(from_le(r.rsp_mem_buffer(4 to 7))(offset_width_c-1 downto 0));
    buffer_wptr_v := from_le(r.rsp_mem_buffer(8 to 11))(offset_width_c-1 downto 0);
    buffer_rptr_v := from_le(r.rsp_mem_buffer(12 to 15))(offset_width_c-1 downto 0);
    cmd_data_v := from_le(r.cmd_data);
    
    case r.cmd_state is
      when CMD_RESET =>
        rin.cmd_state <= CMD_IDLE;

      when CMD_IDLE =>
        if enable_i = '1' then
          rin.cmd_state <= CMD_CONTROL_ADDR_CMD;
        end if;

      when CMD_CONTROL_ADDR_CMD =>
        if memap_cmd_i.ready = '1' then
          rin.cmd_recheck <= control_check_every_c - 1;
          rin.cmd_data <= to_le(control_address_i & "00");
          rin.cmd_left <= 3;
          rin.cmd_state <= CMD_CONTROL_ADDR_VALUE;
        end if;

      when CMD_CONTROL_ADDR_VALUE =>
        if memap_cmd_i.ready = '1' then
          rin.cmd_data <= shift_left(r.cmd_data);
          if r.cmd_left /= 0 then
            rin.cmd_left <= r.cmd_left - 1;
          else
            rin.cmd_state <= CMD_CONTROL_READ_CMD;
          end if;
        end if;

      when CMD_CONTROL_READ_CMD =>
        if memap_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_CONTROL_WAIT;
        end if;

      when CMD_CONTROL_WAIT =>
        if r.rsp_state = RSP_IDLE then
          rin.cmd_state <= CMD_CONTROL_DECIDE;
        elsif r.rsp_state = RSP_ERROR then
          rin.cmd_state <= CMD_ERROR;
        end if;

      when CMD_CONTROL_DECIDE =>
        if enable_i = '0' then
          rin.cmd_state <= CMD_IDLE;
        elsif std_match(r.rsp_mem_buffer, rtt_control_signature_c) then
          rin.cmd_state <= CMD_CHANNEL_ADDR_CMD;
        else
          rin.cmd_state <= CMD_CONTROL_INTERVAL;
          rin.cmd_interval <= interval_i;
        end if;
        
      when CMD_CONTROL_INTERVAL =>
        if enable_i = '0' then
          rin.cmd_state <= CMD_IDLE;
        elsif r.cmd_interval /= 0 then
          rin.cmd_interval <= r.cmd_interval - 1;
        else
          rin.cmd_state <= CMD_CONTROL_ADDR_CMD;
        end if;

      when CMD_CHANNEL_ADDR_CMD =>
        if memap_cmd_i.ready = '1' then
          -- Skip name, we don't care
          rin.cmd_data <= to_le(unsigned(channel_address_i & "00")
                                + rtt_channel_buffer_offset_c);
          rin.cmd_left <= 3;
          rin.cmd_state <= CMD_CHANNEL_ADDR_VALUE;
        end if;

      when CMD_CHANNEL_ADDR_VALUE =>
        if memap_cmd_i.ready = '1' then
          rin.cmd_data <= shift_left(r.cmd_data);
          if r.cmd_left /= 0 then
            rin.cmd_left <= r.cmd_left - 1;
          else
            rin.cmd_state <= CMD_CHANNEL_READ_CMD;
          end if;
        end if;

      when CMD_CHANNEL_READ_CMD =>
        if memap_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_CHANNEL_WAIT;
        end if;

      when CMD_CHANNEL_WAIT =>
        if r.rsp_state = RSP_IDLE then
          rin.cmd_state <= CMD_CHANNEL_DECIDE;
        elsif r.rsp_state = RSP_ERROR then
          rin.cmd_state <= CMD_ERROR;
        end if;

      when CMD_CHANNEL_INTERVAL =>
        if enable_i = '0' then
          rin.cmd_state <= CMD_IDLE;
        elsif r.cmd_interval /= 0 then
          rin.cmd_interval <= r.cmd_interval - 1;
        elsif r.cmd_recheck /= 0 then
          rin.cmd_recheck <= r.cmd_recheck - 1;
          rin.cmd_state <= CMD_CHANNEL_ADDR_CMD;
        else
          rin.cmd_state <= CMD_CONTROL_ADDR_CMD;
        end if;

      when CMD_CHANNEL_DECIDE =>
        if enable_i = '0' then
          rin.cmd_state <= CMD_IDLE;
        elsif (buffer_rptr_v >= buffer_length_v
               or buffer_wptr_v >= buffer_length_v
               or buffer_address_v = 0
               or buffer_length_v = 0
               or buffer_length_extra_v /= 0
               or buffer_rptr_extra_v /= 0
               or buffer_wptr_extra_v /= 0) then
          rin.cmd_state <= CMD_ERROR;
        elsif buffer_rptr_v /= buffer_wptr_v then
          rin.cmd_state <= CMD_READ_PREPARE;
          rin.offset_start_aligned <= aligned(buffer_rptr_v);
          rin.rsp_pre_pad <= to_integer(buffer_rptr_v(1 downto 0));
          if buffer_rptr_v < buffer_wptr_v then
            rin.offset_stop_aligned <= aligned(buffer_wptr_v + 3);
            rin.offset_stop <= buffer_wptr_v;
          else
            rin.offset_stop_aligned <= buffer_length_v;
            rin.offset_stop <= buffer_length_v;
          end if;
        else
          rin.cmd_state <= CMD_CHANNEL_INTERVAL;
          rin.cmd_interval <= interval_i;
        end if;

      when CMD_READ_PREPARE =>
        rin.read_length_aligned <= r.offset_stop_aligned - r.offset_start_aligned;
        rin.cmd_state <= CMD_READ_PREPARE2;

      when CMD_READ_PREPARE2 =>
        if r.read_length_aligned >= 256 then
          rin.read_length_aligned <= to_unsigned(256, rin.read_length_aligned'length);
          rin.offset_stop_aligned <= r.offset_start_aligned + 256;
          rin.offset_stop <= r.offset_start_aligned + 256;
          rin.rsp_post_pad <= 0;
        else
          rin.rsp_post_pad <= to_integer(r.offset_stop(1 downto 0));
        end if;
        rin.cmd_state <= CMD_READ_ADDR_CMD;

      when CMD_READ_ADDR_CMD =>
        if memap_cmd_i.ready = '1' then
          rin.read_length_aligned <= r.read_length_aligned - 1;
          rin.cmd_left <= 3;
          rin.cmd_data <= to_le(aligned(buffer_address_v + as32(buffer_rptr_v)));
          rin.cmd_state <= CMD_READ_ADDR_VALUE;
        end if;

      when CMD_READ_ADDR_VALUE =>
        if memap_cmd_i.ready = '1' then
          rin.cmd_data <= shift_left(r.cmd_data);
          if r.cmd_left /= 0 then
            rin.cmd_left <= r.cmd_left - 1;
          else
            rin.cmd_state <= CMD_READ_CMD;
          end if;
        end if;

      when CMD_READ_CMD =>
        if memap_cmd_i.ready = '1' then
          rin.cmd_state <= CMD_READ_WAIT;
        end if;

      when CMD_READ_WAIT =>
        if r.rsp_state = RSP_IDLE then
          rin.cmd_state <= CMD_CHANNEL_PTR_ADDR_CMD;
        elsif r.rsp_state = RSP_ERROR then
          rin.cmd_state <= CMD_ERROR;
        end if;

      when CMD_CHANNEL_PTR_ADDR_CMD =>
        if memap_cmd_i.ready = '1' then
          rin.cmd_left <= 3;
          rin.cmd_data <= to_le((channel_address_i & "00")
                                + rtt_channel_rptr_offset_c);
          rin.cmd_state <= CMD_CHANNEL_PTR_ADDR_VALUE;
        end if;

      when CMD_CHANNEL_PTR_ADDR_VALUE =>
        if memap_cmd_i.ready = '1' then
          rin.cmd_data <= shift_left(r.cmd_data);
          if r.cmd_left /= 0 then
            rin.cmd_left <= r.cmd_left - 1;
          else
            rin.cmd_state <= CMD_CHANNEL_PTR_VALUE_CMD;
          end if;
        end if;

      when CMD_CHANNEL_PTR_VALUE_CMD =>
        if memap_cmd_i.ready = '1' then
          rin.cmd_left <= 3;
          if r.offset_stop = buffer_length_v then
            rin.cmd_data <= to_le(as32(""));
          else
            rin.cmd_data <= to_le(as32(r.offset_stop));
          end if;
          rin.cmd_state <= CMD_CHANNEL_PTR_VALUE_VALUE;
        end if;

      when CMD_CHANNEL_PTR_VALUE_VALUE =>
        if memap_cmd_i.ready = '1' then
          rin.cmd_data <= shift_left(r.cmd_data);
          if r.cmd_left /= 0 then
            rin.cmd_left <= r.cmd_left - 1;
          else
            rin.cmd_state <= CMD_CHANNEL_INTERVAL;
            rin.cmd_interval <= interval_i;
          end if;
        end if;

      when CMD_ERROR =>
        if enable_i = '0' then
          rin.cmd_state <= CMD_IDLE;
        end if;
    end case;

    case r.rsp_state is
      when RSP_RESET =>
        rin.rsp_state <= RSP_IDLE;

      when RSP_IDLE =>
        if r.cmd_state = CMD_CONTROL_ADDR_CMD then
          rin.rsp_state <= RSP_CONTROL_DATA;
          rin.rsp_left <= 15;
        elsif r.cmd_state = CMD_CHANNEL_ADDR_CMD then
          rin.rsp_state <= RSP_CHANNEL_DATA;
          rin.rsp_left <= 15;
        elsif r.cmd_state = CMD_READ_ADDR_CMD then
          rin.rsp_left <= to_integer(rin.offset_stop - buffer_rptr_v - 1) mod 256;
          if r.rsp_pre_pad /= 0 then
            rin.rsp_state <= RSP_READ_PRE_PAD;
            rin.rsp_pre_pad <= r.rsp_pre_pad - 1;
          else
            rin.rsp_state <= RSP_READ_DATA_GET;
          end if;
        elsif r.cmd_state = CMD_CHANNEL_PTR_ADDR_CMD then
          rin.rsp_state <= RSP_CHANNEL_PTR_STATUS;
        end if;

      when RSP_ERROR =>
        if enable_i = '0' then
          rin.rsp_state <= RSP_IDLE;
        end if;

      when RSP_CONTROL_DATA =>
        if memap_rsp_i.valid = '1' then
          rin.rsp_mem_buffer <= shift_left(r.rsp_mem_buffer, memap_rsp_i.data);
          if r.rsp_left /= 0 then
            rin.rsp_left <= r.rsp_left - 1;
          else
            rin.rsp_state <= RSP_CONTROL_STATUS;
          end if;
        end if;
          
      when RSP_CONTROL_STATUS | RSP_CHANNEL_STATUS
        | RSP_READ_STATUS | RSP_CHANNEL_PTR_STATUS =>
        if memap_rsp_i.valid = '1' then
          if memap_rsp_i.data(7) /= '0' then
            rin.rsp_state <= RSP_ERROR;
          else
            rin.rsp_state <= RSP_IDLE;
          end if;
        end if;

      when RSP_CHANNEL_DATA =>
        if memap_rsp_i.valid = '1' then
          rin.rsp_mem_buffer <= shift_left(r.rsp_mem_buffer, memap_rsp_i.data);
          if r.rsp_left /= 0 then
            rin.rsp_left <= r.rsp_left - 1;
          else
            rin.rsp_state <= RSP_CONTROL_STATUS;
          end if;
        end if;

      when RSP_READ_PRE_PAD =>
        if memap_rsp_i.valid = '1' then
          if r.rsp_pre_pad /= 0 then
            rin.rsp_pre_pad <= r.rsp_pre_pad - 1;
          else
            rin.rsp_state <= RSP_READ_DATA_GET;
          end if;
        end if;

      when RSP_READ_DATA_GET =>
        if memap_rsp_i.valid = '1' then
          rin.rsp_data <= memap_rsp_i.data;
          rin.rsp_state <= RSP_READ_DATA_PUT;
        end if;

      when RSP_READ_DATA_PUT =>
        if data_i.ready = '1' then
          if r.rsp_left /= 0 then
            rin.rsp_left <= r.rsp_left - 1;
            rin.rsp_state <= RSP_READ_DATA_GET;
          elsif r.rsp_post_pad /= 0 then
            rin.rsp_state <= RSP_READ_POST_PAD;
            rin.rsp_post_pad <= 3 - r.rsp_post_pad;
          else
            rin.rsp_state <= RSP_READ_STATUS;
          end if;
        end if;

      when RSP_READ_POST_PAD =>
        if memap_rsp_i.valid = '1' then
          if r.rsp_post_pad /= 0 then
            rin.rsp_post_pad <= r.rsp_post_pad - 1;
          else
            rin.rsp_state <= RSP_READ_STATUS;
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    case r.cmd_state is
      when CMD_RESET | CMD_IDLE =>
        busy_o <= '0';
        error_o <= '0';

      when CMD_ERROR =>
        busy_o <= '1';
        error_o <= '0';
        
      when others =>
        busy_o <= '1';
        error_o <= '0';
    end case;

    memap_cmd_o <= framed_req_idle_c;
    case r.cmd_state is
      when CMD_RESET | CMD_IDLE | CMD_ERROR
        | CMD_CONTROL_WAIT
        | CMD_CONTROL_DECIDE | CMD_CONTROL_INTERVAL
        | CMD_CHANNEL_WAIT | CMD_CHANNEL_INTERVAL
        | CMD_CHANNEL_DECIDE | CMD_READ_PREPARE | CMD_READ_PREPARE2
        | CMD_READ_WAIT =>
        null;
        
      when CMD_CONTROL_ADDR_CMD | CMD_CHANNEL_ADDR_CMD
        | CMD_READ_ADDR_CMD | CMD_CHANNEL_PTR_ADDR_CMD =>
        memap_cmd_o <= framed_flit(x"45");

      when CMD_CONTROL_ADDR_VALUE | CMD_CHANNEL_ADDR_VALUE
        | CMD_READ_ADDR_VALUE | CMD_CHANNEL_PTR_ADDR_VALUE =>
        memap_cmd_o <= framed_flit(first_left(r.cmd_data));

      when CMD_CHANNEL_PTR_VALUE_VALUE =>
        memap_cmd_o <= framed_flit(first_left(r.cmd_data),
                                   last => r.cmd_left = 0);

      when CMD_CONTROL_READ_CMD | CMD_CHANNEL_READ_CMD =>
        -- Read 4 words
        memap_cmd_o <= framed_flit(x"c3", last => true);

      when CMD_READ_CMD =>
        -- Read as many as aligned words - 1
        -- (substract done in CMD_READ_ADDR_CMD)
        memap_cmd_o <= framed_flit(
          data => std_ulogic_vector("11" & r.read_length_aligned(7 downto 2)),
          last => true);

      when CMD_CHANNEL_PTR_VALUE_CMD =>
        -- Write 1 word
        memap_cmd_o <= framed_flit(x"80");
    end case;

    data_o <= pipe_req_idle_c;
    memap_rsp_o <= framed_accept(false);
    case r.rsp_state is
      when RSP_RESET | RSP_IDLE | RSP_ERROR =>
        null;

      when RSP_CONTROL_DATA
        | RSP_CONTROL_STATUS | RSP_CHANNEL_STATUS
        | RSP_READ_STATUS | RSP_CHANNEL_PTR_STATUS
        | RSP_CHANNEL_DATA | RSP_READ_PRE_PAD
        | RSP_READ_DATA_GET | RSP_READ_POST_PAD =>
        memap_rsp_o <= framed_accept(true);

      when RSP_READ_DATA_PUT =>
        data_o <= pipe_flit(r.rsp_data);
    end case;
  end process;
  
end architecture;
