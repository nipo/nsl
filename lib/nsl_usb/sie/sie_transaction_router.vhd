library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_usb.utmi.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity sie_transaction_router is
  generic (
    in_ep_count_c, out_ep_count_c : endpoint_idx_t
    );
  port (
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;

    transaction_i : in  transaction_cmd;
    transaction_o : out transaction_rsp;

    transaction_ep0_o : out transaction_cmd;
    transaction_ep0_i : in transaction_rsp;

    halted_in_o : out std_ulogic_vector(1 to in_ep_count_c);
    halt_in_i : in std_ulogic_vector(1 to in_ep_count_c);
    clear_in_i : in std_ulogic_vector(1 to in_ep_count_c);

    halted_out_o : out std_ulogic_vector(1 to out_ep_count_c);
    halt_out_i : in std_ulogic_vector(1 to out_ep_count_c);
    clear_out_i : in std_ulogic_vector(1 to out_ep_count_c);

    transaction_in_o : out transaction_cmd_vector(1 to in_ep_count_c);
    transaction_in_i : in transaction_rsp_vector(1 to in_ep_count_c);
    transaction_out_o : out transaction_cmd_vector(1 to out_ep_count_c);
    transaction_out_i : in transaction_rsp_vector(1 to out_ep_count_c)
    );
end entity sie_transaction_router;

architecture beh of sie_transaction_router is
  
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

  transition: process(r, transaction_i)
  begin
    rin <= r;

    rin.ep <= to_integer(transaction_i.ep_no);
  end process;

  rsp_input_select: process(r, transaction_i, transaction_in_i, transaction_out_i,
                            transaction_ep0_i, clear_in_i, clear_out_i,
                            halt_in_i, halt_out_i) is
  begin
    transaction_ep0_o <= TRANSACTION_CMD_IDLE;
    for i in transaction_out_o'range
    loop
      transaction_out_o(i) <= TRANSACTION_CMD_IDLE;
      transaction_out_o(i).hs <= transaction_i.hs;
    end loop;
    for i in transaction_in_o'range
    loop
      transaction_in_o(i) <= TRANSACTION_CMD_IDLE;
      transaction_in_o(i).hs <= transaction_i.hs;
    end loop;
    transaction_o <= TRANSACTION_RSP_IDLE;
    
    if transaction_i.ep_no = x"0" then
      transaction_o <= transaction_ep0_i;
      transaction_ep0_o <= transaction_i;
    end if;

    case transaction_i.transaction is
      when TRANSACTION_SETUP | TRANSACTION_OUT | TRANSACTION_PING =>
        for i in transaction_out_i'range
        loop
          if i = r.ep then
            transaction_o <= transaction_out_i(i);
            transaction_out_o(i) <= transaction_i;
          end if;
        end loop;

      when TRANSACTION_IN =>
        for i in transaction_in_i'range
        loop
          if i = r.ep then
            transaction_o <= transaction_in_i(i);
            transaction_in_o(i) <= transaction_i;
          end if;
        end loop;

      when others =>
        null;
    end case;

    for i in transaction_out_o'range
    loop
      transaction_out_o(i).clear <= clear_out_i(i);
      transaction_out_o(i).halt <= halt_out_i(i);
      halted_out_o(i) <= transaction_out_i(i).halted;
    end loop;
    for i in transaction_in_o'range
    loop
      transaction_in_o(i).clear <= clear_in_i(i);
      transaction_in_o(i).halt <= halt_in_i(i);
      halted_in_o(i) <= transaction_in_i(i).halted;
    end loop;
  end process;
  
end architecture beh;
