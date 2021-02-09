library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_usb.utmi.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity sie_transfer_router is
  generic (
    in_ep_count_c, out_ep_count_c : endpoint_idx_t
    );
  port (
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;

    transfer_i : in  transfer_cmd;
    transfer_o : out transfer_rsp;

    transfer_ep0_o : out transfer_cmd;
    transfer_ep0_i : in transfer_rsp;

    halted_in_o : out std_ulogic_vector(1 to in_ep_count_c);
    halt_in_i : in std_ulogic_vector(1 to in_ep_count_c);
    clear_in_i : in std_ulogic_vector(1 to in_ep_count_c);

    halted_out_o : out std_ulogic_vector(1 to out_ep_count_c);
    halt_out_i : in std_ulogic_vector(1 to out_ep_count_c);
    clear_out_i : in std_ulogic_vector(1 to out_ep_count_c);

    transfer_in_o : out transfer_cmd_vector(1 to in_ep_count_c);
    transfer_in_i : in transfer_rsp_vector(1 to in_ep_count_c);
    transfer_out_o : out transfer_cmd_vector(1 to out_ep_count_c);
    transfer_out_i : in transfer_rsp_vector(1 to out_ep_count_c)
    );
end entity sie_transfer_router;

architecture beh of sie_transfer_router is
  
  type regs_t is
  record
    ep : endpoint_idx_t;
  end record;

  signal r, rin : regs_t;
  
begin
  
  regs: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, transfer_i)
  begin
    rin <= r;

    rin.ep <= to_integer(transfer_i.ep_no);
  end process;

  rsp_input_select: process(r, transfer_i, transfer_in_i, transfer_out_i,
                            transfer_ep0_i, clear_in_i, clear_out_i,
                            halt_in_i, halt_out_i) is
  begin
    transfer_ep0_o <= TRANSFER_CMD_IDLE;
    for i in transfer_out_o'range
    loop
      transfer_out_o(i) <= TRANSFER_CMD_IDLE;
      transfer_out_o(i).hs <= transfer_i.hs;
    end loop;
    for i in transfer_in_o'range
    loop
      transfer_in_o(i) <= TRANSFER_CMD_IDLE;
      transfer_in_o(i).hs <= transfer_i.hs;
    end loop;
    transfer_o <= TRANSFER_RSP_IDLE;
    
    if transfer_i.ep_no = x"0" then
      transfer_o <= transfer_ep0_i;
      transfer_ep0_o <= transfer_i;
    end if;

    case transfer_i.transfer is
      when TRANSFER_SETUP | TRANSFER_OUT | TRANSFER_PING =>
        for i in transfer_out_i'range
        loop
          if i = r.ep then
            transfer_o <= transfer_out_i(i);
            transfer_out_o(i) <= transfer_i;
          end if;
        end loop;

      when TRANSFER_IN =>
        for i in transfer_in_i'range
        loop
          if i = r.ep then
            transfer_o <= transfer_in_i(i);
            transfer_in_o(i) <= transfer_i;
          end if;
        end loop;

      when others =>
        null;
    end case;

    for i in transfer_out_o'range
    loop
      transfer_out_o(i).clear <= clear_out_i(i);
      transfer_out_o(i).halt <= halt_out_i(i);
      halted_out_o(i) <= transfer_out_i(i).halted;
    end loop;
    for i in transfer_in_o'range
    loop
      transfer_in_o(i).clear <= clear_in_i(i);
      transfer_in_o(i).halt <= halt_in_i(i);
      halted_in_o(i) <= transfer_in_i(i).halted;
    end loop;
  end process;
  
end architecture beh;
