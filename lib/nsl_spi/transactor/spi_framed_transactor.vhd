library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_spi, nsl_io;
use nsl_spi.transactor.all;

entity spi_framed_transactor is
  generic(
    slave_count_c : natural range 1 to 7 := 1
    );
  port(
    clock_i    : in std_ulogic;
    reset_n_i : in std_ulogic;

    sck_o  : out std_ulogic;
    cs_n_o  : out nsl_io.io.opendrain_vector(0 to slave_count_c-1);
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
    ST_SELECTED_PRE,
    ST_SELECTED_POST,
    ST_SHIFT_FIRST_HALF,
    ST_SHIFT_SECOND_HALF,
    ST_DATA_PUT,
    ST_RSP,
    ST_RSP_OUT_ONLY
    );
  
  type regs_t is record
    state      : state_t;
    cmd        : nsl_bnoc.framed.framed_data_t;
    shreg      : std_ulogic_vector(7 downto 0);
    word_count : natural range 0 to 63;
    selected   : natural range 0 to 7;
    bit_count  : natural range 0 to 7;
    last       : std_ulogic;
    div        : unsigned(4 downto 0);
    cnt        : unsigned(4 downto 0);
    sck        : std_ulogic;
    mosi       : std_ulogic;
    cpol       : std_ulogic;
    cpha       : std_ulogic;
  end record;

  signal r, rin: regs_t;
    
begin
  
  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
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
        rin.selected <= 7;
        rin.div <= "10000";
        rin.cnt <= (others => '0');
        rin.cpol <= '0';
        rin.cpha <= '0';

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
            rin.cnt <= r.div;
            if to_integer(unsigned(r.cmd(2 downto 0))) < slave_count_c then
              rin.cpol <= r.cmd(4);
              rin.cpha <= r.cmd(3);
            end if;
            rin.state <= ST_SELECTED_PRE;
            rin.sck <= r.cmd(4);

          elsif std_match(r.cmd, SPI_CMD_SHIFT_IO) then
            rin.state <= ST_DATA_GET;
            rin.word_count <= to_integer(unsigned(r.cmd(5 downto 0)));

          elsif std_match(r.cmd, SPI_CMD_SHIFT_IN) then
            rin.state <= ST_SHIFT_FIRST_HALF;
            rin.sck <= r.cpol xor r.cpha;
            rin.shreg <= (others => '1');
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
          rin.cnt <= r.div;
          rin.last <= cmd_i.last;
          rin.state <= ST_SHIFT_FIRST_HALF;
          rin.sck <= r.cpol xor r.cpha;
          rin.bit_count <= 7;
        end if;
        
      when ST_SELECTED_PRE =>
        if ready then
          rin.cnt <= r.div;
          rin.state <= ST_SELECTED_POST;
          rin.selected <= to_integer(unsigned(r.cmd(2 downto 0)));
        end if;
        
      when ST_SELECTED_POST =>
        if ready then
          rin.cnt <= r.div;
          rin.state <= ST_IDLE;
        end if;
        
      when ST_SHIFT_FIRST_HALF =>
        rin.mosi <= r.shreg(7);

        if ready then
          rin.cnt <= r.div;
          rin.state <= ST_SHIFT_SECOND_HALF;
          rin.sck <= r.cpol xnor r.cpha;
          rin.shreg <= r.shreg(6 downto 0) & miso_i;
        end if;

      when ST_SHIFT_SECOND_HALF =>
        if ready then
          rin.cnt <= r.div;

          rin.bit_count <= (r.bit_count - 1) mod 8;
          if r.bit_count /= 0 then
            rin.state <= ST_SHIFT_FIRST_HALF;
            rin.sck <= r.cpol xor r.cpha;
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
            rin.state <= ST_IDLE;
          elsif std_match(r.cmd, SPI_CMD_SHIFT_IN) then
            rin.word_count <= r.word_count - 1;
            rin.shreg <= (others => '1');
            rin.bit_count <= 7;
            rin.state <= ST_SHIFT_FIRST_HALF;
            rin.sck <= r.cpol xor r.cpha;
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
    sck_o <= r.sck;
    cs_n_o <= (others => (drain_n => '1'));
    cmd_o.ready <= '0';
    rsp_o.valid <= '0';
    rsp_o.last <= '-';
    rsp_o.data <= (others => '-');
    if r.selected < slave_count_c then
      cs_n_o(r.selected).drain_n <= '0';
    end if;
    
    case r.state is
      when ST_RESET | ST_SELECTED_PRE | ST_SELECTED_POST | ST_SHIFT_FIRST_HALF | ST_ROUTE | ST_SHIFT_SECOND_HALF =>
        null;

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
