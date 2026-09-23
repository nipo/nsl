#
#  TEI0003 - CYC1000 pin assignments - 4
# 

package require ::quartus::project

set_global_assignment -name TOP_LEVEL_ENTITY top_4
set_global_assignment -name VERILOG_FILE top_4.v
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name ENABLE_DEVICE_WIDE_RESET ON

set_location_assignment PIN_M2 -to CLK12M
set_location_assignment PIN_E15 -to CLK_X
set_location_assignment PIN_N6 -to USER_BTN

set_location_assignment PIN_M6 -to LED1
set_location_assignment PIN_T4 -to LED2
set_location_assignment PIN_T3 -to LED3
set_location_assignment PIN_R3 -to LED4
set_location_assignment PIN_T2 -to LED5
set_location_assignment PIN_R4 -to LED6
set_location_assignment PIN_N5 -to LED7
set_location_assignment PIN_N3 -to LED8

set_location_assignment PIN_A3 -to A[0]
set_location_assignment PIN_B5 -to A[1]
set_location_assignment PIN_B4 -to A[2]
set_location_assignment PIN_B3 -to A[3]
set_location_assignment PIN_C3 -to A[4]
set_location_assignment PIN_D3 -to A[5]
set_location_assignment PIN_E6 -to A[6]
set_location_assignment PIN_E7 -to A[7]
set_location_assignment PIN_D6 -to A[8]
set_location_assignment PIN_D8 -to A[9]
set_location_assignment PIN_A5 -to A[10]
set_location_assignment PIN_E8 -to A[11]
# set_location_assignment PIN_A2 -to A[12]
# set_location_assignment PIN_C6 -to A[13]
set_location_assignment PIN_A4 -to BA[0]
set_location_assignment PIN_B6 -to BA[1]
set_location_assignment PIN_C8 -to CAS
set_location_assignment PIN_B14 -to CLK
set_location_assignment PIN_F8 -to CKE
set_location_assignment PIN_A6 -to CS
set_location_assignment PIN_D12 -to DQM[1]
set_location_assignment PIN_B13 -to DQM[0]
set_location_assignment PIN_B10 -to DQ[0]
set_location_assignment PIN_A10 -to DQ[1]
set_location_assignment PIN_B11 -to DQ[2]
set_location_assignment PIN_A11 -to DQ[3]
set_location_assignment PIN_A12 -to DQ[4]
set_location_assignment PIN_D9 -to DQ[5]
set_location_assignment PIN_B12 -to DQ[6]
set_location_assignment PIN_C9 -to DQ[7]
set_location_assignment PIN_D11 -to DQ[8]
set_location_assignment PIN_E11 -to DQ[9]
set_location_assignment PIN_A15 -to DQ[10]
set_location_assignment PIN_E9 -to DQ[11]
set_location_assignment PIN_D14 -to DQ[12]
set_location_assignment PIN_F9 -to DQ[13]
set_location_assignment PIN_C14 -to DQ[14]
set_location_assignment PIN_A14 -to DQ[15]
set_location_assignment PIN_A7 -to WE
set_location_assignment PIN_B7 -to RAS

set_location_assignment PIN_F3 -to SEN_SPC
set_location_assignment PIN_D1 -to SEN_CS
set_location_assignment PIN_G1 -to SEN_SDO
set_location_assignment PIN_G2 -to SEN_SDI
set_location_assignment PIN_B1 -to SEN_INT1
set_location_assignment PIN_C2 -to SEN_INT2

set_location_assignment PIN_R7 -to BDBUS0
set_location_assignment PIN_T7 -to BDBUS1
set_location_assignment PIN_R6 -to BDBUS2
set_location_assignment PIN_T6 -to BDBUS3
set_location_assignment PIN_R5 -to BDBUS4
set_location_assignment PIN_T5 -to BDBUS5
set_location_assignment PIN_M8 -to ADBUS4
set_location_assignment PIN_N8 -to ADBUS7

set_location_assignment PIN_T12 -to AIN
set_location_assignment PIN_R12 -to AIN0
set_location_assignment PIN_T13 -to AIN1
set_location_assignment PIN_R13 -to AIN2
set_location_assignment PIN_T14 -to AIN3
set_location_assignment PIN_P14 -to AIN4
set_location_assignment PIN_R14 -to AIN5
set_location_assignment PIN_T15 -to AIN6
set_location_assignment PIN_R11 -to AIN7

set_location_assignment PIN_N16 -to D0
set_location_assignment PIN_L15 -to D1
set_location_assignment PIN_L16 -to D2
set_location_assignment PIN_K15 -to D3
set_location_assignment PIN_K16 -to D4
set_location_assignment PIN_J14 -to D5
set_location_assignment PIN_N2 -to D6
set_location_assignment PIN_N1 -to D7
set_location_assignment PIN_P2 -to D8
set_location_assignment PIN_J1 -to D9
set_location_assignment PIN_J2 -to D10
set_location_assignment PIN_K2 -to D11
set_location_assignment PIN_K1 -to D11_R
set_location_assignment PIN_L2 -to D12
set_location_assignment PIN_L1 -to D12_R
set_location_assignment PIN_P1 -to D13
set_location_assignment PIN_R1 -to D14

set_location_assignment PIN_F13 -to PIO_01
set_location_assignment PIN_F15 -to PIO_02
set_location_assignment PIN_F16 -to PIO_03
set_location_assignment PIN_D16 -to PIO_04
set_location_assignment PIN_D15 -to PIO_05
set_location_assignment PIN_C15 -to PIO_06
set_location_assignment PIN_B16 -to PIO_07
set_location_assignment PIN_C16 -to PIO_08