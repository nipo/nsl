library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package jtag is
  component jtag_tap_register
    generic(
      id    : natural range 1 to 4
      );
    port(
      p_tck     : out std_ulogic;
      p_reset   : out std_ulogic;
      p_selected: out std_ulogic;
      p_capture : out std_ulogic;
      p_shift   : out std_ulogic;
      p_update  : out std_ulogic;
      p_tdi     : out std_ulogic;
      p_tdo     : in  std_ulogic
      );
  end component;

  component jtag_reg
    generic(
      width : integer;
      id    : natural
      );
    port(
      p_clk       : out std_ulogic;
      p_resetn    : out std_ulogic;
      
      p_inbound_data   : out std_ulogic_vector(width-1 downto 0);
      p_inbound_update : out std_ulogic;

      p_outbound_data     : in std_ulogic_vector(width-1 downto 0);
      p_outbound_captured : out std_ulogic
      );
  end component;

  component jtag_inbound_fifo
    generic(
      width : natural;
      id    : natural;
      sync_word_width : natural
      );
    port(
      p_clk       : out std_ulogic;
      p_resetn    : out std_ulogic;
      sync_word : std_ulogic_vector(sync_word_width-1 downto 0);

      p_data  : out std_ulogic_vector(width-1 downto 0);
      p_val   : out std_ulogic
      );
  end component;

  component jtag_outbound_fifo
    generic(
      width : natural;
      id    : natural
      );
    port(
      p_clk       : out std_ulogic;
      p_resetn    : out std_ulogic;

      p_data  : in std_ulogic_vector(width-1 downto 0);
      p_ack   : out std_ulogic
      );
  end component;
  
end package jtag;
