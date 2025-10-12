package socket is

  subtype nibble is integer range 0 to 255;
  type ipv4_t is array(integer range 0 to 3) of nibble;

  type sockaddr_in_t is
  record
    ip: ipv4_t;
    prt: integer range 0 to 65535;
  end record;
  
end package;
