library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_smi, nsl_io, nsl_math;
use nsl_smi.master.all;
  
entity smi_master is
  generic(
    clock_freq_c : natural := 150000000;
    mdc_freq_c : natural := 25000000
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    smi_o  : out nsl_smi.smi.smi_master_o;
    smi_i  : in  nsl_smi.smi.smi_master_i;

    cmd_valid_i : in std_ulogic;
    cmd_ready_o : out std_ulogic;
    cmd_op_i : in smi_op_t;
    -- clause 22 PHYAD, clause 45 PRTAD
    cmd_prtad_phyad_i : in unsigned(4 downto 0);
    -- clause 22 REGAD, clause 45 DEVAD
    cmd_devad_regad_i : in unsigned(4 downto 0);
    -- May be address for clause 45 ADDR_W
    cmd_data_addr_i : in std_ulogic_vector(15 downto 0);

    rsp_valid_o : out std_ulogic;
    rsp_ready_i : in std_ulogic;
    rsp_data_o : out std_ulogic_vector(15 downto 0);
    rsp_error_o : out std_ulogic
    );
end entity;

--                  [     16 bits      ] [16 bits]
--             PRE  ST OP Addresses   TA Data/Addr TA
-- C22 Read  : 1*32 01 10 PHYAD REGAD Z0 Data      Z
-- C22 Write : 1*32 01 01 PHYAD REGAD 10 Data      Z
-- C45 Addr  : 1*32 00 00 PRTAD DEVAD 10 Address   Z
-- C45 Write : 1*32 00 01 PRTAD DEVAD 10 Data      Z
-- C45 ReadI : 1*32 00 10 PRTAD DEVAD Z0 Data      Z
-- C45 Read  : 1*32 00 11 PRTAD DEVAD Z0 Data      Z

architecture beh of smi_master is

  constant div_init_c : integer := nsl_math.arith.max((clock_freq_c + mdc_freq_c) / mdc_freq_c / 2 - 1, 1);
  
  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_STARTING,
    ST_PRE,
    ST_CMD,
    ST_DATA,
    ST_DONE,
    ST_RSP_PUT
    );
  
  type regs_t is
  record
    clock   : std_ulogic;
    divisor : integer range 0 to div_init_c;
    prtad   : std_ulogic_vector(4 downto 0);
    devad   : std_ulogic_vector(4 downto 0);
    data    : std_ulogic_vector(15 downto 0);
    mdio    : nsl_io.io.directed;
    op      : smi_op_t;
    shreg   : std_ulogic_vector(15 downto 0);
    state   : state_t;
    bit_count : integer range 0 to 31;
    error   : std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  reg: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, smi_i, rsp_ready_i,
                      cmd_valid_i, cmd_op_i, cmd_prtad_phyad_i,
                      cmd_devad_regad_i, cmd_data_addr_i)
    variable rising, falling : boolean;
  begin
    rin <= r;

    rising := false;
    falling := false;

    if r.divisor /= 0 then
      rin.divisor <= r.divisor - 1;
    else
      rin.divisor <= div_init_c;
      rising := r.clock = '0';
      falling := r.clock = '1';
      rin.clock <= not r.clock;
    end if;
    
    case r.state is
      when ST_RESET =>
        rin.divisor <= 0;
        rin.clock <= '0';
        rin.state <= ST_IDLE;
        rin.mdio <= (v => '-', output => '0');

      when ST_IDLE =>
        rin.mdio <= (v => '-', output => '0');
        rin.clock <= '0';
        if cmd_valid_i = '1' then
          rin.state <= ST_STARTING;
          rin.prtad <= std_ulogic_vector(cmd_prtad_phyad_i);
          rin.devad <= std_ulogic_vector(cmd_devad_regad_i);
          rin.data <= cmd_data_addr_i;
          rin.op <= cmd_op_i;
        end if;

      when ST_STARTING =>
        rin.mdio <= (v => '-', output => '0');
        if rising then
          rin.bit_count <= 31;
          rin.state <= ST_PRE;
        end if;

      when ST_PRE =>
        rin.mdio.v <= '1';
        rin.mdio.output <= '1';
        if rising then
          if r.bit_count /= 0 then
            rin.bit_count <= r.bit_count - 1;
          else
            rin.error <= '0';
            rin.state <= ST_CMD;
            rin.bit_count <= 15;
            case r.op is
              when SMI_C45_ADDR =>
                rin.shreg <= "0000" & r.prtad & r.devad & "10";
              when SMI_C45_WRITE =>
                rin.shreg <= "0001" & r.prtad & r.devad & "10";
              when SMI_C45_READ =>
                rin.shreg <= "0011" & r.prtad & r.devad & "--";
              when SMI_C45_READINC =>
                rin.shreg <= "0010" & r.prtad & r.devad & "--";
              when SMI_C22_READ =>
                rin.shreg <= "0110" & r.prtad & r.devad & "--";
              when SMI_C22_WRITE =>
                rin.shreg <= "0101" & r.prtad & r.devad & "10";
            end case;
          end if;
        end if;

      when ST_CMD =>
        if falling then
          rin.mdio.v <= r.shreg(15);
          rin.mdio.output <= '1';

          case r.op is
            when SMI_C45_READINC | SMI_C45_READ | SMI_C22_READ =>
              if r.bit_count <= 1 then
                rin.mdio.output <= '0';
              end if;
            when others =>
              null;
          end case;
        end if;

        if rising then
          rin.shreg <= r.shreg(14 downto 0) & "-";
          if r.bit_count /= 0 then
            rin.bit_count <= r.bit_count - 1;
          else
            rin.bit_count <= 15;
            rin.state <= ST_DATA;
            case r.op is
              when SMI_C45_ADDR | SMI_C45_WRITE | SMI_C22_WRITE =>
                rin.shreg <= r.data;
              when SMI_C45_READINC | SMI_C45_READ | SMI_C22_READ =>
                if smi_i.mdio = '0' then
                  rin.error <= '0';
                else
                  rin.error <= '1';
                end if;
                rin.shreg <= (others => '-');
            end case;
          end if;
        end if;

      when ST_DATA =>
        if falling then
          case r.op is
            when SMI_C45_ADDR | SMI_C45_WRITE | SMI_C22_WRITE =>
              rin.mdio.v <= r.shreg(15);
              rin.mdio.output <= '1';
            when SMI_C45_READINC | SMI_C45_READ | SMI_C22_READ =>
              rin.mdio.v <= '-';
              rin.mdio.output <= '0';
          end case;
        end if;

        if rising then
          rin.shreg <= r.shreg(14 downto 0) & smi_i.mdio;
          if r.bit_count /= 0 then
            rin.bit_count <= r.bit_count - 1;
          else
            rin.state <= ST_DONE;
          end if;
        end if;

      when ST_DONE =>
        if falling then
          rin.mdio.v <= '-';
          rin.mdio.output <= '0';
        end if;

        if rising then
          rin.state <= ST_RSP_PUT;
          rin.data <= r.shreg;
        end if;

      when ST_RSP_PUT =>
        if rsp_ready_i = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    smi_o.mdc <= r.clock;
    smi_o.mdio <= r.mdio;

    cmd_ready_o <= '0';
    rsp_valid_o <= '0';
    rsp_error_o <= '-';
    rsp_data_o <= (others => '-');

    case r.state is
      when ST_RESET | ST_STARTING | ST_PRE | ST_CMD | ST_DATA | ST_DONE =>
        null;

      when ST_IDLE =>
        cmd_ready_o <= '1';

      when ST_RSP_PUT =>
        rsp_data_o <= r.data;
        rsp_error_o <= r.error;
        rsp_valid_o <= '1';
    end case;
  end process;

end architecture;
