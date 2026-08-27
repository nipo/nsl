library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tristated_chunker is
  generic(
    grouped_count : positive;
    chunk0_count : positive;
    chunk1_count : natural;
    chunk2_count : natural;
    chunk3_count : natural;
    chunk4_count : natural;
    chunk5_count : natural;
    chunk6_count : natural;
    chunk7_count : natural
    );
  port(
    grouped_o: out std_logic_vector(grouped_count-1 downto 0);
    grouped_i: in std_logic_vector(grouped_count-1 downto 0) := (others => '0');
    grouped_oe: in std_logic_vector(grouped_count-1 downto 0) := (others => '0');

    chunk0_o: out std_logic_vector(chunk0_count-1 downto 0);
    chunk0_i: in std_logic_vector(chunk0_count-1 downto 0) := (others => '0');
    chunk0_oe: out std_logic_vector(chunk0_count-1 downto 0);

    chunk1_o: out std_logic_vector(chunk1_count-1 downto 0);
    chunk1_i: in std_logic_vector(chunk1_count-1 downto 0) := (others => '0');
    chunk1_oe: out std_logic_vector(chunk1_count-1 downto 0);

    chunk2_o: out std_logic_vector(chunk2_count-1 downto 0);
    chunk2_i: in std_logic_vector(chunk2_count-1 downto 0) := (others => '0');
    chunk2_oe: out std_logic_vector(chunk2_count-1 downto 0);

    chunk3_o: out std_logic_vector(chunk3_count-1 downto 0);
    chunk3_i: in std_logic_vector(chunk3_count-1 downto 0) := (others => '0');
    chunk3_oe: out std_logic_vector(chunk3_count-1 downto 0);

    chunk4_o: out std_logic_vector(chunk4_count-1 downto 0);
    chunk4_i: in std_logic_vector(chunk4_count-1 downto 0) := (others => '0');
    chunk4_oe: out std_logic_vector(chunk4_count-1 downto 0);

    chunk5_o: out std_logic_vector(chunk5_count-1 downto 0);
    chunk5_i: in std_logic_vector(chunk5_count-1 downto 0) := (others => '0');
    chunk5_oe: out std_logic_vector(chunk5_count-1 downto 0);

    chunk6_o: out std_logic_vector(chunk6_count-1 downto 0);
    chunk6_i: in std_logic_vector(chunk6_count-1 downto 0) := (others => '0');
    chunk6_oe: out std_logic_vector(chunk6_count-1 downto 0);

    chunk7_o: out std_logic_vector(chunk7_count-1 downto 0);
    chunk7_i: in std_logic_vector(chunk7_count-1 downto 0) := (others => '0');
    chunk7_oe: out std_logic_vector(chunk7_count-1 downto 0)
    );
end entity;

architecture rtl of tristated_chunker is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_MODE : string;

  attribute X_INTERFACE_MODE of grouped_i : signal is "SLAVE";
  attribute X_INTERFACE_INFO of grouped_o : signal is "nsl:io:tristated:1.0 grouped i";
  attribute X_INTERFACE_INFO of grouped_i : signal is "nsl:io:tristated:1.0 grouped o";
  attribute X_INTERFACE_INFO of grouped_oe: signal is "nsl:io:tristated:1.0 grouped oe";

  attribute X_INTERFACE_MODE of chunk0_i : signal is "MASTER";
  attribute X_INTERFACE_INFO of chunk0_i : signal is "nsl:io:tristated:1.0 chunk0 i";
  attribute X_INTERFACE_INFO of chunk0_o : signal is "nsl:io:tristated:1.0 chunk0 o";
  attribute X_INTERFACE_INFO of chunk0_oe: signal is "nsl:io:tristated:1.0 chunk0 oe";

  attribute X_INTERFACE_MODE of chunk1_i : signal is "MASTER";
  attribute X_INTERFACE_INFO of chunk1_i : signal is "nsl:io:tristated:1.0 chunk1 i";
  attribute X_INTERFACE_INFO of chunk1_o : signal is "nsl:io:tristated:1.0 chunk1 o";
  attribute X_INTERFACE_INFO of chunk1_oe: signal is "nsl:io:tristated:1.0 chunk1 oe";

  attribute X_INTERFACE_MODE of chunk2_i : signal is "MASTER";
  attribute X_INTERFACE_INFO of chunk2_i : signal is "nsl:io:tristated:1.0 chunk2 i";
  attribute X_INTERFACE_INFO of chunk2_o : signal is "nsl:io:tristated:1.0 chunk2 o";
  attribute X_INTERFACE_INFO of chunk2_oe: signal is "nsl:io:tristated:1.0 chunk2 oe";

  attribute X_INTERFACE_MODE of chunk3_i : signal is "MASTER";
  attribute X_INTERFACE_INFO of chunk3_i : signal is "nsl:io:tristated:1.0 chunk3 i";
  attribute X_INTERFACE_INFO of chunk3_o : signal is "nsl:io:tristated:1.0 chunk3 o";
  attribute X_INTERFACE_INFO of chunk3_oe: signal is "nsl:io:tristated:1.0 chunk3 oe";

  attribute X_INTERFACE_MODE of chunk4_i : signal is "MASTER";
  attribute X_INTERFACE_INFO of chunk4_i : signal is "nsl:io:tristated:1.0 chunk4 i";
  attribute X_INTERFACE_INFO of chunk4_o : signal is "nsl:io:tristated:1.0 chunk4 o";
  attribute X_INTERFACE_INFO of chunk4_oe: signal is "nsl:io:tristated:1.0 chunk4 oe";

  attribute X_INTERFACE_MODE of chunk5_i : signal is "MASTER";
  attribute X_INTERFACE_INFO of chunk5_i : signal is "nsl:io:tristated:1.0 chunk5 i";
  attribute X_INTERFACE_INFO of chunk5_o : signal is "nsl:io:tristated:1.0 chunk5 o";
  attribute X_INTERFACE_INFO of chunk5_oe: signal is "nsl:io:tristated:1.0 chunk5 oe";

  attribute X_INTERFACE_MODE of chunk6_i : signal is "MASTER";
  attribute X_INTERFACE_INFO of chunk6_i : signal is "nsl:io:tristated:1.0 chunk6 i";
  attribute X_INTERFACE_INFO of chunk6_o : signal is "nsl:io:tristated:1.0 chunk6 o";
  attribute X_INTERFACE_INFO of chunk6_oe: signal is "nsl:io:tristated:1.0 chunk6 oe";

  attribute X_INTERFACE_MODE of chunk7_i : signal is "MASTER";
  attribute X_INTERFACE_INFO of chunk7_i : signal is "nsl:io:tristated:1.0 chunk7 i";
  attribute X_INTERFACE_INFO of chunk7_o : signal is "nsl:io:tristated:1.0 chunk7 o";
  attribute X_INTERFACE_INFO of chunk7_oe: signal is "nsl:io:tristated:1.0 chunk7 oe";

begin

  assert grouped_count = chunk0_count + chunk1_count + chunk2_count + chunk3_count
    + chunk4_count + chunk5_count + chunk6_count + chunk7_count
    report "Counts should add up"
    severity failure;

  chunk0_o <= grouped_i(chunk0_count-1
                        downto 0);
  chunk1_o <= grouped_i(chunk1_count + chunk0_count-1
                        downto chunk0_count);
  chunk2_o <= grouped_i(chunk2_count + chunk1_count + chunk0_count-1
                        downto chunk1_count + chunk0_count);
  chunk3_o <= grouped_i(chunk3_count + chunk2_count + chunk1_count + chunk0_count-1
                        downto chunk2_count + chunk1_count + chunk0_count);
  chunk4_o <= grouped_i(chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count-1
                        downto chunk3_count + chunk2_count + chunk1_count + chunk0_count);
  chunk5_o <= grouped_i(chunk5_count + chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count-1
                        downto chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count);
  chunk6_o <= grouped_i(chunk6_count + chunk5_count + chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count-1
                        downto chunk5_count + chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count);
  chunk7_o <= grouped_i(chunk7_count + chunk6_count + chunk5_count + chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count-1
                        downto chunk6_count + chunk5_count + chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count);

  chunk0_oe <= grouped_oe(chunk0_count-1
                          downto 0);
  chunk1_oe <= grouped_oe(chunk1_count + chunk0_count-1
                          downto chunk0_count);
  chunk2_oe <= grouped_oe(chunk2_count + chunk1_count + chunk0_count-1
                          downto chunk1_count + chunk0_count);
  chunk3_oe <= grouped_oe(chunk3_count + chunk2_count + chunk1_count + chunk0_count-1
                          downto chunk2_count + chunk1_count + chunk0_count);
  chunk4_oe <= grouped_oe(chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count-1
                          downto chunk3_count + chunk2_count + chunk1_count + chunk0_count);
  chunk5_oe <= grouped_oe(chunk5_count + chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count-1
                          downto chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count);
  chunk6_oe <= grouped_oe(chunk6_count + chunk5_count + chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count-1
                          downto chunk5_count + chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count);
  chunk7_oe <= grouped_oe(chunk7_count + chunk6_count + chunk5_count + chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count-1
                          downto chunk6_count + chunk5_count + chunk4_count + chunk3_count + chunk2_count + chunk1_count + chunk0_count);

  grouped_o <= chunk7_i & chunk6_i & chunk5_i & chunk4_i & chunk3_i & chunk2_i & chunk1_i & chunk0_i;
  
end;
