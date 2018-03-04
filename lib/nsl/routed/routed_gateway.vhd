library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.routed.all;
library hwdep;
use hwdep.ram.all;

entity routed_gateway is
  generic(
    source_id: nsl.routed.component_id;
    target_id: nsl.routed.component_id
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_cmd_in_val   : in nsl.routed.routed_req;
    p_cmd_in_ack   : out nsl.routed.routed_ack;
    p_cmd_out_val   : out nsl.routed.routed_req;
    p_cmd_out_ack   : in nsl.routed.routed_ack;

    p_rsp_in_val   : in nsl.routed.routed_req;
    p_rsp_in_ack   : out nsl.routed.routed_ack;
    p_rsp_out_val   : out nsl.routed.routed_req;
    p_rsp_out_ack   : in nsl.routed.routed_ack
    );
end entity;

architecture rtl of routed_gateway is

  type cmd_state_t is (
    CMD_RESET,
    CMD_GET_HEADER,
    CMD_GET_HEADER2,
    CMD_GET_TAG,
    CMD_PUT_TABLE,
    CMD_PUT_HEADER,
    CMD_PUT_TAG,
    CMD_FORWARD
    );

  type rsp_state_t is (
    RSP_RESET,
    RSP_GET_HEADER,
    RSP_GET_TAG,
    RSP_PUT_HEADER,
    RSP_PUT_HEADER2,
    RSP_PUT_TAG,
    RSP_FORWARD
    );

  constant tag_size: natural := 4;
  
  type regs_t is record
    cmd_from: std_ulogic_vector(3 downto 0);
    cmd_to2: nsl.routed.component_id;
    cmd_tag: nsl.framed.framed_data_t;
    cmd_state: cmd_state_t;

    next_tag: unsigned(tag_size-1 downto 0);

    rsp_from2: nsl.routed.component_id;
    rsp_state: rsp_state_t;
  end record;  

  signal r, rin: regs_t;

  signal s_lut_read, s_lut_write : std_ulogic;
  signal s_lut_tag: std_ulogic_vector(7 downto 0);
  signal s_lut_source: std_ulogic_vector(3 downto 0);
  
begin

  regs: process(p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.cmd_state <= CMD_RESET;
      r.rsp_state <= RSP_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  lut: hwdep.ram.ram_2p_r_w
    generic map(
      addr_size => tag_size,
      data_size => s_lut_tag'length + s_lut_source'length
      )
    port map(
      p_clk(0) => p_clk,

      p_waddr => std_ulogic_vector(r.next_tag),
      p_wen => s_lut_write,
      p_wdata(11 downto 8) => r.cmd_from,
      p_wdata(7 downto 0) => r.cmd_tag,

      p_raddr => p_rsp_in_val.data(tag_size-1 downto 0),
      p_ren => s_lut_read,
      p_rdata(11 downto 8) => s_lut_source,
      p_rdata(7 downto 0) => s_lut_tag
      );

  s_lut_write <= '1' when r.cmd_state = CMD_PUT_TABLE else '0';
  s_lut_read <= p_rsp_in_val.valid when r.rsp_state = RSP_GET_TAG else '0';
  
  transition: process(p_cmd_in_val, p_cmd_out_ack, p_rsp_in_val, p_rsp_out_ack, r)
  begin
    rin <= r;

    case r.cmd_state is
      when CMD_RESET =>
        rin.cmd_state <= CMD_GET_HEADER;

      when CMD_GET_HEADER =>
        if p_cmd_in_val.valid = '1' then
          rin.cmd_from <= std_ulogic_vector(to_unsigned(nsl.routed.routed_header_src(p_cmd_in_val.data), 4));
          rin.cmd_state <= CMD_GET_HEADER2;
        end if;
        
      when CMD_GET_HEADER2 =>
        if p_cmd_in_val.valid = '1' then
          rin.cmd_to2 <= nsl.routed.routed_header_dst(p_cmd_in_val.data);
          rin.cmd_state <= CMD_GET_TAG;
        end if;
        
      when CMD_GET_TAG =>
        if p_cmd_in_val.valid = '1' then
          rin.cmd_tag <= p_cmd_in_val.data;
          rin.cmd_state <= CMD_PUT_TABLE;
        end if;
        
      when CMD_PUT_TABLE =>
        rin.cmd_state <= CMD_PUT_HEADER;
        
      when CMD_PUT_HEADER =>
        if p_cmd_out_ack.ready = '1' then
          rin.cmd_state <= CMD_PUT_TAG;
        end if;
        
      when CMD_PUT_TAG =>
        if p_cmd_out_ack.ready = '1' then
          rin.cmd_state <= CMD_FORWARD;
          rin.next_tag <= r.next_tag + 1;
        end if;

      when CMD_FORWARD =>
        if p_cmd_in_val.valid = '1' and p_cmd_out_ack.ready = '1' and p_cmd_in_val.last = '1' then
          rin.cmd_state <= CMD_GET_HEADER;
        end if;
    end case;

    case r.rsp_state is
      when RSP_RESET =>
        rin.rsp_state <= RSP_GET_HEADER;

      when RSP_GET_HEADER =>
        if p_rsp_in_val.valid = '1' then
          rin.rsp_state <= RSP_GET_TAG;
          rin.rsp_from2 <= nsl.routed.routed_header_src(p_cmd_in_val.data);
        end if;
        
      when RSP_GET_TAG =>
        if p_rsp_in_val.valid = '1' then
          rin.rsp_state <= RSP_PUT_HEADER;
        end if;
        
      when RSP_PUT_HEADER =>
        if p_rsp_out_ack.ready = '1' then
          rin.rsp_state <= RSP_PUT_HEADER2;
        end if;
        
      when RSP_PUT_HEADER2 =>
        if p_rsp_out_ack.ready = '1' then
          rin.rsp_state <= RSP_PUT_TAG;
        end if;
        
      when RSP_PUT_TAG =>
        if p_rsp_out_ack.ready = '1' then
          rin.rsp_state <= RSP_FORWARD;
        end if;

      when RSP_FORWARD =>
        if p_rsp_in_val.valid = '1' and p_rsp_out_ack.ready = '1' and p_rsp_in_val.last = '1' then
          rin.rsp_state <= RSP_GET_HEADER;
        end if;
    end case;
  end process;

  mux: process(r, p_cmd_in_val, p_cmd_out_ack, p_rsp_in_val, p_rsp_out_ack)
  begin
    p_cmd_out_val.valid <= '0';
    p_cmd_out_val.data <= (others => '-');
    p_cmd_out_val.last <= '-';
    p_cmd_in_ack.ready <= '0';

    p_rsp_out_val.valid <= '0';
    p_rsp_out_val.data <= (others => '-');
    p_rsp_out_val.last <= '-';
    p_rsp_in_ack.ready <= '0';

    case r.cmd_state is
      when CMD_RESET =>
        null;
        
      when CMD_GET_HEADER | CMD_GET_HEADER2 | CMD_GET_TAG =>
        p_cmd_in_ack.ready <= '1';
        
      when CMD_PUT_TABLE =>
        rin.cmd_state <= CMD_PUT_HEADER;
        
      when CMD_PUT_HEADER =>
        p_cmd_out_val.valid <= '1';
        p_cmd_out_val.data <= nsl.routed.routed_header(r.cmd_to2, source_id);
        p_cmd_out_val.last <= '0';
        
      when CMD_PUT_TAG =>
        p_cmd_out_val.valid <= '1';
        p_cmd_out_val.data(tag_size-1 downto 0) <= std_ulogic_vector(r.next_tag);
        p_cmd_out_val.last <= '0';

      when CMD_FORWARD =>
        p_cmd_out_val <= p_cmd_in_val;
        p_cmd_in_ack <= p_cmd_out_ack;
    end case;

    case r.rsp_state is
      when RSP_RESET =>
        null;

      when RSP_GET_HEADER | RSP_GET_TAG =>
        p_rsp_in_ack.ready <= '1';
        
      when RSP_PUT_HEADER =>
        p_rsp_out_val.valid <= '1';
        p_rsp_out_val.data <= nsl.routed.routed_header(to_integer(unsigned(s_lut_source)), target_id);
        p_rsp_out_val.last <= '0';
        
      when RSP_PUT_HEADER2 =>
        p_rsp_out_val.valid <= '1';
        p_rsp_out_val.data <= nsl.routed.routed_header(0, r.rsp_from2);
        p_rsp_out_val.last <= '0';
        
      when RSP_PUT_TAG =>
        p_rsp_out_val.valid <= '1';
        p_rsp_out_val.data <= s_lut_tag;
        p_rsp_out_val.last <= '0';

      when RSP_FORWARD =>
        p_rsp_out_val <= p_rsp_in_val;
        p_rsp_in_ack <= p_rsp_out_ack;
    end case;

  end process;
    
end architecture;
