library ieee;
use ieee.std_logic_1164.all;

package body axi4_lite is

  procedure a32_d32_ms_idle(
    ms   : inout a32_d32_ms) is
  begin
    ms <= a32_d32_ms_defaults;
  end procedure;
  
  procedure a32_d32_sm_idle(
    sm   : inout a32_d32_sm) is
  begin
    sm <= a32_d32_sm_defaults;
  end procedure;

  procedure a32_d32_ms_aw(
    ms   : inout a32_d32_ms;
    addr : in    std_ulogic_vector(31 downto 0)) is
  begin
    ms.awvalid <= '1';
    ms.awaddr <= addr;
  end;
  
  procedure a32_d32_ms_ar(
    ms   : inout a32_d32_ms;
    addr : in    std_ulogic_vector(31 downto 0)) is
  begin
    ms.arvalid <= '1';
    ms.araddr <= addr;
  end;

  procedure a32_d32_ms_b(
    ms : inout a32_d32_ms) is
  begin
    ms.bready <= '1';
  end;

  procedure a32_d32_ms_r(
    ms : inout a32_d32_ms) is
  begin
    ms.rready <= '1';
  end;

  procedure a32_d32_ms_w(
    ms   : inout a32_d32_ms;
    data : in    std_ulogic_vector(31 downto 0);
    strb : in    std_ulogic_vector(3 downto 0)) is
  begin
    ms.wvalid <= '1';
    ms.wdata <= data;
    ms.wstrb <= strb;
  end;


  procedure a32_d32_sm_aw(
    sm : inout a32_d32_sm) is
  begin
    sm.awready <= '1';
  end;

  procedure a32_d32_sm_ar(
    sm : inout a32_d32_sm) is
  begin
    sm.arready <= '1';
  end;

  procedure a32_d32_sm_b(
    sm  : inout a32_d32_sm;
    rsp : in    std_ulogic_vector(1 downto 0)) is
  begin
    sm.bvalid <= '1';
    sm.bresp <= rsp;
  end;

  procedure a32_d32_sm_r(
    sm   : inout a32_d32_sm;
    data : in    std_ulogic_vector(31 downto 0);
    rsp  : in    std_ulogic_vector(1 downto 0)) is
  begin
    sm.rvalid <= '1';
    sm.rresp <= rsp;
    sm.rdata <= data;
  end;

  procedure a32_d32_sm_w(
    sm   : inout a32_d32_sm;
    data : in    std_ulogic_vector(31 downto 0);
    strb : in    std_ulogic_vector(3 downto 0)) is
  begin
    sm.wready <= '1';
  end;


end package body;
