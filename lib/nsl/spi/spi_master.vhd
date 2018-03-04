library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.spi.all;

entity spi_master is
  generic(
    slave_count : natural range 1 to 63 := 1
    );
  port(
    p_clk    : in std_ulogic;
    p_resetn : in std_ulogic;

    p_sck  : out std_ulogic;
    p_csn  : out std_ulogic_vector(0 to slave_count-1);
    p_mosi : out std_ulogic;
    p_miso : in  std_ulogic;

    p_cmd_val : in  nsl.framed.framed_req;
    p_cmd_ack : out nsl.framed.framed_ack;
    p_rsp_val : out nsl.framed.framed_req;
    p_rsp_ack : in  nsl.framed.framed_ack
    );
end entity;

architecture rtl of spi_master is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_DATA_GET,
    ST_SHIFT,
    ST_DATA_PUT,
    ST_RSP
    );
  
  type regs_t is record
    state      : state_t;
    cmd        : std_ulogic_vector(7 downto 0);
    shreg      : std_ulogic_vector(7 downto 0);
    word_count : natural range 0 to 63;
    selected   : natural range 0 to 63;
    bit_count  : natural range 0 to 7;
    last       : std_ulogic;
    div        : unsigned(4 downto 0);
    cnt        : unsigned(4 downto 0);
    sck, mosi  : std_ulogic;
  end record;

  signal r, rin: regs_t;
    
begin
  
  regs: process(p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_cmd_val, p_rsp_ack, p_miso)
    variable ready : boolean;
  begin
    ready := false;
    rin <= r;

    if r.cnt /= (r.cnt'range => '0') then
      rin.cnt <= r.cnt - 1;
    else
      ready := true;
    end if;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.selected <= 63;
        rin.div <= "10000";
        rin.cnt <= (others => '0');
        rin.sck <= '0';

      when ST_IDLE =>
        if p_cmd_val.valid = '1' then
          rin.last <= p_cmd_val.last;
          rin.cmd <= p_cmd_val.data;
          rin.state <= ST_RSP;
        end if;

      when ST_RSP =>
        if p_rsp_ack.ready = '1' then
          rin.state <= ST_IDLE;
          if std_match(r.cmd, SPI_CMD_DIV) then
            rin.div <= unsigned(r.cmd(4 downto 0));

          elsif std_match(r.cmd, SPI_CMD_SELECT) then
            rin.selected <= to_integer(unsigned(r.cmd(4 downto 0)));

          elsif std_match(r.cmd, SPI_CMD_SHIFT_OUT)
            or std_match(r.cmd, SPI_CMD_SHIFT_IO) then
            rin.state <= ST_DATA_GET;
            rin.word_count <= to_integer(unsigned(r.cmd(5 downto 0)));

          elsif std_match(r.cmd, SPI_CMD_SHIFT_IN) then
            rin.state <= ST_SHIFT;
            rin.shreg <= (others => '1');
            rin.bit_count <= 7;
            rin.word_count <= to_integer(unsigned(r.cmd(5 downto 0)));
          end if;
        end if;

      when ST_DATA_GET =>
        if p_cmd_val.valid = '1' then
          rin.shreg <= p_cmd_val.data;
          rin.last <= p_cmd_val.last;
          rin.state <= ST_SHIFT;
          rin.bit_count <= 7;
        end if;
        
      when ST_SHIFT =>
        if ready then
          rin.cnt <= r.div;

          if r.sck = '1' then -- falling edge
            rin.sck <= '0';
            rin.mosi <= r.shreg(7);
          else -- rising edge
            rin.sck <= '1';
            rin.shreg <= r.shreg(6 downto 0) & p_miso;
            rin.bit_count <= (r.bit_count - 1) mod 8;
            if r.bit_count = 0 then
              if std_match(r.cmd, SPI_CMD_SHIFT_IN) or std_match(r.cmd, SPI_CMD_SHIFT_IO) then
                rin.state <= ST_DATA_PUT;
              else
                rin.word_count <= (r.word_count - 1) mod 64;
                if r.word_count /= 0 then
                  rin.state <= ST_DATA_GET;
                else
                  rin.state <= ST_IDLE;
                end if;
              end if;
            end if;
          end if;
        end if;

      when ST_DATA_PUT =>
        if p_rsp_ack.ready = '1' then
          rin.word_count <= (r.word_count - 1) mod 64;

          if r.word_count /= 0 then
            if std_match(r.cmd, SPI_CMD_SHIFT_IN) then
              rin.shreg <= (others => '1');
              rin.bit_count <= 7;
              rin.state <= ST_SHIFT;
            else
              rin.state <= ST_DATA_GET;
            end if;
          else
            rin.state <= ST_IDLE;
          end if;
        end if;

    end case;
  end process;

  moore: process(r)
  begin
    p_sck <= r.sck;
    p_csn <= (others => '1');
    p_mosi <= r.mosi;
    p_cmd_ack.ready <= '0';
    p_rsp_val.valid <= '0';
    p_rsp_val.last <= '-';
    p_rsp_val.data <= (others => '-');
    if r.selected < slave_count then
      p_csn(r.selected) <= '0';
    end if;
    
    case r.state is
      when ST_RESET | ST_SHIFT =>
        null;
        
      when ST_IDLE | ST_DATA_GET =>
        p_cmd_ack.ready <= '1';
        
      when ST_RSP =>
        p_rsp_val.valid <= '1';
        p_rsp_val.data <= r.cmd;
        if std_match(r.cmd, SPI_CMD_SHIFT_IN) or std_match(r.cmd, SPI_CMD_SHIFT_IO) then
          p_rsp_val.last <= '0';
        else
          p_rsp_val.last <= r.last;
        end if;

      when ST_DATA_PUT =>
        p_rsp_val.valid <= '1';
        p_rsp_val.data <= r.shreg;
        if r.word_count = 0 then
          p_rsp_val.last <= r.last;
        else
          p_rsp_val.last <= '0';
        end if;

    end case;
  end process;
  
end architecture;
