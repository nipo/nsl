library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_bnoc, nsl_data, nsl_logic;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.logic.all;
use nsl_logic.bool.all;

entity spi_fifo_transport_master is
  generic(
    width_c : positive
    );
  port(
    -- clocks the fifo
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;

    enable_i    : in std_ulogic := '1';
    div_i       : in unsigned(6 downto 0);
    cpol_i      : in std_ulogic := '0';
    cpha_i      : in std_ulogic := '0';
    cs_i        : in unsigned(2 downto 0);

    irq_n_i     : in std_ulogic := '0';

    tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
    tx_valid_i  : in  std_ulogic;
    tx_ready_o  : out std_ulogic;

    rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
    rx_valid_o  : out std_ulogic;
    rx_ready_i  : in  std_ulogic;

    cmd_o : out framed_req;
    cmd_i : in  framed_ack;
    rsp_i : in  framed_req;
    rsp_o : out framed_ack
    );
end entity;

architecture beh of spi_fifo_transport_master is

  subtype data_t is std_ulogic_vector(width_c-1 downto 0);
  
  -- Ready, Valid, Data[width_c]
  constant ready_pos_c : integer := width_c+1;
  constant valid_pos_c : integer := width_c;
  constant shift_width_c : integer := width_c + 2;
  constant byte_count_c : integer := (shift_width_c + 7) / 8;

  constant leftover_width_c : integer := shift_width_c mod 8;
  constant has_size_change_c : boolean := leftover_width_c /= 0;
  
  constant common_length_c : integer :=
    (0
     + 2 -- DIVH / DIVL
     + 1 -- Select
     + if_else(shift_width_c < 8,
               1 + 1 + byte_count_c, -- Size, Shift cmd, Data
               if_else(has_size_change_c,
                       1 + 1 + 1 + 1 + byte_count_c, -- Size, Shift cmd, Data[0], Size, Shift cmd, Data[1:]
                       1 + byte_count_c -- Shift cmd, data
                       )
               )
     );

  constant cmd_length_c : integer := common_length_c
                                     + 1 -- Unselect
                                     + 1 -- shift
                                     ;

  constant rsp_length_c : integer := common_length_c;

  function cmd_build(ready, valid: boolean;
                     data: data_t;
                     div: unsigned(6 downto 0);
                     cpol, cpha: std_ulogic;
                     cs: unsigned(2 downto 0))
    return byte_string
  is
    constant deselect_c: byte := x"07";
    constant pad_c: byte := x"40";
    variable cmd_bitstream: std_ulogic_vector(byte_count_c*8-1 downto 0) := (others => '0');
    variable cmd_bytestream: byte_string(0 to byte_count_c-1);
    variable ret: byte_string(0 to cmd_length_c-1) := (others => pad_c);
  begin
    cmd_bitstream(ready_pos_c) := to_logic(ready);
    cmd_bitstream(valid_pos_c) := to_logic(valid);
    cmd_bitstream(width_c-1 downto 0) := data;

    cmd_bytestream := to_be(unsigned(cmd_bitstream));

    ret(0) := "0010" & std_ulogic_vector(div(6 downto 3));
    ret(1) := "00110" & std_ulogic_vector(div(2 downto 0));
    ret(2) := "000" & cpol & cpha & std_ulogic_vector(cs);
    if shift_width_c < 8 then
      ret(3) := "00111" & std_ulogic_vector(to_unsigned(leftover_width_c-1, 3));
      ret(4) := "11000000";
      ret(5) := cmd_bytestream(0);
      ret(6) := deselect_c;
    elsif byte_count_c > 1 and has_size_change_c then
      ret(3) := "00111" & std_ulogic_vector(to_unsigned(leftover_width_c-1, 3));
      ret(4) := "11000000";
      ret(5) := cmd_bytestream(0);
      ret(6) := "00111111";
      ret(7) := "11" & std_ulogic_vector(to_unsigned(byte_count_c-2, 6));
      ret(8 to 8+byte_count_c-2) := cmd_bytestream(1 to cmd_bytestream'right);
      ret(8+byte_count_c-1) := deselect_c;
    else -- multiple of 8-bits
      ret(3) := "11" & std_ulogic_vector(to_unsigned(byte_count_c-1, 6));
      ret(4 to 4+byte_count_c-1) := cmd_bytestream;
      ret(4+byte_count_c) := deselect_c;
    end if;

    return ret;
  end function;

  function rsp_select_build
    return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(0 to rsp_length_c-1) := (others => '0');
  begin
    if shift_width_c < 8 then
      ret(5) := '1';
    elsif byte_count_c > 1 and has_size_change_c then
      ret(5) := '1';
      ret(8 to 8+byte_count_c-2) := (others => '1');
    else -- multiple of 8-bits
      ret(4 to 4+byte_count_c-1) := (others => '1');
    end if;

    return ret;
  end function;

  type cmd_state_t is (
    ST_CMD_RESET,
    ST_CMD_IDLE,
    ST_CMD_RUN,
    ST_CMD_WAIT
    );

  type rsp_state_t is (
    ST_RSP_RESET,
    ST_RSP_IDLE,
    ST_RSP_RUN,
    ST_RSP_COMPLETE
    );
 
  type regs_t is
  record
    cmd_state : cmd_state_t;
    rsp_state : rsp_state_t;

    cmd_stream : byte_string(0 to cmd_length_c - 1);
    cmd_left: integer range 0 to cmd_length_c - 1;
    cmd_ready, cmd_valid : boolean;

    rsp_select : std_ulogic_vector(0 to rsp_length_c - 1);
    rsp_data : byte_string(0 to byte_count_c - 1);

    rx_data, tx_data: std_ulogic_vector(width_c-1 downto 0);
    rx_valid, tx_valid: std_ulogic;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.cmd_state <= ST_CMD_RESET;
      r.rsp_state <= ST_RSP_RESET;
      r.tx_valid <= '0';
      r.tx_data <= (others => '0');
      r.rx_valid <= '0';
    end if;
  end process;

  transition: process(r, irq_n_i, cmd_i, rsp_i,
                      tx_data_i, tx_valid_i, rx_ready_i,
                      enable_i, cs_i, cpol_i, cpha_i, div_i)
    variable spi_data : std_ulogic_vector(byte_count_c*8-1 downto 0);
  begin
    rin <= r;

    spi_data := std_ulogic_vector(from_be(r.rsp_data));

    if rx_ready_i = '1' then
      rin.rx_valid <= '0';
    end if;

    if r.cmd_state /= ST_CMD_RESET and r.tx_valid = '0' and tx_valid_i = '1' then
      rin.tx_valid <= '1';
      rin.tx_data <= tx_data_i;
    end if;
    
    case r.cmd_state is
      when ST_CMD_RESET =>
        rin.cmd_state <= ST_CMD_IDLE;

      when ST_CMD_IDLE =>
        if enable_i = '1' and (irq_n_i = '0' or r.tx_valid = '1') then
          rin.cmd_stream <= cmd_build(
            ready => r.rx_valid = '0',
            valid => r.tx_valid = '1',
            data => r.tx_data,
            div => div_i,
            cpol => cpol_i,
            cpha => cpha_i,
            cs => cs_i);
          rin.cmd_ready <= r.rx_valid = '0';
          rin.cmd_valid <= r.tx_valid = '1';
          rin.cmd_left <= cmd_length_c-1;
          rin.rsp_select <= rsp_select_build;
          rin.cmd_state <= ST_CMD_RUN;
        end if;

      when ST_CMD_RUN =>
        if cmd_i.ready = '1' then
          rin.cmd_stream <= shift_left(r.cmd_stream, first_right(r.cmd_stream));
          if r.cmd_left /= 0 then
            rin.cmd_left <= r.cmd_left - 1;
          else
            rin.cmd_state <= ST_CMD_WAIT;
          end if;
        end if;

      when ST_CMD_WAIT =>
        if r.rsp_state = ST_RSP_IDLE then
          rin.cmd_state <= ST_CMD_IDLE;
        end if;
    end case;

    case r.rsp_state is
      when ST_RSP_RESET =>
        rin.rsp_state <= ST_RSP_IDLE;

      when ST_RSP_IDLE =>
        if r.cmd_state = ST_CMD_RUN then
          rin.rsp_state <= ST_RSP_RUN;
        end if;

      when ST_RSP_RUN =>
        if rsp_i.valid = '1' then
          if r.rsp_select(0) = '1' then
            rin.rsp_data <= shift_left(r.rsp_data, rsp_i.data);
          end if;

          rin.rsp_select <= r.rsp_select(1 to r.rsp_select'right) & '0';

          if rsp_i.last = '1' then
            rin.rsp_state <= ST_RSP_COMPLETE;
          end if;
        end if;

      when ST_RSP_COMPLETE =>
        if r.cmd_ready and spi_data(valid_pos_c) = '1' then
          rin.rx_data <= spi_data(width_c-1 downto 0);
          rin.rx_valid <= '1';
        end if;

        if r.cmd_valid and spi_data(ready_pos_c) = '1' then
          rin.tx_valid <= '0';
          rin.tx_data <= (others => '0');
        end if;

        rin.rsp_state <= ST_RSP_IDLE;
    end case;
  end process;

  moore: process(r)
  begin
    tx_ready_o <= '0';
    if r.cmd_state /= ST_CMD_RESET and r.tx_valid = '0' then
      tx_ready_o <= '1';
    end if;
    
    rx_valid_o <= r.rx_valid;
    rx_data_o <= r.rx_data;
    
    case r.cmd_state is
      when ST_CMD_RESET | ST_CMD_IDLE | ST_CMD_WAIT =>
        cmd_o <= framed_req_idle_c;

      when ST_CMD_RUN =>
        cmd_o <= framed_flit(data => first_left(r.cmd_stream),
                             last => r.cmd_left = 0);
    end case;

    case r.rsp_state is
      when ST_RSP_RESET | ST_RSP_IDLE | ST_RSP_COMPLETE =>
        rsp_o <= framed_ack_idle_c;

      when ST_RSP_RUN =>
        rsp_o <= framed_accept(true);
    end case;
  end process;

end architecture;
