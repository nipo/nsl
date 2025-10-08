//
//Written by GowinSynthesis
//Tool Version "V1.9.10.02"
//Fri Sep 27 00:55:43 2024

//Source file index table:
//file0 "\C:/Gowin/Gowin_V1.9.10.02_x64/IDE/ipcore/DVI_TX/data/dvi_tx_top.v"
//file1 "\C:/Gowin/Gowin_V1.9.10.02_x64/IDE/ipcore/DVI_TX/data/rgb2dvi.v"
`timescale 100 ps/100 ps
module \~TMDS8b10b.DVI_TX_Top  (
  I_rgb_clk,
  n36_6,
  I_rgb_de,
  I_rgb_r,
  de_d,
  c1_d,
  q_out_r
)
;
input I_rgb_clk;
input n36_6;
input I_rgb_de;
input [7:0] I_rgb_r;
output de_d;
output c1_d;
output [9:0] q_out_r;
wire n274_2;
wire n596_2;
wire n114_4;
wire n630_3;
wire n653_3;
wire n681_4;
wire n682_3;
wire n683_4;
wire n684_3;
wire n685_4;
wire n686_3;
wire n687_4;
wire n688_3;
wire n689_3;
wire n605_5;
wire n604_5;
wire n603_5;
wire n403_10;
wire n402_10;
wire n114_5;
wire n114_6;
wire n114_7;
wire n630_4;
wire n630_5;
wire n653_4;
wire n682_4;
wire n682_5;
wire n683_6;
wire n688_4;
wire cnt_one_9bit_0_19;
wire cnt_one_9bit_0_20;
wire cnt_one_9bit_1_21;
wire cnt_one_9bit_1_22;
wire cnt_one_9bit_1_23;
wire cnt_one_9bit_2_23;
wire n605_6;
wire n605_7;
wire n604_6;
wire n604_7;
wire n603_6;
wire n603_7;
wire n114_8;
wire n114_9;
wire n114_10;
wire n114_12;
wire n683_7;
wire n683_8;
wire n685_6;
wire n686_5;
wire cnt_one_9bit_1_24;
wire cnt_one_9bit_1_25;
wire cnt_one_9bit_1_26;
wire cnt_one_9bit_2_24;
wire n604_8;
wire n114_13;
wire cnt_one_9bit_1_27;
wire cnt_one_9bit_1_28;
wire cnt_one_9bit_0_22;
wire n114_15;
wire n603_11;
wire n685_8;
wire n401_10;
wire n683_10;
wire n686_7;
wire n687_7;
wire n684_6;
wire n680_8;
wire n606_7;
wire n647_6;
wire n670_5;
wire n603_14;
wire n630_8;
wire sel_xnor;
wire n135_2;
wire n135_3;
wire n134_2;
wire n134_3;
wire n133_2;
wire n133_3;
wire n132_2;
wire n132_0_COUT;
wire n560_2;
wire n560_3;
wire n559_2;
wire n559_3;
wire n558_2;
wire n558_0_COUT;
wire n561_5;
wire n561_6;
wire n560_4;
wire n560_5;
wire n559_4;
wire n559_5;
wire n558_4;
wire n558_1_COUT;
wire n366_3;
wire n366_4;
wire n365_3;
wire n365_4;
wire n364_3;
wire n364_0_COUT;
wire n561_9;
wire n561_8;
wire n239_15;
wire n239_14;
wire n238_13;
wire n238_12;
wire n237_13;
wire n237_12;
wire n236_11;
wire n236_5_COUT;
wire n367_13;
wire n367_12;
wire n367_16;
wire n367_15;
wire n366_12;
wire n366_11;
wire n365_12;
wire n365_11;
wire n679_3;
wire n404_10;
wire [3:1] cnt_one_9bit;
wire [7:0] din_d;
wire [4:1] cnt;
wire VCC;
wire GND;
  LUT3 n274_s0 (
    .F(n274_2),
    .I0(n135_2),
    .I1(n239_15),
    .I2(sel_xnor) 
);
defparam n274_s0.INIT=8'h3A;
  LUT3 n596_s0 (
    .F(n596_2),
    .I0(n561_5),
    .I1(n367_16),
    .I2(n653_3) 
);
defparam n596_s0.INIT=8'hCA;
  LUT4 n114_s0 (
    .F(n114_4),
    .I0(I_rgb_r[0]),
    .I1(n114_5),
    .I2(n114_6),
    .I3(n114_7) 
);
defparam n114_s0.INIT=16'hFCC4;
  LUT4 n630_s0 (
    .F(n630_3),
    .I0(n630_4),
    .I1(cnt_one_9bit[2]),
    .I2(cnt[4]),
    .I3(n630_5) 
);
defparam n630_s0.INIT=16'h4F44;
  LUT4 n653_s0 (
    .F(n653_3),
    .I0(n630_5),
    .I1(n630_4),
    .I2(cnt[4]),
    .I3(n653_4) 
);
defparam n653_s0.INIT=16'hF004;
  LUT3 n681_s1 (
    .F(n681_4),
    .I0(c1_d),
    .I1(sel_xnor),
    .I2(de_d) 
);
defparam n681_s1.INIT=8'h35;
  LUT4 n682_s0 (
    .F(n682_3),
    .I0(c1_d),
    .I1(n682_4),
    .I2(n682_5),
    .I3(de_d) 
);
defparam n682_s0.INIT=16'h3CAA;
  LUT4 n683_s1 (
    .F(n683_4),
    .I0(c1_d),
    .I1(n683_10),
    .I2(n683_6),
    .I3(de_d) 
);
defparam n683_s1.INIT=16'hC355;
  LUT4 n684_s0 (
    .F(n684_3),
    .I0(c1_d),
    .I1(n683_6),
    .I2(n684_6),
    .I3(de_d) 
);
defparam n684_s0.INIT=16'hC3AA;
  LUT4 n685_s1 (
    .F(n685_4),
    .I0(c1_d),
    .I1(n683_6),
    .I2(n685_8),
    .I3(de_d) 
);
defparam n685_s1.INIT=16'hC355;
  LUT4 n686_s0 (
    .F(n686_3),
    .I0(c1_d),
    .I1(n683_6),
    .I2(n686_7),
    .I3(de_d) 
);
defparam n686_s0.INIT=16'hC3AA;
  LUT4 n687_s1 (
    .F(n687_4),
    .I0(c1_d),
    .I1(n683_6),
    .I2(n687_7),
    .I3(de_d) 
);
defparam n687_s1.INIT=16'hC355;
  LUT4 n688_s0 (
    .F(n688_3),
    .I0(c1_d),
    .I1(n688_4),
    .I2(n682_4),
    .I3(de_d) 
);
defparam n688_s0.INIT=16'h3CAA;
  LUT3 n689_s0 (
    .F(n689_3),
    .I0(n679_3),
    .I1(c1_d),
    .I2(de_d) 
);
defparam n689_s0.INIT=8'hAC;
  LUT4 cnt_one_9bit_2_s15 (
    .F(cnt_one_9bit[2]),
    .I0(cnt_one_9bit_1_21),
    .I1(cnt_one_9bit_1_23),
    .I2(cnt_one_9bit_1_22),
    .I3(cnt_one_9bit_2_23) 
);
defparam cnt_one_9bit_2_s15.INIT=16'h71BE;
  LUT4 n605_s1 (
    .F(n605_5),
    .I0(n605_6),
    .I1(n605_7),
    .I2(n630_3),
    .I3(de_d) 
);
defparam n605_s1.INIT=16'hCA00;
  LUT4 n604_s1 (
    .F(n604_5),
    .I0(n604_6),
    .I1(n604_7),
    .I2(n630_3),
    .I3(de_d) 
);
defparam n604_s1.INIT=16'h3500;
  LUT4 n603_s1 (
    .F(n603_5),
    .I0(n603_6),
    .I1(n603_7),
    .I2(n630_3),
    .I3(de_d) 
);
defparam n603_s1.INIT=16'h3A00;
  LUT2 n403_s4 (
    .F(n403_10),
    .I0(cnt[1]),
    .I1(cnt[2]) 
);
defparam n403_s4.INIT=4'h9;
  LUT3 n402_s4 (
    .F(n402_10),
    .I0(cnt[1]),
    .I1(cnt[2]),
    .I2(cnt[3]) 
);
defparam n402_s4.INIT=8'hE1;
  LUT4 n114_s1 (
    .F(n114_5),
    .I0(n114_8),
    .I1(n114_9),
    .I2(n114_10),
    .I3(n114_7) 
);
defparam n114_s1.INIT=16'hE8FE;
  LUT4 n114_s2 (
    .F(n114_6),
    .I0(I_rgb_r[0]),
    .I1(I_rgb_r[1]),
    .I2(I_rgb_r[2]),
    .I3(I_rgb_r[4]) 
);
defparam n114_s2.INIT=16'h8000;
  LUT3 n114_s3 (
    .F(n114_7),
    .I0(I_rgb_r[7]),
    .I1(n114_15),
    .I2(n114_12) 
);
defparam n114_s3.INIT=8'hDB;
  LUT4 n630_s1 (
    .F(n630_4),
    .I0(n630_8),
    .I1(cnt_one_9bit_1_22),
    .I2(cnt_one_9bit_1_23),
    .I3(cnt_one_9bit_2_23) 
);
defparam n630_s1.INIT=16'h96D7;
  LUT3 n630_s2 (
    .F(n630_5),
    .I0(cnt[1]),
    .I1(cnt[2]),
    .I2(cnt[3]) 
);
defparam n630_s2.INIT=8'h01;
  LUT4 n653_s1 (
    .F(n653_4),
    .I0(cnt_one_9bit_1_21),
    .I1(cnt_one_9bit_1_23),
    .I2(cnt_one_9bit_1_22),
    .I3(cnt_one_9bit_2_23) 
);
defparam n653_s1.INIT=16'h8E00;
  LUT3 n682_s1 (
    .F(n682_4),
    .I0(n630_3),
    .I1(sel_xnor),
    .I2(n653_3) 
);
defparam n682_s1.INIT=8'h14;
  LUT2 n682_s2 (
    .F(n682_5),
    .I0(din_d[7]),
    .I1(n683_10) 
);
defparam n682_s2.INIT=4'h6;
  LUT3 n683_s3 (
    .F(n683_6),
    .I0(n630_3),
    .I1(sel_xnor),
    .I2(n653_3) 
);
defparam n683_s3.INIT=8'h07;
  LUT2 n688_s1 (
    .F(n688_4),
    .I0(din_d[0]),
    .I1(din_d[1]) 
);
defparam n688_s1.INIT=4'h6;
  LUT4 cnt_one_9bit_0_s14 (
    .F(cnt_one_9bit_0_19),
    .I0(din_d[1]),
    .I1(sel_xnor),
    .I2(din_d[3]),
    .I3(din_d[5]) 
);
defparam cnt_one_9bit_0_s14.INIT=16'h6996;
  LUT2 cnt_one_9bit_0_s15 (
    .F(cnt_one_9bit_0_20),
    .I0(sel_xnor),
    .I1(din_d[7]) 
);
defparam cnt_one_9bit_0_s15.INIT=4'h6;
  LUT4 cnt_one_9bit_1_s15 (
    .F(cnt_one_9bit_1_21),
    .I0(n683_7),
    .I1(n683_8),
    .I2(cnt_one_9bit_0_19),
    .I3(cnt_one_9bit_0_20) 
);
defparam cnt_one_9bit_1_s15.INIT=16'h6FF9;
  LUT4 cnt_one_9bit_1_s16 (
    .F(cnt_one_9bit_1_22),
    .I0(cnt_one_9bit_1_24),
    .I1(n686_5),
    .I2(n683_8),
    .I3(cnt_one_9bit_0_19) 
);
defparam cnt_one_9bit_1_s16.INIT=16'h96AA;
  LUT2 cnt_one_9bit_1_s17 (
    .F(cnt_one_9bit_1_23),
    .I0(cnt_one_9bit_1_25),
    .I1(cnt_one_9bit_1_26) 
);
defparam cnt_one_9bit_1_s17.INIT=4'h6;
  LUT3 cnt_one_9bit_2_s16 (
    .F(cnt_one_9bit_2_23),
    .I0(cnt_one_9bit_1_26),
    .I1(cnt_one_9bit_1_25),
    .I2(cnt_one_9bit_2_24) 
);
defparam cnt_one_9bit_2_s16.INIT=8'h0B;
  LUT3 n605_s2 (
    .F(n605_6),
    .I0(n366_12),
    .I1(n560_4),
    .I2(n653_3) 
);
defparam n605_s2.INIT=8'hAC;
  LUT4 n605_s3 (
    .F(n605_7),
    .I0(n134_2),
    .I1(n238_13),
    .I2(n239_15),
    .I3(sel_xnor) 
);
defparam n605_s3.INIT=16'h3CAA;
  LUT3 n604_s2 (
    .F(n604_6),
    .I0(n365_12),
    .I1(n559_4),
    .I2(n653_3) 
);
defparam n604_s2.INIT=8'hAC;
  LUT4 n604_s3 (
    .F(n604_7),
    .I0(n133_2),
    .I1(n237_13),
    .I2(n604_8),
    .I3(sel_xnor) 
);
defparam n604_s3.INIT=16'h3CAA;
  LUT4 n603_s2 (
    .F(n603_6),
    .I0(n603_14),
    .I1(n559_4),
    .I2(n558_4),
    .I3(n653_3) 
);
defparam n603_s2.INIT=16'hAAC3;
  LUT4 n603_s3 (
    .F(n603_7),
    .I0(n603_11),
    .I1(n133_2),
    .I2(n132_2),
    .I3(sel_xnor) 
);
defparam n603_s3.INIT=16'hAA3C;
  LUT4 n114_s4 (
    .F(n114_8),
    .I0(I_rgb_r[0]),
    .I1(I_rgb_r[1]),
    .I2(I_rgb_r[2]),
    .I3(I_rgb_r[4]) 
);
defparam n114_s4.INIT=16'h7EE8;
  LUT2 n114_s5 (
    .F(n114_9),
    .I0(I_rgb_r[3]),
    .I1(I_rgb_r[5]) 
);
defparam n114_s5.INIT=4'h8;
  LUT4 n114_s6 (
    .F(n114_10),
    .I0(I_rgb_r[6]),
    .I1(n114_13),
    .I2(I_rgb_r[3]),
    .I3(I_rgb_r[5]) 
);
defparam n114_s6.INIT=16'h8EE8;
  LUT4 n114_s8 (
    .F(n114_12),
    .I0(I_rgb_r[3]),
    .I1(I_rgb_r[5]),
    .I2(I_rgb_r[6]),
    .I3(n114_13) 
);
defparam n114_s8.INIT=16'h6996;
  LUT4 n683_s4 (
    .F(n683_7),
    .I0(din_d[2]),
    .I1(din_d[3]),
    .I2(din_d[4]),
    .I3(din_d[5]) 
);
defparam n683_s4.INIT=16'h6996;
  LUT3 n683_s5 (
    .F(n683_8),
    .I0(din_d[0]),
    .I1(din_d[1]),
    .I2(din_d[6]) 
);
defparam n683_s5.INIT=8'h96;
  LUT2 n685_s3 (
    .F(n685_6),
    .I0(din_d[3]),
    .I1(din_d[4]) 
);
defparam n685_s3.INIT=4'h6;
  LUT2 n686_s2 (
    .F(n686_5),
    .I0(din_d[2]),
    .I1(din_d[3]) 
);
defparam n686_s2.INIT=4'h6;
  LUT2 cnt_one_9bit_1_s18 (
    .F(cnt_one_9bit_1_24),
    .I0(din_d[4]),
    .I1(din_d[5]) 
);
defparam cnt_one_9bit_1_s18.INIT=4'h6;
  LUT4 cnt_one_9bit_1_s19 (
    .F(cnt_one_9bit_1_25),
    .I0(sel_xnor),
    .I1(cnt_one_9bit_1_27),
    .I2(din_d[1]),
    .I3(n685_6) 
);
defparam cnt_one_9bit_1_s19.INIT=16'h5A3C;
  LUT4 cnt_one_9bit_1_s20 (
    .F(cnt_one_9bit_1_26),
    .I0(din_d[0]),
    .I1(cnt_one_9bit_1_28),
    .I2(n686_5),
    .I3(cnt_one_9bit_1_24) 
);
defparam cnt_one_9bit_1_s20.INIT=16'hDD4B;
  LUT4 cnt_one_9bit_2_s17 (
    .F(cnt_one_9bit_2_24),
    .I0(din_d[0]),
    .I1(n686_5),
    .I2(cnt_one_9bit_1_24),
    .I3(cnt_one_9bit_1_28) 
);
defparam cnt_one_9bit_2_s17.INIT=16'h0002;
  LUT2 n604_s4 (
    .F(n604_8),
    .I0(n238_13),
    .I1(n239_15) 
);
defparam n604_s4.INIT=4'h8;
  LUT4 n114_s9 (
    .F(n114_13),
    .I0(I_rgb_r[0]),
    .I1(I_rgb_r[1]),
    .I2(I_rgb_r[2]),
    .I3(I_rgb_r[4]) 
);
defparam n114_s9.INIT=16'h6996;
  LUT2 cnt_one_9bit_1_s21 (
    .F(cnt_one_9bit_1_27),
    .I0(din_d[0]),
    .I1(din_d[2]) 
);
defparam cnt_one_9bit_1_s21.INIT=4'h6;
  LUT2 cnt_one_9bit_1_s22 (
    .F(cnt_one_9bit_1_28),
    .I0(din_d[1]),
    .I1(sel_xnor) 
);
defparam cnt_one_9bit_1_s22.INIT=4'h6;
  LUT3 cnt_one_9bit_0_s16 (
    .F(cnt_one_9bit_0_22),
    .I0(cnt_one_9bit_0_19),
    .I1(sel_xnor),
    .I2(din_d[7]) 
);
defparam cnt_one_9bit_0_s16.INIT=8'h96;
  LUT4 n114_s10 (
    .F(n114_15),
    .I0(n114_8),
    .I1(I_rgb_r[3]),
    .I2(I_rgb_r[5]),
    .I3(n114_10) 
);
defparam n114_s10.INIT=16'h6A95;
  LUT4 n603_s6 (
    .F(n603_11),
    .I0(n237_13),
    .I1(n238_13),
    .I2(n239_15),
    .I3(n236_11) 
);
defparam n603_s6.INIT=16'hEA15;
  LUT3 n685_s4 (
    .F(n685_8),
    .I0(din_d[3]),
    .I1(din_d[4]),
    .I2(n687_7) 
);
defparam n685_s4.INIT=8'h96;
  LUT4 n401_s4 (
    .F(n401_10),
    .I0(cnt[4]),
    .I1(cnt[1]),
    .I2(cnt[2]),
    .I3(cnt[3]) 
);
defparam n401_s4.INIT=16'hAAA9;
  LUT4 n683_s6 (
    .F(n683_10),
    .I0(n683_7),
    .I1(din_d[0]),
    .I2(din_d[1]),
    .I3(din_d[6]) 
);
defparam n683_s6.INIT=16'h6996;
  LUT4 n686_s3 (
    .F(n686_7),
    .I0(sel_xnor),
    .I1(din_d[2]),
    .I2(din_d[3]),
    .I3(n688_4) 
);
defparam n686_s3.INIT=16'h6996;
  LUT3 n687_s3 (
    .F(n687_7),
    .I0(din_d[2]),
    .I1(din_d[0]),
    .I2(din_d[1]) 
);
defparam n687_s3.INIT=8'h96;
  LUT4 n684_s2 (
    .F(n684_6),
    .I0(sel_xnor),
    .I1(n683_7),
    .I2(din_d[0]),
    .I3(din_d[1]) 
);
defparam n684_s2.INIT=16'h6996;
  LUT4 cnt_one_9bit_3_s12 (
    .F(cnt_one_9bit[3]),
    .I0(cnt_one_9bit_1_21),
    .I1(cnt_one_9bit_2_23),
    .I2(cnt_one_9bit_1_25),
    .I3(cnt_one_9bit_1_26) 
);
defparam cnt_one_9bit_3_s12.INIT=16'h1001;
  LUT4 cnt_one_9bit_1_s23 (
    .F(cnt_one_9bit[1]),
    .I0(cnt_one_9bit_1_21),
    .I1(cnt_one_9bit_1_22),
    .I2(cnt_one_9bit_1_25),
    .I3(cnt_one_9bit_1_26) 
);
defparam cnt_one_9bit_1_s23.INIT=16'h6996;
  LUT4 n680_s3 (
    .F(n680_8),
    .I0(de_d),
    .I1(n630_3),
    .I2(sel_xnor),
    .I3(n653_3) 
);
defparam n680_s3.INIT=16'hFFD5;
  LUT4 n606_s2 (
    .F(n606_7),
    .I0(de_d),
    .I1(n596_2),
    .I2(n274_2),
    .I3(n630_3) 
);
defparam n606_s2.INIT=16'hA088;
  LUT2 n679_s2 (
    .F(n647_6),
    .I0(din_d[0]),
    .I1(sel_xnor) 
);
defparam n679_s2.INIT=4'h6;
  LUT2 n679_s1 (
    .F(n670_5),
    .I0(din_d[0]),
    .I1(n653_3) 
);
defparam n679_s1.INIT=4'h6;
  LUT4 n603_s7 (
    .F(n603_14),
    .I0(n364_3),
    .I1(cnt_one_9bit[3]),
    .I2(n365_11),
    .I3(n365_12) 
);
defparam n603_s7.INIT=16'h9669;
  LUT4 n630_s4 (
    .F(n630_8),
    .I0(cnt_one_9bit_0_19),
    .I1(sel_xnor),
    .I2(din_d[7]),
    .I3(cnt_one_9bit_1_21) 
);
defparam n630_s4.INIT=16'h6900;
  DFFCE din_d_6_s0 (
    .Q(din_d[6]),
    .D(I_rgb_r[6]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_5_s0 (
    .Q(din_d[5]),
    .D(I_rgb_r[5]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_4_s0 (
    .Q(din_d[4]),
    .D(I_rgb_r[4]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_3_s0 (
    .Q(din_d[3]),
    .D(I_rgb_r[3]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_2_s0 (
    .Q(din_d[2]),
    .D(I_rgb_r[2]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_1_s0 (
    .Q(din_d[1]),
    .D(I_rgb_r[1]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_0_s0 (
    .Q(din_d[0]),
    .D(I_rgb_r[0]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE de_d_s0 (
    .Q(de_d),
    .D(I_rgb_de),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFPE c1_d_s0 (
    .Q(c1_d),
    .D(GND),
    .CLK(I_rgb_clk),
    .PRESET(n36_6),
    .CE(VCC) 
);
  DFFCE sel_xnor_s0 (
    .Q(sel_xnor),
    .D(n114_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE cnt_4_s0 (
    .Q(cnt[4]),
    .D(n603_5),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE cnt_3_s0 (
    .Q(cnt[3]),
    .D(n604_5),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE cnt_2_s0 (
    .Q(cnt[2]),
    .D(n605_5),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE cnt_1_s0 (
    .Q(cnt[1]),
    .D(n606_7),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_9_s0 (
    .Q(q_out_r[9]),
    .D(n680_8),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_8_s0 (
    .Q(q_out_r[8]),
    .D(n681_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_7_s0 (
    .Q(q_out_r[7]),
    .D(n682_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_6_s0 (
    .Q(q_out_r[6]),
    .D(n683_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_5_s0 (
    .Q(q_out_r[5]),
    .D(n684_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_4_s0 (
    .Q(q_out_r[4]),
    .D(n685_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_3_s0 (
    .Q(q_out_r[3]),
    .D(n686_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_2_s0 (
    .Q(q_out_r[2]),
    .D(n687_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_1_s0 (
    .Q(q_out_r[1]),
    .D(n688_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_0_s0 (
    .Q(q_out_r[0]),
    .D(n689_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_7_s0 (
    .Q(din_d[7]),
    .D(I_rgb_r[7]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  ALU n135_s (
    .SUM(n135_2),
    .COUT(n135_3),
    .I0(cnt[1]),
    .I1(cnt_one_9bit_0_22),
    .I3(GND),
    .CIN(GND) 
);
defparam n135_s.ALU_MODE=0;
  ALU n134_s (
    .SUM(n134_2),
    .COUT(n134_3),
    .I0(cnt[2]),
    .I1(cnt_one_9bit[1]),
    .I3(GND),
    .CIN(n135_3) 
);
defparam n134_s.ALU_MODE=0;
  ALU n133_s (
    .SUM(n133_2),
    .COUT(n133_3),
    .I0(cnt[3]),
    .I1(cnt_one_9bit[2]),
    .I3(GND),
    .CIN(n134_3) 
);
defparam n133_s.ALU_MODE=0;
  ALU n132_s (
    .SUM(n132_2),
    .COUT(n132_0_COUT),
    .I0(cnt[4]),
    .I1(cnt_one_9bit[3]),
    .I3(GND),
    .CIN(n133_3) 
);
defparam n132_s.ALU_MODE=0;
  ALU n560_s (
    .SUM(n560_2),
    .COUT(n560_3),
    .I0(n403_10),
    .I1(GND),
    .I3(GND),
    .CIN(n561_8) 
);
defparam n560_s.ALU_MODE=0;
  ALU n559_s (
    .SUM(n559_2),
    .COUT(n559_3),
    .I0(n402_10),
    .I1(GND),
    .I3(GND),
    .CIN(n560_3) 
);
defparam n559_s.ALU_MODE=0;
  ALU n558_s (
    .SUM(n558_2),
    .COUT(n558_0_COUT),
    .I0(n401_10),
    .I1(GND),
    .I3(GND),
    .CIN(n559_3) 
);
defparam n558_s.ALU_MODE=0;
  ALU n561_s1 (
    .SUM(n561_5),
    .COUT(n561_6),
    .I0(n561_9),
    .I1(cnt_one_9bit_0_22),
    .I3(GND),
    .CIN(GND) 
);
defparam n561_s1.ALU_MODE=0;
  ALU n560_s0 (
    .SUM(n560_4),
    .COUT(n560_5),
    .I0(n560_2),
    .I1(cnt_one_9bit[1]),
    .I3(GND),
    .CIN(n561_6) 
);
defparam n560_s0.ALU_MODE=0;
  ALU n559_s0 (
    .SUM(n559_4),
    .COUT(n559_5),
    .I0(n559_2),
    .I1(cnt_one_9bit[2]),
    .I3(GND),
    .CIN(n560_5) 
);
defparam n559_s0.ALU_MODE=0;
  ALU n558_s0 (
    .SUM(n558_4),
    .COUT(n558_1_COUT),
    .I0(n558_2),
    .I1(cnt_one_9bit[3]),
    .I3(GND),
    .CIN(n559_5) 
);
defparam n558_s0.ALU_MODE=0;
  ALU n366_s (
    .SUM(n366_3),
    .COUT(n366_4),
    .I0(cnt[2]),
    .I1(GND),
    .I3(GND),
    .CIN(n367_12) 
);
defparam n366_s.ALU_MODE=0;
  ALU n365_s (
    .SUM(n365_3),
    .COUT(n365_4),
    .I0(cnt[3]),
    .I1(GND),
    .I3(GND),
    .CIN(n366_4) 
);
defparam n365_s.ALU_MODE=0;
  ALU n364_s (
    .SUM(n364_3),
    .COUT(n364_0_COUT),
    .I0(cnt[4]),
    .I1(GND),
    .I3(GND),
    .CIN(n365_4) 
);
defparam n364_s.ALU_MODE=0;
  ALU n561_s2 (
    .SUM(n561_9),
    .COUT(n561_8),
    .I0(n404_10),
    .I1(sel_xnor),
    .I3(GND),
    .CIN(GND) 
);
defparam n561_s2.ALU_MODE=1;
  ALU n239_s6 (
    .SUM(n239_15),
    .COUT(n239_14),
    .I0(cnt[1]),
    .I1(cnt_one_9bit_0_22),
    .I3(GND),
    .CIN(GND) 
);
defparam n239_s6.ALU_MODE=1;
  ALU n238_s5 (
    .SUM(n238_13),
    .COUT(n238_12),
    .I0(cnt[2]),
    .I1(cnt_one_9bit[1]),
    .I3(GND),
    .CIN(n239_14) 
);
defparam n238_s5.ALU_MODE=1;
  ALU n237_s5 (
    .SUM(n237_13),
    .COUT(n237_12),
    .I0(cnt[3]),
    .I1(cnt_one_9bit[2]),
    .I3(GND),
    .CIN(n238_12) 
);
defparam n237_s5.ALU_MODE=1;
  ALU n236_s4 (
    .SUM(n236_11),
    .COUT(n236_5_COUT),
    .I0(cnt[4]),
    .I1(cnt_one_9bit[3]),
    .I3(GND),
    .CIN(n237_12) 
);
defparam n236_s4.ALU_MODE=1;
  ALU n367_s4 (
    .SUM(n367_13),
    .COUT(n367_12),
    .I0(cnt[1]),
    .I1(sel_xnor),
    .I3(GND),
    .CIN(GND) 
);
defparam n367_s4.ALU_MODE=1;
  ALU n367_s5 (
    .SUM(n367_16),
    .COUT(n367_15),
    .I0(n367_13),
    .I1(cnt_one_9bit_0_22),
    .I3(GND),
    .CIN(VCC) 
);
defparam n367_s5.ALU_MODE=1;
  ALU n366_s3 (
    .SUM(n366_12),
    .COUT(n366_11),
    .I0(n366_3),
    .I1(cnt_one_9bit[1]),
    .I3(GND),
    .CIN(n367_15) 
);
defparam n366_s3.ALU_MODE=1;
  ALU n365_s3 (
    .SUM(n365_12),
    .COUT(n365_11),
    .I0(n365_3),
    .I1(cnt_one_9bit[2]),
    .I3(GND),
    .CIN(n366_11) 
);
defparam n365_s3.ALU_MODE=1;
  MUX2_LUT5 n679_s0 (
    .O(n679_3),
    .I0(n670_5),
    .I1(n647_6),
    .S0(n630_3) 
);
  INV n404_s5 (
    .O(n404_10),
    .I(cnt[1]) 
);
  VCC VCC_cZ (
    .V(VCC)
);
  GND GND_cZ (
    .G(GND)
);
endmodule /* \~TMDS8b10b.DVI_TX_Top  */
module \~TMDS8b10b.DVI_TX_Top_0  (
  I_rgb_clk,
  n36_6,
  c1_d,
  de_d,
  I_rgb_g,
  q_out_g
)
;
input I_rgb_clk;
input n36_6;
input c1_d;
input de_d;
input [7:0] I_rgb_g;
output [9:0] q_out_g;
wire n274_2;
wire n596_2;
wire n114_3;
wire n630_3;
wire n653_3;
wire n681_4;
wire n682_3;
wire n683_4;
wire n684_3;
wire n685_4;
wire n686_3;
wire n687_4;
wire n688_3;
wire n689_3;
wire cnt_one_9bit_0_18;
wire n605_5;
wire n604_5;
wire n603_5;
wire n403_10;
wire n402_10;
wire n114_4;
wire n114_5;
wire n114_6;
wire n630_4;
wire n630_5;
wire n630_6;
wire n682_4;
wire n682_5;
wire n683_6;
wire n684_4;
wire n688_4;
wire cnt_one_9bit_1_21;
wire cnt_one_9bit_1_22;
wire cnt_one_9bit_3_15;
wire n605_6;
wire n605_7;
wire n604_6;
wire n604_7;
wire n603_6;
wire n603_7;
wire n114_7;
wire n114_9;
wire n114_10;
wire n114_11;
wire n114_12;
wire n630_7;
wire n683_7;
wire n683_8;
wire n683_9;
wire n685_6;
wire cnt_one_9bit_0_20;
wire cnt_one_9bit_1_23;
wire cnt_one_9bit_1_24;
wire n604_8;
wire n114_13;
wire n630_8;
wire cnt_one_9bit_1_25;
wire cnt_one_9bit_0_22;
wire n114_15;
wire n603_11;
wire n685_8;
wire n401_10;
wire n687_7;
wire n686_6;
wire n683_11;
wire n680_8;
wire n606_7;
wire n647_5;
wire n670_5;
wire n603_13;
wire sel_xnor;
wire n135_2;
wire n135_3;
wire n134_2;
wire n134_3;
wire n133_2;
wire n133_3;
wire n132_2;
wire n132_0_COUT;
wire n560_2;
wire n560_3;
wire n559_2;
wire n559_3;
wire n558_2;
wire n558_0_COUT;
wire n561_5;
wire n561_6;
wire n560_4;
wire n560_5;
wire n559_4;
wire n559_5;
wire n558_4;
wire n558_1_COUT;
wire n366_3;
wire n366_4;
wire n365_3;
wire n365_4;
wire n364_3;
wire n364_0_COUT;
wire n561_9;
wire n561_8;
wire n239_15;
wire n239_14;
wire n238_13;
wire n238_12;
wire n237_13;
wire n237_12;
wire n236_11;
wire n236_5_COUT;
wire n367_13;
wire n367_12;
wire n367_16;
wire n367_15;
wire n366_12;
wire n366_11;
wire n365_12;
wire n365_11;
wire n679_3;
wire n404_10;
wire [3:1] cnt_one_9bit;
wire [7:0] din_d;
wire [4:1] cnt;
wire VCC;
wire GND;
  LUT3 n274_s0 (
    .F(n274_2),
    .I0(n135_2),
    .I1(n239_15),
    .I2(sel_xnor) 
);
defparam n274_s0.INIT=8'h3A;
  LUT3 n596_s0 (
    .F(n596_2),
    .I0(n561_5),
    .I1(n367_16),
    .I2(n653_3) 
);
defparam n596_s0.INIT=8'hCA;
  LUT3 n114_s0 (
    .F(n114_3),
    .I0(n114_4),
    .I1(n114_5),
    .I2(n114_6) 
);
defparam n114_s0.INIT=8'hB2;
  LUT4 n630_s0 (
    .F(n630_3),
    .I0(n630_4),
    .I1(n630_5),
    .I2(cnt[4]),
    .I3(n630_6) 
);
defparam n630_s0.INIT=16'h1F11;
  LUT4 n653_s0 (
    .F(n653_3),
    .I0(n630_6),
    .I1(n630_4),
    .I2(n630_5),
    .I3(cnt[4]) 
);
defparam n653_s0.INIT=16'hF004;
  LUT3 n681_s1 (
    .F(n681_4),
    .I0(sel_xnor),
    .I1(c1_d),
    .I2(de_d) 
);
defparam n681_s1.INIT=8'h53;
  LUT4 n682_s0 (
    .F(n682_3),
    .I0(c1_d),
    .I1(n682_4),
    .I2(n682_5),
    .I3(de_d) 
);
defparam n682_s0.INIT=16'h3CAA;
  LUT4 n683_s1 (
    .F(n683_4),
    .I0(c1_d),
    .I1(n683_11),
    .I2(n683_6),
    .I3(de_d) 
);
defparam n683_s1.INIT=16'hC355;
  LUT4 n684_s0 (
    .F(n684_3),
    .I0(c1_d),
    .I1(n683_6),
    .I2(n684_4),
    .I3(de_d) 
);
defparam n684_s0.INIT=16'hC3AA;
  LUT4 n685_s1 (
    .F(n685_4),
    .I0(c1_d),
    .I1(n683_6),
    .I2(n685_8),
    .I3(de_d) 
);
defparam n685_s1.INIT=16'hC355;
  LUT4 n686_s0 (
    .F(n686_3),
    .I0(c1_d),
    .I1(n686_6),
    .I2(n683_6),
    .I3(de_d) 
);
defparam n686_s0.INIT=16'hC3AA;
  LUT4 n687_s1 (
    .F(n687_4),
    .I0(c1_d),
    .I1(n683_6),
    .I2(n687_7),
    .I3(de_d) 
);
defparam n687_s1.INIT=16'hC355;
  LUT4 n688_s0 (
    .F(n688_3),
    .I0(c1_d),
    .I1(n688_4),
    .I2(n682_4),
    .I3(de_d) 
);
defparam n688_s0.INIT=16'h3CAA;
  LUT3 n689_s0 (
    .F(n689_3),
    .I0(n679_3),
    .I1(c1_d),
    .I2(de_d) 
);
defparam n689_s0.INIT=8'hAC;
  LUT3 cnt_one_9bit_0_s13 (
    .F(cnt_one_9bit_0_18),
    .I0(sel_xnor),
    .I1(din_d[7]),
    .I2(cnt_one_9bit_0_22) 
);
defparam cnt_one_9bit_0_s13.INIT=8'h96;
  LUT3 cnt_one_9bit_3_s11 (
    .F(cnt_one_9bit[3]),
    .I0(cnt_one_9bit_1_21),
    .I1(cnt_one_9bit_3_15),
    .I2(cnt_one_9bit_1_22) 
);
defparam cnt_one_9bit_3_s11.INIT=8'h01;
  LUT4 n605_s1 (
    .F(n605_5),
    .I0(n605_6),
    .I1(n605_7),
    .I2(n630_3),
    .I3(de_d) 
);
defparam n605_s1.INIT=16'hCA00;
  LUT4 n604_s1 (
    .F(n604_5),
    .I0(n604_6),
    .I1(n604_7),
    .I2(n630_3),
    .I3(de_d) 
);
defparam n604_s1.INIT=16'h3500;
  LUT4 n603_s1 (
    .F(n603_5),
    .I0(n603_6),
    .I1(n603_7),
    .I2(n630_3),
    .I3(de_d) 
);
defparam n603_s1.INIT=16'h3A00;
  LUT2 n403_s4 (
    .F(n403_10),
    .I0(cnt[1]),
    .I1(cnt[2]) 
);
defparam n403_s4.INIT=4'h9;
  LUT3 n402_s4 (
    .F(n402_10),
    .I0(cnt[1]),
    .I1(cnt[2]),
    .I2(cnt[3]) 
);
defparam n402_s4.INIT=8'hE1;
  LUT4 n114_s1 (
    .F(n114_4),
    .I0(I_rgb_g[0]),
    .I1(I_rgb_g[1]),
    .I2(I_rgb_g[2]),
    .I3(I_rgb_g[4]) 
);
defparam n114_s1.INIT=16'h8000;
  LUT4 n114_s2 (
    .F(n114_5),
    .I0(I_rgb_g[7]),
    .I1(n114_7),
    .I2(n114_15),
    .I3(I_rgb_g[0]) 
);
defparam n114_s2.INIT=16'h8100;
  LUT4 n114_s3 (
    .F(n114_6),
    .I0(n114_9),
    .I1(n114_10),
    .I2(n114_11),
    .I3(n114_12) 
);
defparam n114_s3.INIT=16'hFDD4;
  LUT4 n630_s1 (
    .F(n630_4),
    .I0(cnt_one_9bit_3_15),
    .I1(cnt_one_9bit_0_18),
    .I2(cnt_one_9bit_1_21),
    .I3(cnt_one_9bit_1_22) 
);
defparam n630_s1.INIT=16'hCFF5;
  LUT4 n630_s2 (
    .F(n630_5),
    .I0(cnt_one_9bit_1_21),
    .I1(n630_7),
    .I2(cnt_one_9bit_3_15),
    .I3(cnt_one_9bit_1_22) 
);
defparam n630_s2.INIT=16'h30A0;
  LUT3 n630_s3 (
    .F(n630_6),
    .I0(cnt[1]),
    .I1(cnt[2]),
    .I2(cnt[3]) 
);
defparam n630_s3.INIT=8'h01;
  LUT3 n682_s1 (
    .F(n682_4),
    .I0(n630_3),
    .I1(sel_xnor),
    .I2(n653_3) 
);
defparam n682_s1.INIT=8'h14;
  LUT2 n682_s2 (
    .F(n682_5),
    .I0(din_d[7]),
    .I1(n683_11) 
);
defparam n682_s2.INIT=4'h6;
  LUT3 n683_s3 (
    .F(n683_6),
    .I0(n630_3),
    .I1(sel_xnor),
    .I2(n653_3) 
);
defparam n683_s3.INIT=8'h07;
  LUT4 n684_s1 (
    .F(n684_4),
    .I0(sel_xnor),
    .I1(n683_7),
    .I2(n683_8),
    .I3(n688_4) 
);
defparam n684_s1.INIT=16'h6996;
  LUT2 n688_s1 (
    .F(n688_4),
    .I0(din_d[0]),
    .I1(din_d[1]) 
);
defparam n688_s1.INIT=4'h6;
  LUT4 cnt_one_9bit_1_s15 (
    .F(cnt_one_9bit_1_21),
    .I0(sel_xnor),
    .I1(din_d[7]),
    .I2(n683_11),
    .I3(cnt_one_9bit_0_22) 
);
defparam cnt_one_9bit_1_s15.INIT=16'hF96F;
  LUT3 cnt_one_9bit_1_s16 (
    .F(cnt_one_9bit_1_22),
    .I0(n630_7),
    .I1(cnt_one_9bit_1_23),
    .I2(cnt_one_9bit_1_24) 
);
defparam cnt_one_9bit_1_s16.INIT=8'h96;
  LUT4 cnt_one_9bit_3_s12 (
    .F(cnt_one_9bit_3_15),
    .I0(n686_6),
    .I1(n683_7),
    .I2(cnt_one_9bit_1_23),
    .I3(cnt_one_9bit_1_24) 
);
defparam cnt_one_9bit_3_s12.INIT=16'hDD0F;
  LUT3 n605_s2 (
    .F(n605_6),
    .I0(n366_12),
    .I1(n560_4),
    .I2(n653_3) 
);
defparam n605_s2.INIT=8'hAC;
  LUT4 n605_s3 (
    .F(n605_7),
    .I0(n134_2),
    .I1(n238_13),
    .I2(n239_15),
    .I3(sel_xnor) 
);
defparam n605_s3.INIT=16'h3CAA;
  LUT3 n604_s2 (
    .F(n604_6),
    .I0(n365_12),
    .I1(n559_4),
    .I2(n653_3) 
);
defparam n604_s2.INIT=8'hAC;
  LUT4 n604_s3 (
    .F(n604_7),
    .I0(n133_2),
    .I1(n237_13),
    .I2(n604_8),
    .I3(sel_xnor) 
);
defparam n604_s3.INIT=16'h3CAA;
  LUT4 n603_s2 (
    .F(n603_6),
    .I0(n603_13),
    .I1(n559_4),
    .I2(n558_4),
    .I3(n653_3) 
);
defparam n603_s2.INIT=16'hAAC3;
  LUT4 n603_s3 (
    .F(n603_7),
    .I0(n603_11),
    .I1(n133_2),
    .I2(n132_2),
    .I3(sel_xnor) 
);
defparam n603_s3.INIT=16'hAA3C;
  LUT4 n114_s4 (
    .F(n114_7),
    .I0(I_rgb_g[3]),
    .I1(I_rgb_g[5]),
    .I2(I_rgb_g[6]),
    .I3(n114_13) 
);
defparam n114_s4.INIT=16'h6996;
  LUT4 n114_s6 (
    .F(n114_9),
    .I0(I_rgb_g[6]),
    .I1(n114_13),
    .I2(I_rgb_g[3]),
    .I3(I_rgb_g[5]) 
);
defparam n114_s6.INIT=16'h7117;
  LUT4 n114_s7 (
    .F(n114_10),
    .I0(I_rgb_g[0]),
    .I1(I_rgb_g[1]),
    .I2(I_rgb_g[2]),
    .I3(I_rgb_g[4]) 
);
defparam n114_s7.INIT=16'h7EE8;
  LUT2 n114_s8 (
    .F(n114_11),
    .I0(I_rgb_g[3]),
    .I1(I_rgb_g[5]) 
);
defparam n114_s8.INIT=4'h8;
  LUT2 n114_s9 (
    .F(n114_12),
    .I0(n114_7),
    .I1(I_rgb_g[7]) 
);
defparam n114_s9.INIT=4'h8;
  LUT4 n630_s4 (
    .F(n630_7),
    .I0(n683_7),
    .I1(n630_8),
    .I2(n683_8),
    .I3(n683_9) 
);
defparam n630_s4.INIT=16'hACCA;
  LUT2 n683_s4 (
    .F(n683_7),
    .I0(din_d[4]),
    .I1(din_d[5]) 
);
defparam n683_s4.INIT=4'h6;
  LUT2 n683_s5 (
    .F(n683_8),
    .I0(din_d[2]),
    .I1(din_d[3]) 
);
defparam n683_s5.INIT=4'h6;
  LUT3 n683_s6 (
    .F(n683_9),
    .I0(din_d[0]),
    .I1(din_d[1]),
    .I2(din_d[6]) 
);
defparam n683_s6.INIT=8'h96;
  LUT2 n685_s3 (
    .F(n685_6),
    .I0(din_d[3]),
    .I1(din_d[4]) 
);
defparam n685_s3.INIT=4'h6;
  LUT2 cnt_one_9bit_0_s15 (
    .F(cnt_one_9bit_0_20),
    .I0(din_d[1]),
    .I1(sel_xnor) 
);
defparam cnt_one_9bit_0_s15.INIT=4'h6;
  LUT4 cnt_one_9bit_1_s17 (
    .F(cnt_one_9bit_1_23),
    .I0(sel_xnor),
    .I1(cnt_one_9bit_1_25),
    .I2(din_d[1]),
    .I3(n685_6) 
);
defparam cnt_one_9bit_1_s17.INIT=16'h5A3C;
  LUT4 cnt_one_9bit_1_s18 (
    .F(cnt_one_9bit_1_24),
    .I0(din_d[0]),
    .I1(cnt_one_9bit_0_20),
    .I2(n683_8),
    .I3(n683_7) 
);
defparam cnt_one_9bit_1_s18.INIT=16'hDD4B;
  LUT2 n604_s4 (
    .F(n604_8),
    .I0(n238_13),
    .I1(n239_15) 
);
defparam n604_s4.INIT=4'h8;
  LUT4 n114_s10 (
    .F(n114_13),
    .I0(I_rgb_g[0]),
    .I1(I_rgb_g[1]),
    .I2(I_rgb_g[2]),
    .I3(I_rgb_g[4]) 
);
defparam n114_s10.INIT=16'h6996;
  LUT4 n630_s5 (
    .F(n630_8),
    .I0(din_d[1]),
    .I1(sel_xnor),
    .I2(din_d[3]),
    .I3(din_d[4]) 
);
defparam n630_s5.INIT=16'h6996;
  LUT2 cnt_one_9bit_1_s19 (
    .F(cnt_one_9bit_1_25),
    .I0(din_d[0]),
    .I1(din_d[2]) 
);
defparam cnt_one_9bit_1_s19.INIT=4'h6;
  LUT4 cnt_one_9bit_0_s16 (
    .F(cnt_one_9bit_0_22),
    .I0(din_d[3]),
    .I1(din_d[5]),
    .I2(din_d[1]),
    .I3(sel_xnor) 
);
defparam cnt_one_9bit_0_s16.INIT=16'h6996;
  LUT4 n114_s11 (
    .F(n114_15),
    .I0(n114_9),
    .I1(n114_10),
    .I2(I_rgb_g[3]),
    .I3(I_rgb_g[5]) 
);
defparam n114_s11.INIT=16'h6999;
  LUT4 n603_s6 (
    .F(n603_11),
    .I0(n237_13),
    .I1(n238_13),
    .I2(n239_15),
    .I3(n236_11) 
);
defparam n603_s6.INIT=16'hEA15;
  LUT3 n685_s4 (
    .F(n685_8),
    .I0(din_d[3]),
    .I1(din_d[4]),
    .I2(n687_7) 
);
defparam n685_s4.INIT=8'h96;
  LUT4 n401_s4 (
    .F(n401_10),
    .I0(cnt[4]),
    .I1(cnt[1]),
    .I2(cnt[2]),
    .I3(cnt[3]) 
);
defparam n401_s4.INIT=16'hAAA9;
  LUT4 cnt_one_9bit_1_s20 (
    .F(cnt_one_9bit[1]),
    .I0(cnt_one_9bit_1_21),
    .I1(n630_7),
    .I2(cnt_one_9bit_1_23),
    .I3(cnt_one_9bit_1_24) 
);
defparam cnt_one_9bit_1_s20.INIT=16'h6996;
  LUT3 n687_s3 (
    .F(n687_7),
    .I0(din_d[2]),
    .I1(din_d[0]),
    .I2(din_d[1]) 
);
defparam n687_s3.INIT=8'h96;
  LUT4 n686_s2 (
    .F(n686_6),
    .I0(sel_xnor),
    .I1(n683_8),
    .I2(din_d[0]),
    .I3(din_d[1]) 
);
defparam n686_s2.INIT=16'h6996;
  LUT4 cnt_one_9bit_2_s16 (
    .F(cnt_one_9bit[2]),
    .I0(n630_5),
    .I1(cnt_one_9bit_1_21),
    .I2(cnt_one_9bit_3_15),
    .I3(cnt_one_9bit_1_22) 
);
defparam cnt_one_9bit_2_s16.INIT=16'h5554;
  LUT4 n683_s7 (
    .F(n683_11),
    .I0(din_d[4]),
    .I1(din_d[5]),
    .I2(n683_8),
    .I3(n683_9) 
);
defparam n683_s7.INIT=16'h6996;
  LUT4 n680_s3 (
    .F(n680_8),
    .I0(de_d),
    .I1(n630_3),
    .I2(sel_xnor),
    .I3(n653_3) 
);
defparam n680_s3.INIT=16'hFFD5;
  LUT4 n606_s2 (
    .F(n606_7),
    .I0(de_d),
    .I1(n596_2),
    .I2(n274_2),
    .I3(n630_3) 
);
defparam n606_s2.INIT=16'hA088;
  LUT2 n679_s2 (
    .F(n647_5),
    .I0(din_d[0]),
    .I1(sel_xnor) 
);
defparam n679_s2.INIT=4'h6;
  LUT2 n679_s1 (
    .F(n670_5),
    .I0(din_d[0]),
    .I1(n653_3) 
);
defparam n679_s1.INIT=4'h6;
  LUT4 n603_s7 (
    .F(n603_13),
    .I0(n364_3),
    .I1(cnt_one_9bit[3]),
    .I2(n365_11),
    .I3(n365_12) 
);
defparam n603_s7.INIT=16'h9669;
  DFFCE din_d_6_s0 (
    .Q(din_d[6]),
    .D(I_rgb_g[6]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_5_s0 (
    .Q(din_d[5]),
    .D(I_rgb_g[5]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_4_s0 (
    .Q(din_d[4]),
    .D(I_rgb_g[4]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_3_s0 (
    .Q(din_d[3]),
    .D(I_rgb_g[3]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_2_s0 (
    .Q(din_d[2]),
    .D(I_rgb_g[2]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_1_s0 (
    .Q(din_d[1]),
    .D(I_rgb_g[1]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_0_s0 (
    .Q(din_d[0]),
    .D(I_rgb_g[0]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE sel_xnor_s0 (
    .Q(sel_xnor),
    .D(n114_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE cnt_4_s0 (
    .Q(cnt[4]),
    .D(n603_5),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE cnt_3_s0 (
    .Q(cnt[3]),
    .D(n604_5),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE cnt_2_s0 (
    .Q(cnt[2]),
    .D(n605_5),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE cnt_1_s0 (
    .Q(cnt[1]),
    .D(n606_7),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_9_s0 (
    .Q(q_out_g[9]),
    .D(n680_8),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_8_s0 (
    .Q(q_out_g[8]),
    .D(n681_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_7_s0 (
    .Q(q_out_g[7]),
    .D(n682_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_6_s0 (
    .Q(q_out_g[6]),
    .D(n683_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_5_s0 (
    .Q(q_out_g[5]),
    .D(n684_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_4_s0 (
    .Q(q_out_g[4]),
    .D(n685_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_3_s0 (
    .Q(q_out_g[3]),
    .D(n686_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_2_s0 (
    .Q(q_out_g[2]),
    .D(n687_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_1_s0 (
    .Q(q_out_g[1]),
    .D(n688_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_0_s0 (
    .Q(q_out_g[0]),
    .D(n689_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_7_s0 (
    .Q(din_d[7]),
    .D(I_rgb_g[7]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  ALU n135_s (
    .SUM(n135_2),
    .COUT(n135_3),
    .I0(cnt[1]),
    .I1(cnt_one_9bit_0_18),
    .I3(GND),
    .CIN(GND) 
);
defparam n135_s.ALU_MODE=0;
  ALU n134_s (
    .SUM(n134_2),
    .COUT(n134_3),
    .I0(cnt[2]),
    .I1(cnt_one_9bit[1]),
    .I3(GND),
    .CIN(n135_3) 
);
defparam n134_s.ALU_MODE=0;
  ALU n133_s (
    .SUM(n133_2),
    .COUT(n133_3),
    .I0(cnt[3]),
    .I1(cnt_one_9bit[2]),
    .I3(GND),
    .CIN(n134_3) 
);
defparam n133_s.ALU_MODE=0;
  ALU n132_s (
    .SUM(n132_2),
    .COUT(n132_0_COUT),
    .I0(cnt[4]),
    .I1(cnt_one_9bit[3]),
    .I3(GND),
    .CIN(n133_3) 
);
defparam n132_s.ALU_MODE=0;
  ALU n560_s (
    .SUM(n560_2),
    .COUT(n560_3),
    .I0(n403_10),
    .I1(GND),
    .I3(GND),
    .CIN(n561_8) 
);
defparam n560_s.ALU_MODE=0;
  ALU n559_s (
    .SUM(n559_2),
    .COUT(n559_3),
    .I0(n402_10),
    .I1(GND),
    .I3(GND),
    .CIN(n560_3) 
);
defparam n559_s.ALU_MODE=0;
  ALU n558_s (
    .SUM(n558_2),
    .COUT(n558_0_COUT),
    .I0(n401_10),
    .I1(GND),
    .I3(GND),
    .CIN(n559_3) 
);
defparam n558_s.ALU_MODE=0;
  ALU n561_s1 (
    .SUM(n561_5),
    .COUT(n561_6),
    .I0(n561_9),
    .I1(cnt_one_9bit_0_18),
    .I3(GND),
    .CIN(GND) 
);
defparam n561_s1.ALU_MODE=0;
  ALU n560_s0 (
    .SUM(n560_4),
    .COUT(n560_5),
    .I0(n560_2),
    .I1(cnt_one_9bit[1]),
    .I3(GND),
    .CIN(n561_6) 
);
defparam n560_s0.ALU_MODE=0;
  ALU n559_s0 (
    .SUM(n559_4),
    .COUT(n559_5),
    .I0(n559_2),
    .I1(cnt_one_9bit[2]),
    .I3(GND),
    .CIN(n560_5) 
);
defparam n559_s0.ALU_MODE=0;
  ALU n558_s0 (
    .SUM(n558_4),
    .COUT(n558_1_COUT),
    .I0(n558_2),
    .I1(cnt_one_9bit[3]),
    .I3(GND),
    .CIN(n559_5) 
);
defparam n558_s0.ALU_MODE=0;
  ALU n366_s (
    .SUM(n366_3),
    .COUT(n366_4),
    .I0(cnt[2]),
    .I1(GND),
    .I3(GND),
    .CIN(n367_12) 
);
defparam n366_s.ALU_MODE=0;
  ALU n365_s (
    .SUM(n365_3),
    .COUT(n365_4),
    .I0(cnt[3]),
    .I1(GND),
    .I3(GND),
    .CIN(n366_4) 
);
defparam n365_s.ALU_MODE=0;
  ALU n364_s (
    .SUM(n364_3),
    .COUT(n364_0_COUT),
    .I0(cnt[4]),
    .I1(GND),
    .I3(GND),
    .CIN(n365_4) 
);
defparam n364_s.ALU_MODE=0;
  ALU n561_s2 (
    .SUM(n561_9),
    .COUT(n561_8),
    .I0(n404_10),
    .I1(sel_xnor),
    .I3(GND),
    .CIN(GND) 
);
defparam n561_s2.ALU_MODE=1;
  ALU n239_s6 (
    .SUM(n239_15),
    .COUT(n239_14),
    .I0(cnt[1]),
    .I1(cnt_one_9bit_0_18),
    .I3(GND),
    .CIN(GND) 
);
defparam n239_s6.ALU_MODE=1;
  ALU n238_s5 (
    .SUM(n238_13),
    .COUT(n238_12),
    .I0(cnt[2]),
    .I1(cnt_one_9bit[1]),
    .I3(GND),
    .CIN(n239_14) 
);
defparam n238_s5.ALU_MODE=1;
  ALU n237_s5 (
    .SUM(n237_13),
    .COUT(n237_12),
    .I0(cnt[3]),
    .I1(cnt_one_9bit[2]),
    .I3(GND),
    .CIN(n238_12) 
);
defparam n237_s5.ALU_MODE=1;
  ALU n236_s4 (
    .SUM(n236_11),
    .COUT(n236_5_COUT),
    .I0(cnt[4]),
    .I1(cnt_one_9bit[3]),
    .I3(GND),
    .CIN(n237_12) 
);
defparam n236_s4.ALU_MODE=1;
  ALU n367_s4 (
    .SUM(n367_13),
    .COUT(n367_12),
    .I0(cnt[1]),
    .I1(sel_xnor),
    .I3(GND),
    .CIN(GND) 
);
defparam n367_s4.ALU_MODE=1;
  ALU n367_s5 (
    .SUM(n367_16),
    .COUT(n367_15),
    .I0(n367_13),
    .I1(cnt_one_9bit_0_18),
    .I3(GND),
    .CIN(VCC) 
);
defparam n367_s5.ALU_MODE=1;
  ALU n366_s3 (
    .SUM(n366_12),
    .COUT(n366_11),
    .I0(n366_3),
    .I1(cnt_one_9bit[1]),
    .I3(GND),
    .CIN(n367_15) 
);
defparam n366_s3.ALU_MODE=1;
  ALU n365_s3 (
    .SUM(n365_12),
    .COUT(n365_11),
    .I0(n365_3),
    .I1(cnt_one_9bit[2]),
    .I3(GND),
    .CIN(n366_11) 
);
defparam n365_s3.ALU_MODE=1;
  MUX2_LUT5 n679_s0 (
    .O(n679_3),
    .I0(n670_5),
    .I1(n647_5),
    .S0(n630_3) 
);
  INV n404_s5 (
    .O(n404_10),
    .I(cnt[1]) 
);
  VCC VCC_cZ (
    .V(VCC)
);
  GND GND_cZ (
    .G(GND)
);
endmodule /* \~TMDS8b10b.DVI_TX_Top_0  */
module \~TMDS8b10b.DVI_TX_Top_1  (
  I_rgb_clk,
  n36_6,
  I_rgb_vs,
  I_rgb_hs,
  de_d,
  I_rgb_b,
  q_out_b
)
;
input I_rgb_clk;
input n36_6;
input I_rgb_vs;
input I_rgb_hs;
input de_d;
input [7:0] I_rgb_b;
output [9:0] q_out_b;
wire n274_2;
wire n596_2;
wire n114_3;
wire n630_3;
wire n653_3;
wire n680_3;
wire n681_4;
wire n682_3;
wire n683_4;
wire n684_3;
wire n685_4;
wire n686_3;
wire n687_4;
wire n688_3;
wire n689_3;
wire n605_5;
wire n604_5;
wire n603_5;
wire n403_10;
wire n402_10;
wire n114_4;
wire n114_5;
wire n114_6;
wire n630_4;
wire n630_5;
wire n653_4;
wire n653_5;
wire n680_4;
wire n682_4;
wire n682_5;
wire n688_4;
wire cnt_one_9bit_0_19;
wire cnt_one_9bit_0_20;
wire cnt_one_9bit_1_21;
wire cnt_one_9bit_1_22;
wire cnt_one_9bit_2_23;
wire cnt_one_9bit_2_24;
wire cnt_one_9bit_2_25;
wire n605_6;
wire n605_7;
wire n604_6;
wire n604_7;
wire n603_6;
wire n603_7;
wire n114_7;
wire n114_9;
wire n114_10;
wire n114_11;
wire n114_12;
wire n653_6;
wire n683_6;
wire n683_7;
wire n685_6;
wire n686_5;
wire cnt_one_9bit_1_23;
wire cnt_one_9bit_1_24;
wire cnt_one_9bit_2_26;
wire cnt_one_9bit_2_27;
wire n604_8;
wire n114_13;
wire cnt_one_9bit_1_25;
wire n114_15;
wire n603_11;
wire n685_8;
wire cnt_one_9bit_0_22;
wire n401_10;
wire n683_9;
wire n686_7;
wire n687_7;
wire n684_6;
wire n606_7;
wire n647_5;
wire n670_5;
wire n603_13;
wire c1_d;
wire sel_xnor;
wire c0_d;
wire n135_2;
wire n135_3;
wire n134_2;
wire n134_3;
wire n133_2;
wire n133_3;
wire n132_2;
wire n132_0_COUT;
wire n560_2;
wire n560_3;
wire n559_2;
wire n559_3;
wire n558_2;
wire n558_0_COUT;
wire n561_5;
wire n561_6;
wire n560_4;
wire n560_5;
wire n559_4;
wire n559_5;
wire n558_4;
wire n558_1_COUT;
wire n366_3;
wire n366_4;
wire n365_3;
wire n365_4;
wire n364_3;
wire n364_0_COUT;
wire n561_9;
wire n561_8;
wire n239_15;
wire n239_14;
wire n238_13;
wire n238_12;
wire n237_13;
wire n237_12;
wire n236_11;
wire n236_5_COUT;
wire n367_13;
wire n367_12;
wire n367_16;
wire n367_15;
wire n366_12;
wire n366_11;
wire n365_12;
wire n365_11;
wire n679_3;
wire n404_10;
wire [3:1] cnt_one_9bit;
wire [7:0] din_d;
wire [4:1] cnt;
wire VCC;
wire GND;
  LUT3 n274_s0 (
    .F(n274_2),
    .I0(n135_2),
    .I1(n239_15),
    .I2(sel_xnor) 
);
defparam n274_s0.INIT=8'h3A;
  LUT3 n596_s0 (
    .F(n596_2),
    .I0(n561_5),
    .I1(n367_16),
    .I2(n653_3) 
);
defparam n596_s0.INIT=8'hCA;
  LUT3 n114_s0 (
    .F(n114_3),
    .I0(n114_4),
    .I1(n114_5),
    .I2(n114_6) 
);
defparam n114_s0.INIT=8'hB2;
  LUT4 n630_s0 (
    .F(n630_3),
    .I0(n630_4),
    .I1(cnt_one_9bit[2]),
    .I2(cnt[4]),
    .I3(n630_5) 
);
defparam n630_s0.INIT=16'h4F44;
  LUT4 n653_s0 (
    .F(n653_3),
    .I0(cnt_one_9bit[3]),
    .I1(n630_4),
    .I2(n653_4),
    .I3(n653_5) 
);
defparam n653_s0.INIT=16'hFFE0;
  LUT4 n680_s0 (
    .F(n680_3),
    .I0(n680_4),
    .I1(c0_d),
    .I2(c1_d),
    .I3(de_d) 
);
defparam n680_s0.INIT=16'h55C3;
  LUT3 n681_s1 (
    .F(n681_4),
    .I0(c0_d),
    .I1(sel_xnor),
    .I2(de_d) 
);
defparam n681_s1.INIT=8'h35;
  LUT4 n682_s0 (
    .F(n682_3),
    .I0(c0_d),
    .I1(n682_4),
    .I2(n682_5),
    .I3(de_d) 
);
defparam n682_s0.INIT=16'h3CAA;
  LUT4 n683_s1 (
    .F(n683_4),
    .I0(c0_d),
    .I1(n683_9),
    .I2(n680_4),
    .I3(de_d) 
);
defparam n683_s1.INIT=16'hC355;
  LUT4 n684_s0 (
    .F(n684_3),
    .I0(c0_d),
    .I1(n680_4),
    .I2(n684_6),
    .I3(de_d) 
);
defparam n684_s0.INIT=16'hC3AA;
  LUT4 n685_s1 (
    .F(n685_4),
    .I0(c0_d),
    .I1(n680_4),
    .I2(n685_8),
    .I3(de_d) 
);
defparam n685_s1.INIT=16'hC355;
  LUT4 n686_s0 (
    .F(n686_3),
    .I0(c0_d),
    .I1(n686_7),
    .I2(n680_4),
    .I3(de_d) 
);
defparam n686_s0.INIT=16'hC3AA;
  LUT4 n687_s1 (
    .F(n687_4),
    .I0(c0_d),
    .I1(n680_4),
    .I2(n687_7),
    .I3(de_d) 
);
defparam n687_s1.INIT=16'hC355;
  LUT4 n688_s0 (
    .F(n688_3),
    .I0(c0_d),
    .I1(n688_4),
    .I2(n682_4),
    .I3(de_d) 
);
defparam n688_s0.INIT=16'h3CAA;
  LUT3 n689_s0 (
    .F(n689_3),
    .I0(c0_d),
    .I1(n679_3),
    .I2(de_d) 
);
defparam n689_s0.INIT=8'hCA;
  LUT4 cnt_one_9bit_2_s15 (
    .F(cnt_one_9bit[2]),
    .I0(cnt_one_9bit_2_23),
    .I1(cnt_one_9bit_1_22),
    .I2(cnt_one_9bit_2_24),
    .I3(cnt_one_9bit_2_25) 
);
defparam cnt_one_9bit_2_s15.INIT=16'hDC2B;
  LUT4 n605_s1 (
    .F(n605_5),
    .I0(n605_6),
    .I1(n605_7),
    .I2(n630_3),
    .I3(de_d) 
);
defparam n605_s1.INIT=16'hCA00;
  LUT4 n604_s1 (
    .F(n604_5),
    .I0(n604_6),
    .I1(n604_7),
    .I2(n630_3),
    .I3(de_d) 
);
defparam n604_s1.INIT=16'h3500;
  LUT4 n603_s1 (
    .F(n603_5),
    .I0(n603_6),
    .I1(n603_7),
    .I2(n630_3),
    .I3(de_d) 
);
defparam n603_s1.INIT=16'h3A00;
  LUT2 n403_s4 (
    .F(n403_10),
    .I0(cnt[1]),
    .I1(cnt[2]) 
);
defparam n403_s4.INIT=4'h9;
  LUT3 n402_s4 (
    .F(n402_10),
    .I0(cnt[1]),
    .I1(cnt[2]),
    .I2(cnt[3]) 
);
defparam n402_s4.INIT=8'hE1;
  LUT4 n114_s1 (
    .F(n114_4),
    .I0(I_rgb_b[0]),
    .I1(I_rgb_b[1]),
    .I2(I_rgb_b[2]),
    .I3(I_rgb_b[4]) 
);
defparam n114_s1.INIT=16'h8000;
  LUT4 n114_s2 (
    .F(n114_5),
    .I0(I_rgb_b[7]),
    .I1(n114_7),
    .I2(n114_15),
    .I3(I_rgb_b[0]) 
);
defparam n114_s2.INIT=16'h8100;
  LUT4 n114_s3 (
    .F(n114_6),
    .I0(n114_9),
    .I1(n114_10),
    .I2(n114_11),
    .I3(n114_12) 
);
defparam n114_s3.INIT=16'hFDD4;
  LUT4 n630_s1 (
    .F(n630_4),
    .I0(n683_9),
    .I1(cnt_one_9bit_0_19),
    .I2(cnt_one_9bit_0_20),
    .I3(cnt_one_9bit_1_21) 
);
defparam n630_s1.INIT=16'h7EBD;
  LUT3 n630_s2 (
    .F(n630_5),
    .I0(cnt[1]),
    .I1(cnt[2]),
    .I2(cnt[3]) 
);
defparam n630_s2.INIT=8'h01;
  LUT4 n653_s1 (
    .F(n653_4),
    .I0(n653_6),
    .I1(cnt_one_9bit_2_25),
    .I2(n630_5),
    .I3(cnt[4]) 
);
defparam n653_s1.INIT=16'h000D;
  LUT3 n653_s2 (
    .F(n653_5),
    .I0(n653_6),
    .I1(cnt_one_9bit_2_25),
    .I2(cnt[4]) 
);
defparam n653_s2.INIT=8'h20;
  LUT3 n680_s1 (
    .F(n680_4),
    .I0(n630_3),
    .I1(sel_xnor),
    .I2(n653_3) 
);
defparam n680_s1.INIT=8'h07;
  LUT3 n682_s1 (
    .F(n682_4),
    .I0(n630_3),
    .I1(sel_xnor),
    .I2(n653_3) 
);
defparam n682_s1.INIT=8'h14;
  LUT2 n682_s2 (
    .F(n682_5),
    .I0(din_d[7]),
    .I1(n683_9) 
);
defparam n682_s2.INIT=4'h6;
  LUT2 n688_s1 (
    .F(n688_4),
    .I0(din_d[0]),
    .I1(din_d[1]) 
);
defparam n688_s1.INIT=4'h6;
  LUT4 cnt_one_9bit_0_s14 (
    .F(cnt_one_9bit_0_19),
    .I0(din_d[1]),
    .I1(sel_xnor),
    .I2(din_d[3]),
    .I3(din_d[5]) 
);
defparam cnt_one_9bit_0_s14.INIT=16'h6996;
  LUT2 cnt_one_9bit_0_s15 (
    .F(cnt_one_9bit_0_20),
    .I0(sel_xnor),
    .I1(din_d[7]) 
);
defparam cnt_one_9bit_0_s15.INIT=4'h6;
  LUT3 cnt_one_9bit_1_s15 (
    .F(cnt_one_9bit_1_21),
    .I0(cnt_one_9bit_1_23),
    .I1(cnt_one_9bit_2_23),
    .I2(cnt_one_9bit_1_24) 
);
defparam cnt_one_9bit_1_s15.INIT=8'h96;
  LUT4 cnt_one_9bit_1_s16 (
    .F(cnt_one_9bit_1_22),
    .I0(n683_6),
    .I1(n683_7),
    .I2(cnt_one_9bit_0_19),
    .I3(cnt_one_9bit_0_20) 
);
defparam cnt_one_9bit_1_s16.INIT=16'h6FF9;
  LUT4 cnt_one_9bit_2_s16 (
    .F(cnt_one_9bit_2_23),
    .I0(cnt_one_9bit_0_19),
    .I1(n686_5),
    .I2(n683_7),
    .I3(cnt_one_9bit_2_26) 
);
defparam cnt_one_9bit_2_s16.INIT=16'hD728;
  LUT2 cnt_one_9bit_2_s17 (
    .F(cnt_one_9bit_2_24),
    .I0(cnt_one_9bit_1_23),
    .I1(cnt_one_9bit_1_24) 
);
defparam cnt_one_9bit_2_s17.INIT=4'h6;
  LUT4 cnt_one_9bit_2_s18 (
    .F(cnt_one_9bit_2_25),
    .I0(cnt_one_9bit_1_23),
    .I1(din_d[1]),
    .I2(cnt_one_9bit_2_27),
    .I3(cnt_one_9bit_1_24) 
);
defparam cnt_one_9bit_2_s18.INIT=16'hC3AA;
  LUT3 n605_s2 (
    .F(n605_6),
    .I0(n366_12),
    .I1(n560_4),
    .I2(n653_3) 
);
defparam n605_s2.INIT=8'hAC;
  LUT4 n605_s3 (
    .F(n605_7),
    .I0(n134_2),
    .I1(n238_13),
    .I2(n239_15),
    .I3(sel_xnor) 
);
defparam n605_s3.INIT=16'h3CAA;
  LUT3 n604_s2 (
    .F(n604_6),
    .I0(n365_12),
    .I1(n559_4),
    .I2(n653_3) 
);
defparam n604_s2.INIT=8'hAC;
  LUT4 n604_s3 (
    .F(n604_7),
    .I0(n133_2),
    .I1(n237_13),
    .I2(n604_8),
    .I3(sel_xnor) 
);
defparam n604_s3.INIT=16'h3CAA;
  LUT4 n603_s2 (
    .F(n603_6),
    .I0(n603_13),
    .I1(n559_4),
    .I2(n558_4),
    .I3(n653_3) 
);
defparam n603_s2.INIT=16'hAAC3;
  LUT4 n603_s3 (
    .F(n603_7),
    .I0(n603_11),
    .I1(n133_2),
    .I2(n132_2),
    .I3(sel_xnor) 
);
defparam n603_s3.INIT=16'hAA3C;
  LUT4 n114_s4 (
    .F(n114_7),
    .I0(I_rgb_b[3]),
    .I1(I_rgb_b[5]),
    .I2(I_rgb_b[6]),
    .I3(n114_13) 
);
defparam n114_s4.INIT=16'h6996;
  LUT4 n114_s6 (
    .F(n114_9),
    .I0(I_rgb_b[6]),
    .I1(n114_13),
    .I2(I_rgb_b[3]),
    .I3(I_rgb_b[5]) 
);
defparam n114_s6.INIT=16'h7117;
  LUT4 n114_s7 (
    .F(n114_10),
    .I0(I_rgb_b[0]),
    .I1(I_rgb_b[1]),
    .I2(I_rgb_b[2]),
    .I3(I_rgb_b[4]) 
);
defparam n114_s7.INIT=16'h7EE8;
  LUT2 n114_s8 (
    .F(n114_11),
    .I0(I_rgb_b[3]),
    .I1(I_rgb_b[5]) 
);
defparam n114_s8.INIT=4'h8;
  LUT2 n114_s9 (
    .F(n114_12),
    .I0(n114_7),
    .I1(I_rgb_b[7]) 
);
defparam n114_s9.INIT=4'h8;
  LUT4 n653_s3 (
    .F(n653_6),
    .I0(cnt_one_9bit_2_23),
    .I1(cnt_one_9bit_1_22),
    .I2(cnt_one_9bit_1_23),
    .I3(cnt_one_9bit_1_24) 
);
defparam n653_s3.INIT=16'h4DD4;
  LUT4 n683_s3 (
    .F(n683_6),
    .I0(din_d[2]),
    .I1(din_d[3]),
    .I2(din_d[4]),
    .I3(din_d[5]) 
);
defparam n683_s3.INIT=16'h6996;
  LUT3 n683_s4 (
    .F(n683_7),
    .I0(din_d[0]),
    .I1(din_d[1]),
    .I2(din_d[6]) 
);
defparam n683_s4.INIT=8'h96;
  LUT2 n685_s3 (
    .F(n685_6),
    .I0(din_d[3]),
    .I1(din_d[4]) 
);
defparam n685_s3.INIT=4'h6;
  LUT2 n686_s2 (
    .F(n686_5),
    .I0(din_d[2]),
    .I1(din_d[3]) 
);
defparam n686_s2.INIT=4'h6;
  LUT4 cnt_one_9bit_1_s17 (
    .F(cnt_one_9bit_1_23),
    .I0(sel_xnor),
    .I1(n686_5),
    .I2(n688_4),
    .I3(cnt_one_9bit_2_26) 
);
defparam cnt_one_9bit_1_s17.INIT=16'h0096;
  LUT4 cnt_one_9bit_1_s18 (
    .F(cnt_one_9bit_1_24),
    .I0(sel_xnor),
    .I1(cnt_one_9bit_1_25),
    .I2(cnt_one_9bit_2_27),
    .I3(n685_6) 
);
defparam cnt_one_9bit_1_s18.INIT=16'h5A3C;
  LUT2 cnt_one_9bit_2_s19 (
    .F(cnt_one_9bit_2_26),
    .I0(din_d[4]),
    .I1(din_d[5]) 
);
defparam cnt_one_9bit_2_s19.INIT=4'h6;
  LUT3 cnt_one_9bit_2_s20 (
    .F(cnt_one_9bit_2_27),
    .I0(din_d[1]),
    .I1(sel_xnor),
    .I2(din_d[0]) 
);
defparam cnt_one_9bit_2_s20.INIT=8'hC5;
  LUT2 n604_s4 (
    .F(n604_8),
    .I0(n238_13),
    .I1(n239_15) 
);
defparam n604_s4.INIT=4'h8;
  LUT4 n114_s10 (
    .F(n114_13),
    .I0(I_rgb_b[0]),
    .I1(I_rgb_b[1]),
    .I2(I_rgb_b[2]),
    .I3(I_rgb_b[4]) 
);
defparam n114_s10.INIT=16'h6996;
  LUT2 cnt_one_9bit_1_s19 (
    .F(cnt_one_9bit_1_25),
    .I0(din_d[0]),
    .I1(din_d[2]) 
);
defparam cnt_one_9bit_1_s19.INIT=4'h6;
  LUT4 cnt_one_9bit_1_s20 (
    .F(cnt_one_9bit[1]),
    .I0(cnt_one_9bit_1_23),
    .I1(cnt_one_9bit_2_23),
    .I2(cnt_one_9bit_1_24),
    .I3(cnt_one_9bit_1_22) 
);
defparam cnt_one_9bit_1_s20.INIT=16'h6996;
  LUT4 cnt_one_9bit_3_s12 (
    .F(cnt_one_9bit[3]),
    .I0(cnt_one_9bit_1_22),
    .I1(cnt_one_9bit_2_25),
    .I2(cnt_one_9bit_1_23),
    .I3(cnt_one_9bit_1_24) 
);
defparam cnt_one_9bit_3_s12.INIT=16'h4004;
  LUT4 n114_s11 (
    .F(n114_15),
    .I0(n114_9),
    .I1(n114_10),
    .I2(I_rgb_b[3]),
    .I3(I_rgb_b[5]) 
);
defparam n114_s11.INIT=16'h6999;
  LUT4 n603_s6 (
    .F(n603_11),
    .I0(n237_13),
    .I1(n238_13),
    .I2(n239_15),
    .I3(n236_11) 
);
defparam n603_s6.INIT=16'hEA15;
  LUT3 n685_s4 (
    .F(n685_8),
    .I0(din_d[3]),
    .I1(din_d[4]),
    .I2(n687_7) 
);
defparam n685_s4.INIT=8'h96;
  LUT3 cnt_one_9bit_0_s16 (
    .F(cnt_one_9bit_0_22),
    .I0(cnt_one_9bit_0_19),
    .I1(sel_xnor),
    .I2(din_d[7]) 
);
defparam cnt_one_9bit_0_s16.INIT=8'h96;
  LUT4 n401_s4 (
    .F(n401_10),
    .I0(cnt[4]),
    .I1(cnt[1]),
    .I2(cnt[2]),
    .I3(cnt[3]) 
);
defparam n401_s4.INIT=16'hAAA9;
  LUT4 n683_s5 (
    .F(n683_9),
    .I0(n683_6),
    .I1(din_d[0]),
    .I2(din_d[1]),
    .I3(din_d[6]) 
);
defparam n683_s5.INIT=16'h6996;
  LUT4 n686_s3 (
    .F(n686_7),
    .I0(sel_xnor),
    .I1(din_d[2]),
    .I2(din_d[3]),
    .I3(n688_4) 
);
defparam n686_s3.INIT=16'h6996;
  LUT3 n687_s3 (
    .F(n687_7),
    .I0(din_d[2]),
    .I1(din_d[0]),
    .I2(din_d[1]) 
);
defparam n687_s3.INIT=8'h96;
  LUT4 n684_s2 (
    .F(n684_6),
    .I0(sel_xnor),
    .I1(n683_6),
    .I2(din_d[0]),
    .I3(din_d[1]) 
);
defparam n684_s2.INIT=16'h6996;
  LUT4 n606_s2 (
    .F(n606_7),
    .I0(de_d),
    .I1(n596_2),
    .I2(n274_2),
    .I3(n630_3) 
);
defparam n606_s2.INIT=16'hA088;
  LUT2 n679_s2 (
    .F(n647_5),
    .I0(din_d[0]),
    .I1(sel_xnor) 
);
defparam n679_s2.INIT=4'h6;
  LUT2 n679_s1 (
    .F(n670_5),
    .I0(din_d[0]),
    .I1(n653_3) 
);
defparam n679_s1.INIT=4'h6;
  LUT4 n603_s7 (
    .F(n603_13),
    .I0(n364_3),
    .I1(cnt_one_9bit[3]),
    .I2(n365_11),
    .I3(n365_12) 
);
defparam n603_s7.INIT=16'h9669;
  DFFCE din_d_6_s0 (
    .Q(din_d[6]),
    .D(I_rgb_b[6]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_5_s0 (
    .Q(din_d[5]),
    .D(I_rgb_b[5]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_4_s0 (
    .Q(din_d[4]),
    .D(I_rgb_b[4]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_3_s0 (
    .Q(din_d[3]),
    .D(I_rgb_b[3]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_2_s0 (
    .Q(din_d[2]),
    .D(I_rgb_b[2]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_1_s0 (
    .Q(din_d[1]),
    .D(I_rgb_b[1]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_0_s0 (
    .Q(din_d[0]),
    .D(I_rgb_b[0]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFPE c1_d_s0 (
    .Q(c1_d),
    .D(I_rgb_vs),
    .CLK(I_rgb_clk),
    .PRESET(n36_6),
    .CE(VCC) 
);
  DFFCE sel_xnor_s0 (
    .Q(sel_xnor),
    .D(n114_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE cnt_4_s0 (
    .Q(cnt[4]),
    .D(n603_5),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE cnt_3_s0 (
    .Q(cnt[3]),
    .D(n604_5),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE cnt_2_s0 (
    .Q(cnt[2]),
    .D(n605_5),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE cnt_1_s0 (
    .Q(cnt[1]),
    .D(n606_7),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_9_s0 (
    .Q(q_out_b[9]),
    .D(n680_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_8_s0 (
    .Q(q_out_b[8]),
    .D(n681_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_7_s0 (
    .Q(q_out_b[7]),
    .D(n682_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_6_s0 (
    .Q(q_out_b[6]),
    .D(n683_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_5_s0 (
    .Q(q_out_b[5]),
    .D(n684_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_4_s0 (
    .Q(q_out_b[4]),
    .D(n685_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_3_s0 (
    .Q(q_out_b[3]),
    .D(n686_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_2_s0 (
    .Q(q_out_b[2]),
    .D(n687_4),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_1_s0 (
    .Q(q_out_b[1]),
    .D(n688_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE dout_0_s0 (
    .Q(q_out_b[0]),
    .D(n689_3),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFCE din_d_7_s0 (
    .Q(din_d[7]),
    .D(I_rgb_b[7]),
    .CLK(I_rgb_clk),
    .CLEAR(n36_6),
    .CE(VCC) 
);
  DFFPE c0_d_s0 (
    .Q(c0_d),
    .D(I_rgb_hs),
    .CLK(I_rgb_clk),
    .PRESET(n36_6),
    .CE(VCC) 
);
  ALU n135_s (
    .SUM(n135_2),
    .COUT(n135_3),
    .I0(cnt[1]),
    .I1(cnt_one_9bit_0_22),
    .I3(GND),
    .CIN(GND) 
);
defparam n135_s.ALU_MODE=0;
  ALU n134_s (
    .SUM(n134_2),
    .COUT(n134_3),
    .I0(cnt[2]),
    .I1(cnt_one_9bit[1]),
    .I3(GND),
    .CIN(n135_3) 
);
defparam n134_s.ALU_MODE=0;
  ALU n133_s (
    .SUM(n133_2),
    .COUT(n133_3),
    .I0(cnt[3]),
    .I1(cnt_one_9bit[2]),
    .I3(GND),
    .CIN(n134_3) 
);
defparam n133_s.ALU_MODE=0;
  ALU n132_s (
    .SUM(n132_2),
    .COUT(n132_0_COUT),
    .I0(cnt[4]),
    .I1(cnt_one_9bit[3]),
    .I3(GND),
    .CIN(n133_3) 
);
defparam n132_s.ALU_MODE=0;
  ALU n560_s (
    .SUM(n560_2),
    .COUT(n560_3),
    .I0(n403_10),
    .I1(GND),
    .I3(GND),
    .CIN(n561_8) 
);
defparam n560_s.ALU_MODE=0;
  ALU n559_s (
    .SUM(n559_2),
    .COUT(n559_3),
    .I0(n402_10),
    .I1(GND),
    .I3(GND),
    .CIN(n560_3) 
);
defparam n559_s.ALU_MODE=0;
  ALU n558_s (
    .SUM(n558_2),
    .COUT(n558_0_COUT),
    .I0(n401_10),
    .I1(GND),
    .I3(GND),
    .CIN(n559_3) 
);
defparam n558_s.ALU_MODE=0;
  ALU n561_s1 (
    .SUM(n561_5),
    .COUT(n561_6),
    .I0(n561_9),
    .I1(cnt_one_9bit_0_22),
    .I3(GND),
    .CIN(GND) 
);
defparam n561_s1.ALU_MODE=0;
  ALU n560_s0 (
    .SUM(n560_4),
    .COUT(n560_5),
    .I0(n560_2),
    .I1(cnt_one_9bit[1]),
    .I3(GND),
    .CIN(n561_6) 
);
defparam n560_s0.ALU_MODE=0;
  ALU n559_s0 (
    .SUM(n559_4),
    .COUT(n559_5),
    .I0(n559_2),
    .I1(cnt_one_9bit[2]),
    .I3(GND),
    .CIN(n560_5) 
);
defparam n559_s0.ALU_MODE=0;
  ALU n558_s0 (
    .SUM(n558_4),
    .COUT(n558_1_COUT),
    .I0(n558_2),
    .I1(cnt_one_9bit[3]),
    .I3(GND),
    .CIN(n559_5) 
);
defparam n558_s0.ALU_MODE=0;
  ALU n366_s (
    .SUM(n366_3),
    .COUT(n366_4),
    .I0(cnt[2]),
    .I1(GND),
    .I3(GND),
    .CIN(n367_12) 
);
defparam n366_s.ALU_MODE=0;
  ALU n365_s (
    .SUM(n365_3),
    .COUT(n365_4),
    .I0(cnt[3]),
    .I1(GND),
    .I3(GND),
    .CIN(n366_4) 
);
defparam n365_s.ALU_MODE=0;
  ALU n364_s (
    .SUM(n364_3),
    .COUT(n364_0_COUT),
    .I0(cnt[4]),
    .I1(GND),
    .I3(GND),
    .CIN(n365_4) 
);
defparam n364_s.ALU_MODE=0;
  ALU n561_s2 (
    .SUM(n561_9),
    .COUT(n561_8),
    .I0(n404_10),
    .I1(sel_xnor),
    .I3(GND),
    .CIN(GND) 
);
defparam n561_s2.ALU_MODE=1;
  ALU n239_s6 (
    .SUM(n239_15),
    .COUT(n239_14),
    .I0(cnt[1]),
    .I1(cnt_one_9bit_0_22),
    .I3(GND),
    .CIN(GND) 
);
defparam n239_s6.ALU_MODE=1;
  ALU n238_s5 (
    .SUM(n238_13),
    .COUT(n238_12),
    .I0(cnt[2]),
    .I1(cnt_one_9bit[1]),
    .I3(GND),
    .CIN(n239_14) 
);
defparam n238_s5.ALU_MODE=1;
  ALU n237_s5 (
    .SUM(n237_13),
    .COUT(n237_12),
    .I0(cnt[3]),
    .I1(cnt_one_9bit[2]),
    .I3(GND),
    .CIN(n238_12) 
);
defparam n237_s5.ALU_MODE=1;
  ALU n236_s4 (
    .SUM(n236_11),
    .COUT(n236_5_COUT),
    .I0(cnt[4]),
    .I1(cnt_one_9bit[3]),
    .I3(GND),
    .CIN(n237_12) 
);
defparam n236_s4.ALU_MODE=1;
  ALU n367_s4 (
    .SUM(n367_13),
    .COUT(n367_12),
    .I0(cnt[1]),
    .I1(sel_xnor),
    .I3(GND),
    .CIN(GND) 
);
defparam n367_s4.ALU_MODE=1;
  ALU n367_s5 (
    .SUM(n367_16),
    .COUT(n367_15),
    .I0(n367_13),
    .I1(cnt_one_9bit_0_22),
    .I3(GND),
    .CIN(VCC) 
);
defparam n367_s5.ALU_MODE=1;
  ALU n366_s3 (
    .SUM(n366_12),
    .COUT(n366_11),
    .I0(n366_3),
    .I1(cnt_one_9bit[1]),
    .I3(GND),
    .CIN(n367_15) 
);
defparam n366_s3.ALU_MODE=1;
  ALU n365_s3 (
    .SUM(n365_12),
    .COUT(n365_11),
    .I0(n365_3),
    .I1(cnt_one_9bit[2]),
    .I3(GND),
    .CIN(n366_11) 
);
defparam n365_s3.ALU_MODE=1;
  MUX2_LUT5 n679_s0 (
    .O(n679_3),
    .I0(n670_5),
    .I1(n647_5),
    .S0(n630_3) 
);
  INV n404_s5 (
    .O(n404_10),
    .I(cnt[1]) 
);
  VCC VCC_cZ (
    .V(VCC)
);
  GND GND_cZ (
    .G(GND)
);
endmodule /* \~TMDS8b10b.DVI_TX_Top_1  */
module \~rgb2dvi.DVI_TX_Top  (
  I_rgb_clk,
  I_serial_clk,
  I_rst_n,
  I_rgb_de,
  I_rgb_vs,
  I_rgb_hs,
  I_rgb_r,
  I_rgb_g,
  I_rgb_b,
  O_tmds_clk_p,
  O_tmds_clk_n,
  O_tmds_data_p,
  O_tmds_data_n
)
;
input I_rgb_clk;
input I_serial_clk;
input I_rst_n;
input I_rgb_de;
input I_rgb_vs;
input I_rgb_hs;
input [7:0] I_rgb_r;
input [7:0] I_rgb_g;
input [7:0] I_rgb_b;
output O_tmds_clk_p;
output O_tmds_clk_n;
output [2:0] O_tmds_data_p;
output [2:0] O_tmds_data_n;
wire sdataout_r;
wire sdataout_g;
wire sdataout_b;
wire sdataout_clk;
wire n36_6;
wire de_d;
wire c1_d;
wire [9:0] q_out_r;
wire [9:0] q_out_g;
wire [9:0] q_out_b;
wire VCC;
wire GND;
  TLVDS_OBUF u_LVDS_r (
    .O(O_tmds_data_p[2]),
    .OB(O_tmds_data_n[2]),
    .I(sdataout_r) 
);
  TLVDS_OBUF u_LVDS_g (
    .O(O_tmds_data_p[1]),
    .OB(O_tmds_data_n[1]),
    .I(sdataout_g) 
);
  TLVDS_OBUF u_LVDS_b (
    .O(O_tmds_data_p[0]),
    .OB(O_tmds_data_n[0]),
    .I(sdataout_b) 
);
  TLVDS_OBUF u_LVDS_clk (
    .O(O_tmds_clk_p),
    .OB(O_tmds_clk_n),
    .I(sdataout_clk) 
);
  OSER10 u_OSER10_r (
    .Q(sdataout_r),
    .D0(q_out_r[0]),
    .D1(q_out_r[1]),
    .D2(q_out_r[2]),
    .D3(q_out_r[3]),
    .D4(q_out_r[4]),
    .D5(q_out_r[5]),
    .D6(q_out_r[6]),
    .D7(q_out_r[7]),
    .D8(q_out_r[8]),
    .D9(q_out_r[9]),
    .PCLK(I_rgb_clk),
    .FCLK(I_serial_clk),
    .RESET(n36_6) 
);
  OSER10 u_OSER10_g (
    .Q(sdataout_g),
    .D0(q_out_g[0]),
    .D1(q_out_g[1]),
    .D2(q_out_g[2]),
    .D3(q_out_g[3]),
    .D4(q_out_g[4]),
    .D5(q_out_g[5]),
    .D6(q_out_g[6]),
    .D7(q_out_g[7]),
    .D8(q_out_g[8]),
    .D9(q_out_g[9]),
    .PCLK(I_rgb_clk),
    .FCLK(I_serial_clk),
    .RESET(n36_6) 
);
  OSER10 u_OSER10_b (
    .Q(sdataout_b),
    .D0(q_out_b[0]),
    .D1(q_out_b[1]),
    .D2(q_out_b[2]),
    .D3(q_out_b[3]),
    .D4(q_out_b[4]),
    .D5(q_out_b[5]),
    .D6(q_out_b[6]),
    .D7(q_out_b[7]),
    .D8(q_out_b[8]),
    .D9(q_out_b[9]),
    .PCLK(I_rgb_clk),
    .FCLK(I_serial_clk),
    .RESET(n36_6) 
);
  OSER10 u_OSER10_clk (
    .Q(sdataout_clk),
    .D0(GND),
    .D1(GND),
    .D2(GND),
    .D3(GND),
    .D4(GND),
    .D5(VCC),
    .D6(VCC),
    .D7(VCC),
    .D8(VCC),
    .D9(VCC),
    .PCLK(I_rgb_clk),
    .FCLK(I_serial_clk),
    .RESET(n36_6) 
);
  INV n36_s2 (
    .O(n36_6),
    .I(I_rst_n) 
);
  \~TMDS8b10b.DVI_TX_Top  TMDS8b10b_inst_r (
    .I_rgb_clk(I_rgb_clk),
    .n36_6(n36_6),
    .I_rgb_de(I_rgb_de),
    .I_rgb_r(I_rgb_r[7:0]),
    .de_d(de_d),
    .c1_d(c1_d),
    .q_out_r(q_out_r[9:0])
);
  \~TMDS8b10b.DVI_TX_Top_0  TMDS8b10b_inst_g (
    .I_rgb_clk(I_rgb_clk),
    .n36_6(n36_6),
    .c1_d(c1_d),
    .de_d(de_d),
    .I_rgb_g(I_rgb_g[7:0]),
    .q_out_g(q_out_g[9:0])
);
  \~TMDS8b10b.DVI_TX_Top_1  TMDS8b10b_inst_b (
    .I_rgb_clk(I_rgb_clk),
    .n36_6(n36_6),
    .I_rgb_vs(I_rgb_vs),
    .I_rgb_hs(I_rgb_hs),
    .de_d(de_d),
    .I_rgb_b(I_rgb_b[7:0]),
    .q_out_b(q_out_b[9:0])
);
  VCC VCC_cZ (
    .V(VCC)
);
  GND GND_cZ (
    .G(GND)
);
endmodule /* \~rgb2dvi.DVI_TX_Top  */
 module DVI_TX_Top (
  I_rst_n,
  I_serial_clk,
  I_rgb_clk,
  I_rgb_vs,
  I_rgb_hs,
  I_rgb_de,
  I_rgb_r,
  I_rgb_g,
  I_rgb_b,
  O_tmds_clk_p,
  O_tmds_clk_n,
  O_tmds_data_p,
  O_tmds_data_n
)
;
input I_rst_n;
input I_serial_clk;
input I_rgb_clk;
input I_rgb_vs;
input I_rgb_hs;
input I_rgb_de;
input [7:0] I_rgb_r;
input [7:0] I_rgb_g;
input [7:0] I_rgb_b;
output O_tmds_clk_p;
output O_tmds_clk_n;
output [2:0] O_tmds_data_p;
output [2:0] O_tmds_data_n;
wire VCC;
wire GND;
  \~rgb2dvi.DVI_TX_Top  rgb2dvi_inst (
    .I_rgb_clk(I_rgb_clk),
    .I_serial_clk(I_serial_clk),
    .I_rst_n(I_rst_n),
    .I_rgb_de(I_rgb_de),
    .I_rgb_vs(I_rgb_vs),
    .I_rgb_hs(I_rgb_hs),
    .I_rgb_r(I_rgb_r[7:0]),
    .I_rgb_g(I_rgb_g[7:0]),
    .I_rgb_b(I_rgb_b[7:0]),
    .O_tmds_clk_p(O_tmds_clk_p),
    .O_tmds_clk_n(O_tmds_clk_n),
    .O_tmds_data_p(O_tmds_data_p[2:0]),
    .O_tmds_data_n(O_tmds_data_n[2:0])
);
  VCC VCC_cZ (
    .V(VCC)
);
  GND GND_cZ (
    .G(GND)
);
  GSR GSR (
    .GSRI(VCC) 
);
endmodule /* DVI_TX_Top */
