library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic;
use nsl_logic.bool.if_else;
use work.ibm_8b10b.all;

-- 8b/10b codec implemented "by the book".
--
-- Decoder does not catch all disparity errors.  This is of low
-- importance for real-life scenarios.
package ibm_8b10b_spec is

  procedure encode(
    data_i      : in data_t;
    disparity_i : in std_ulogic;

    data_o      : out code_word_t;
    disparity_o : out std_ulogic
    );

  procedure decode(
    data_i      : in code_word_t;
    disparity_i : in std_ulogic;

    data_o            : out data_t;
    disparity_o       : out std_ulogic;
    code_error_o      : out std_ulogic;
    disparity_error_o : out std_ulogic
    );

end package;

package body ibm_8b10b_spec is

  -- Based on verilog works by Chuck Benz, 2002.

  -- The information and description contained herein is the
  -- property of Chuck Benz.
  --
  -- Permission is granted for any reuse of this information
  -- and description as long as this copyright notice is
  -- preserved.  Modifications may be made as long as this
  -- notice is preserved

  procedure decode(
    data_i : in code_word_t;
    disparity_i : in std_ulogic;

    data_o            : out data_t;
    disparity_o       : out std_ulogic;
    code_error_o      : out std_ulogic;
    disparity_error_o : out std_ulogic)
  is
    variable a, b, c, d, e, f, g, h, i, j : std_ulogic;
    variable abei, aeqb, ceqd, feqg, heqj : std_ulogic;
    variable fghj22, fghjp13, fghjp31 : std_ulogic;
    variable anbnenin : std_ulogic;
    variable disp4n, disp4p, disp6a, disp6a0, disp6a2, disp6b, disp6n, disp6p : std_ulogic;
    variable k28p : std_ulogic;
    variable p04, p13, p22, p31, p40, p13dei, p13en, p13in, p31e, p31i : std_ulogic;
    variable p22aceeqi, p22ancneeqi, p22bceeqi, p22bncneeqi : std_ulogic;
  begin
    a := data_i(0);
    b := data_i(1);
    c := data_i(2);
    d := data_i(3);
    e := data_i(4);
    i := data_i(5);
    f := data_i(6);
    g := data_i(7);
    h := data_i(8);
    j := data_i(9);

    aeqb     := a xnor b;
    ceqd     := c xnor d;
    anbnenin := not (a or b or e or i);
    abei     := a and b and e and i;

    p04 := not (a or b or c or d);
    p13 := (not aeqb and not c and not d) or (not ceqd and not a and not b);
    p22 := (a and b and not c and not d) or (c and d and not a and not b) or (not aeqb and not ceqd);
    p31 := (not aeqb and c and d) or (not ceqd and a and b);
    p40 := a and b and c and d;

    p13in       := p13 and not i;
    p31i        := p31 and i;
    p13dei      := p13 and d and e and i;
    p22aceeqi   := p22 and a and c and (e xnor i);
    p22ancneeqi := p22 and not a and not c and (e xnor i);
    p13en       := p13 and not e;
    p31e        := p31 and e;

    k28p := not (c or d or e or i);

    disp6a := p31 or (p22 and disparity_i);
    disp6a2 := p31 and disparity_i;
    disp6a0 := p13 and not disparity_i;
    disp6b := ((e and i and not disp6a0)
               or (disp6a and (e or i))
               or disp6a2
               or (e and i and d))
              and (e or i or d);
    disp6p := (p31 and (e or i)) or (p22 and e and i);
    disp6n := (p13 and (not (e and i))) or (p22 and not e and not i);

    p22bceeqi := p22 and b and c and (e xnor i);
    p22bncneeqi := p22 and not b and not c and (e xnor i);

    feqg := f xnor g;
    heqj := h xnor j;

    fghj22 := (f and g and not h and not j)
              or (not f and not g and h and j)
              or (not feqg and not heqj);
    fghjp13 := (not feqg and not h and not j)
               or (not heqj and not f and not g);
    fghjp31 := (not feqg and h and j)
               or (not heqj and f and g);

    disp4p := fghjp31;
    disp4n := fghjp13;

    data_o.data(0) := a xor (p22bncneeqi or p31i or p13dei or p22ancneeqi or p13en or abei or k28p);
    data_o.data(1) := b xor (p22bceeqi or p31i or p13dei or p22aceeqi or p13en or abei or k28p);
    data_o.data(2) := c xor (p22bceeqi or p31i or p13dei or p22ancneeqi or p13en or anbnenin or k28p);
    data_o.data(3) := d xor (p22bncneeqi or p31i or p13dei or p22aceeqi or p13en or abei or k28p);
    data_o.data(4) := e xor (p22bncneeqi or p13in or p13dei or p22ancneeqi or p13en or anbnenin or k28p);
    data_o.data(5) := (j and not f and (h or not g or k28p))
                      or (f and not j and (not h or g or not k28p))
                      or (k28p and g and h)
                      or (not k28p and not g and not h);
    data_o.data(6) := (j and not f and (h or not g or not k28p))
                      or (f and not j and (not h or g or k28p))
                      or (not k28p and g and h)
                      or (k28p and not g and not h);
    data_o.data(7) := ((j xor h) and (not ((not f and g and not h and j and not k28p)
                                           or (not f and g and h and not j and k28p)
                                           or (f and not g and not h and j and not k28p)
                                           or (f and not g and h and not j and k28p))))
                      or (not f and g and h and j)
                      or (f and not g and not h and not j);

    data_o.control := (c and d and e and i)
                 or (not c and not d and not e and not i)
                 or (p13 and not e and i and g and h and j)
                 or (p31 and e and not i and not g and not h and not j);

    disparity_o := ((fghjp31 or (disp6b and fghj22)) or (h and j)) and (h or j);

    code_error_o := p40 or p04
                    or (f and g and h and j)
                    or (not f and not g and not h and not j)
                    or (p13 and not e and not i)
                    or (p31 and e and i)
                    or (e and i and f and g and h)
                    or (not e and not i and not f and not g and not h)
                    or (e and not i and g and h and j)
                    or (not e and i and not g and not h and not j)
                    or (not p31 and e and not i and not g and not h and not j)
                    or (not p13 and not e and i and g and h and j)
                    or (((e and i and not g and not h and not j) or (not e and not i and g and h and j))
                        and not ((c and d and e) or (not c and not d and not e)))
                    or (disp6p and disp4p)
                    or (disp6n and disp4n)
                    or ((a and b and c and not e and not i) and ((not f and not g) or fghjp13))
                    or (not a and not b and not c and e and i and ((f and g) or fghjp31))
                    or (f and g and not h and not j and disp6p)
                    or (not f and not g and h and j and disp6n)
                    or (c and d and e and i and not f and not g and not h)
                    or (not c and not d and not e and not i and f and g and h);

    disparity_error_o := (disparity_i and disp6p)
                         or (not disparity_i and disp6n)
                         or (disparity_i and not disp6n and f and g)
                         or (disparity_i and a and b and c)
                         or (disparity_i and not disp6n and disp4p)
                         or (not disparity_i and not disp6p and not f and not g)
                         or (not disparity_i and not a and not b and not c)
                         or (not disparity_i and not disp6p and disp4n)
                         or (disp6p and disp4p)
                         or (disp6n and disp4n);
  end procedure;

  procedure encode(
    data_i : in data_t;
    disparity_i : in std_ulogic;

    data_o : out code_word_t;
    disparity_o : out std_ulogic)
  is
    variable a, b, c, d, e, f, g, h : std_ulogic;
    variable l04, l13, l22, l31, l40, aeqb, ceqd : std_ulogic;
    variable alt7, compls4, compls6, disp6 : std_ulogic;
    variable nd1s4, nd1s6, ndos4, ndos6, pd1s4, pd1s6, pdos4, pdos6 : std_ulogic;
  begin
    a := data_i.data(0);
    b := data_i.data(1);
    c := data_i.data(2);
    d := data_i.data(3);
    e := data_i.data(4);
    f := data_i.data(5);
    g := data_i.data(6);
    h := data_i.data(7);

    aeqb := a xnor b;
    ceqd := c xnor d;

    l04 := not (a or b or c or d);
    l13 := (not aeqb and not c and not d) or (not ceqd and not a and not b);
    l22 := (a and b and not c and not d) or (c and d and not a and not b) or (not aeqb and not ceqd);
    l31 := (not aeqb and c and d) or (not ceqd and a and b);
    l40 := a and b and c and d;

    pd1s6 := (e and d and not c and not b and not a) or (not e and not l22 and not l31);
    nd1s6 := data_i.control or (e and not l22 and not l13) or (not e and not d and c and b and a);

    ndos6 := pd1s6;
    pdos6 := data_i.control or (e and not l22 and not l13);
    disp6 := disparity_i xor (ndos6 or pdos6);

    nd1s4 := f and g;
    pd1s4 := (not f and not g) or (data_i.control and (f xor g));
    ndos4 := not f and not g;
    pdos4 := f and g and h;

    alt7 := pdos4 and (data_i.control or if_else(disparity_i = '1',
                                            not e and d and l31,
                                            e and not d and l13));

    compls6 := (pd1s6 and not disparity_i) or (nd1s6 and disparity_i);
    compls4 := (pd1s4 and not disp6) or (nd1s4 and disp6);

    data_o(0) := compls6 xor a;
    data_o(1) := compls6 xor ((b and not l40) or l04);
    data_o(2) := compls6 xor (l04 or c or (e and d and not c and not b and not a));
    data_o(3) := compls6 xor (d and not (a and b and c));
    data_o(4) := compls6 xor ((e or l13) and not (e and d and not c and not b and not a));
    data_o(5) := compls6 xor ((l22 and not e)
                              or (e and not d and not c and not (a and b))
                              or (e and l40)
                              or (data_i.control and e and d and c and not b and not a)
                              or (e and not d and c and not b and not a));
    data_o(6) := compls4 xor (f and not alt7);
    data_o(7) := compls4 xor (g or (not f and not g and not h));
    data_o(8) := compls4 xor h;
    data_o(9) := compls4 xor ((not h and (g xor f)) or alt7);

    disparity_o := disp6 xor (ndos4 or pdos4);
  end procedure;

end package body;
