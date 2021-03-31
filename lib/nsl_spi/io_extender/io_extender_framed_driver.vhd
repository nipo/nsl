library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

entity io_extender_framed_driver is
  generic(
    clock_divisor_c : natural range 0 to 2**5-1;
    slave_no_c : natural range 0 to 6
    );
  port(
    reset_n_i    : in std_ulogic;
    clock_i      : in std_ulogic;

    data_i       : in std_ulogic_vector(7 downto 0);

    cmd_i : in  nsl_bnoc.framed.framed_ack;
    cmd_o : out nsl_bnoc.framed.framed_req;
    rsp_o : out nsl_bnoc.framed.framed_ack;
    rsp_i : in  nsl_bnoc.framed.framed_req
    );
end entity;

architecture beh of io_extender_framed_driver is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_DIV,
    ST_SELECT,
    ST_SHIFT_CMD,
    ST_SHIFT_DATA,
    ST_UNSELECT,
    ST_RSP_WAIT
    );
  
  type regs_t is record
    state : state_t;
    data  : nsl_bnoc.framed.framed_data_t;
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

  transition: process(r, cmd_i, rsp_i, data_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_DIV;

      when ST_IDLE =>
        if r.data /= data_i then
          rin.state <= ST_DIV;
        end if;

      when ST_DIV =>
        rin.data <= data_i;
        if cmd_i.ready = '1' then
          rin.state <= ST_SELECT;
        end if;

      when ST_SELECT =>
        if cmd_i.ready = '1' then
          rin.state <= ST_SHIFT_CMD;
        end if;
        
      when ST_SHIFT_CMD =>
        if cmd_i.ready = '1' then
          rin.state <= ST_SHIFT_DATA;
        end if;
        
      when ST_SHIFT_DATA =>
        if cmd_i.ready = '1' then
          rin.state <= ST_UNSELECT;
        end if;
        
      when ST_UNSELECT =>
        if cmd_i.ready = '1' then
          rin.state <= ST_RSP_WAIT;
        end if;
        
      when ST_RSP_WAIT =>
        if rsp_i.valid = '1' and rsp_i.last = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    cmd_o.valid <= '0';
    cmd_o.data <= (others => '-');
    cmd_o.last <= '-';
    rsp_o.ready <= '0';

    case r.state is
      when ST_RESET | ST_IDLE =>
        null;

      when ST_DIV =>
        cmd_o.valid <= '1';
        -- SPI_CMD_DIV | div
        cmd_o.data <= "001" & std_ulogic_vector(to_unsigned(clock_divisor_c, 5));
        cmd_o.last <= '0';
        rsp_o.ready <= '1';

      when ST_SELECT =>
        cmd_o.valid <= '1';
        -- SPI_CMD_SELECT | CPOL- | CPHA0 | no
        cmd_o.data <= "00000" & std_ulogic_vector(to_unsigned(slave_no_c, 3));
        cmd_o.last <= '0';
        rsp_o.ready <= '1';

      when ST_SHIFT_CMD =>
        cmd_o.valid <= '1';
        -- SPI_CMD_SHIFT_OUT | 0
        cmd_o.data <= "10000000";
        cmd_o.last <= '0';
        rsp_o.ready <= '1';

      when ST_SHIFT_DATA =>
        cmd_o.valid <= '1';
        cmd_o.data <= r.data;
        cmd_o.last <= '0';
        rsp_o.ready <= '1';

      when ST_UNSELECT =>
        cmd_o.valid <= '1';
        -- SPI_CMD_UNSELECT
        cmd_o.data <= "00000111";
        cmd_o.last <= '1';
        rsp_o.ready <= '1';

      when ST_RSP_WAIT =>
        rsp_o.ready <= '1';
    end case;
  end process;

end architecture;
