library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_spi;
use nsl_spi.transactor.all;

entity spi_framed_transactor is
  generic(
    slave_count_c : natural range 1 to 31 := 1
    );
  port(
    clock_i    : in std_ulogic;
    reset_n_i : in std_ulogic;

    sck_o  : out std_ulogic;
    cs_n_o  : out std_ulogic_vector(0 to slave_count_c-1);
    mosi_o : out std_ulogic;
    miso_i : in  std_ulogic;

    cmd_i : in  nsl_bnoc.framed.framed_req;
    cmd_o : out nsl_bnoc.framed.framed_ack;
    rsp_o : out nsl_bnoc.framed.framed_req;
    rsp_i : in  nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of spi_framed_transactor is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_ROUTE,
    ST_DATA_GET,
    ST_INTERFRAME_WAIT,
    ST_SHIFT_SCK_L,
    ST_SHIFT_SCK_H,
    ST_DATA_PUT,
    ST_RSP,
    ST_RSP_OUT_ONLY
    );
  
  type regs_t is record
    state      : state_t;
    cmd        : std_ulogic_vector(7 downto 0);
    shreg      : std_ulogic_vector(7 downto 0);
    word_count : natural range 0 to 63;
    selected   : natural range 0 to 31;
    bit_count  : natural range 0 to 7;
    last       : std_ulogic;
    div        : unsigned(4 downto 0);
    cnt        : unsigned(4 downto 0);
    mosi       : std_ulogic;
  end record;

  signal r, rin: regs_t;
    
begin
  
  regs: process(reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, cmd_i, rsp_i, miso_i)
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
        rin.selected <= 31;
        rin.div <= "10000";
        rin.cnt <= (others => '0');

      when ST_IDLE =>
        if cmd_i.valid = '1' then
          rin.last <= cmd_i.last;
          rin.cmd <= cmd_i.data;
          rin.state <= ST_ROUTE;
        end if;

      when ST_ROUTE =>
        if std_match(r.cmd, SPI_CMD_SHIFT_OUT) then
          rin.state <= ST_DATA_GET;
          rin.word_count <= to_integer(unsigned(r.cmd(5 downto 0)));
        else
          rin.state <= ST_RSP;
        end if;

      when ST_RSP =>
        if rsp_i.ready = '1' then
          rin.state <= ST_IDLE;
          if std_match(r.cmd, SPI_CMD_DIV) then
            rin.div <= unsigned(r.cmd(4 downto 0));

          elsif std_match(r.cmd, SPI_CMD_SELECT) then
            rin.selected <= to_integer(unsigned(r.cmd(4 downto 0)));
            rin.cnt <= r.div;
            rin.state <= ST_INTERFRAME_WAIT;

          elsif std_match(r.cmd, SPI_CMD_SHIFT_IO) then
            rin.state <= ST_DATA_GET;
            rin.word_count <= to_integer(unsigned(r.cmd(5 downto 0)));

          elsif std_match(r.cmd, SPI_CMD_SHIFT_IN) then
            rin.state <= ST_SHIFT_SCK_L;
            rin.shreg <= (others => '1');
            rin.mosi <= '1';
            rin.bit_count <= 7;
            rin.word_count <= to_integer(unsigned(r.cmd(5 downto 0)));
          end if;
        end if;

      when ST_RSP_OUT_ONLY =>
        if rsp_i.ready = '1' then
          rin.state <= ST_IDLE;
        end if;

      when ST_DATA_GET =>
        if cmd_i.valid = '1' then
          rin.shreg <= cmd_i.data;
          rin.mosi <= cmd_i.data(7);
          rin.last <= cmd_i.last;
          rin.state <= ST_SHIFT_SCK_L;
          rin.bit_count <= 7;
        end if;
        
      when ST_INTERFRAME_WAIT =>
        if ready then
          rin.cnt <= r.div;
          rin.state <= ST_IDLE;
        end if;
        
      when ST_SHIFT_SCK_L =>
        if ready then
          rin.cnt <= r.div;
          rin.state <= ST_SHIFT_SCK_H;
          rin.shreg <= r.shreg(6 downto 0) & miso_i;
        end if;

      when ST_SHIFT_SCK_H =>
        if ready then
          rin.cnt <= r.div;
          rin.mosi <= r.shreg(7);
          rin.bit_count <= (r.bit_count - 1) mod 8;

          if r.bit_count /= 0 then
            rin.state <= ST_SHIFT_SCK_L;
          elsif std_match(r.cmd, SPI_CMD_SHIFT_IN)
            or std_match(r.cmd, SPI_CMD_SHIFT_IO) then
            rin.state <= ST_DATA_PUT;
          else -- SPI_CMD_SHIFT_OUT
            if r.word_count /= 0 then
              rin.word_count <= r.word_count - 1;
              rin.state <= ST_DATA_GET;
            else
              rin.state <= ST_RSP_OUT_ONLY;
            end if;
          end if;
        end if;

      when ST_DATA_PUT =>
        if rsp_i.ready = '1' then
          rin.cnt <= r.div;
          if r.word_count = 0 then
            rin.state <= ST_INTERFRAME_WAIT;
          elsif std_match(r.cmd, SPI_CMD_SHIFT_IN) then
            rin.word_count <= r.word_count - 1;
            rin.shreg <= (others => '1');
            rin.mosi <= '1';
            rin.bit_count <= 7;
            rin.state <= ST_SHIFT_SCK_L;
          else -- SPI_CMD_SHIFT_IO
            rin.word_count <= r.word_count - 1;
            rin.state <= ST_DATA_GET;
          end if;
        end if;

    end case;
  end process;

  mosi_o <= r.mosi;

  moore: process(r)
  begin
    sck_o <= '0';
    cs_n_o <= (others => '1');
    cmd_o.ready <= '0';
    rsp_o.valid <= '0';
    rsp_o.last <= '-';
    rsp_o.data <= (others => '-');
    if r.selected < slave_count_c then
      cs_n_o(r.selected) <= '0';
    end if;
    
    case r.state is
      when ST_RESET | ST_INTERFRAME_WAIT | ST_SHIFT_SCK_L | ST_ROUTE =>
        null;

      when ST_SHIFT_SCK_H =>
        sck_o <= '1';

      when ST_IDLE | ST_DATA_GET =>
        cmd_o.ready <= '1';
        
      when ST_RSP | ST_RSP_OUT_ONLY =>
        rsp_o.valid <= '1';
        rsp_o.data <= r.cmd;
        if std_match(r.cmd, SPI_CMD_SHIFT_IN)
          or std_match(r.cmd, SPI_CMD_SHIFT_IO) then
          rsp_o.last <= '0';
        else
          rsp_o.last <= r.last;
        end if;

      when ST_DATA_PUT =>
        rsp_o.valid <= '1';
        rsp_o.data <= r.shreg;
        if r.word_count = 0 then
          rsp_o.last <= r.last;
        else
          rsp_o.last <= '0';
        end if;

    end case;
  end process;
  
end architecture;
