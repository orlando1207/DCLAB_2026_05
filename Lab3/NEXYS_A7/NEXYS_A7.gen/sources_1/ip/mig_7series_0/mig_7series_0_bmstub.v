// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// -------------------------------------------------------------------------------

`timescale 1 ps / 1 ps

(* BLOCK_STUB = "true" *)
module mig_7series_0 (
  sys_rst,
  ddr2_dq,
  ddr2_dqs_p,
  ddr2_dqs_n,
  ddr2_addr,
  ddr2_ba,
  ddr2_ras_n,
  ddr2_cas_n,
  ddr2_we_n,
  ddr2_ck_p,
  ddr2_ck_n,
  ddr2_cke,
  ddr2_cs_n,
  ddr2_dm,
  ddr2_odt,
  app_addr,
  app_cmd,
  app_en,
  app_wdf_data,
  app_wdf_end,
  app_wdf_mask,
  app_wdf_wren,
  app_rd_data,
  app_rd_data_end,
  app_rd_data_valid,
  app_rdy,
  app_wdf_rdy,
  app_sr_req,
  app_sr_active,
  app_ref_req,
  app_ref_ack,
  app_zq_req,
  app_zq_ack,
  ui_clk_sync_rst,
  ui_clk,
  sys_clk_i,
  init_calib_complete,
  aresetn
);

  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 SYSTEM_RESET RST" *)
  (* X_INTERFACE_MODE = "slave SYSTEM_RESET" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME SYSTEM_RESET, POLARITY ACTIVE_LOW, BOARD.ASSOCIATED_PARAM RESET_BOARD_INTERFACE, INSERT_VIP 0" *)
  input sys_rst;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 DQ" *)
  (* X_INTERFACE_MODE = "master DDR2" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME DDR2, CAN_DEBUG false, TIMEPERIOD_PS 1250, MEMORY_TYPE COMPONENTS, MEMORY_PART , DATA_WIDTH 8, CS_ENABLED true, DATA_MASK_ENABLED true, SLOT Single, CUSTOM_PARTS , MEM_ADDR_MAP ROW_COLUMN_BANK, BURST_LENGTH 8, AXI_ARBITRATION_SCHEME TDM, CAS_LATENCY 11, CAS_WRITE_LATENCY 11" *)
  inout [15:0]ddr2_dq;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 DQS_P" *)
  inout [1:0]ddr2_dqs_p;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 DQS_N" *)
  inout [1:0]ddr2_dqs_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 ADDR" *)
  output [12:0]ddr2_addr;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 BA" *)
  output [2:0]ddr2_ba;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 RAS_N" *)
  output ddr2_ras_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 CAS_N" *)
  output ddr2_cas_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 WE_N" *)
  output ddr2_we_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 CK_P" *)
  output [0:0]ddr2_ck_p;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 CK_N" *)
  output [0:0]ddr2_ck_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 CKE" *)
  output [0:0]ddr2_cke;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 CS_N" *)
  output [0:0]ddr2_cs_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 DM" *)
  output [1:0]ddr2_dm;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR2 ODT" *)
  output [0:0]ddr2_odt;
  (* X_INTERFACE_IGNORE = "true" *)
  input [7:0]app_addr;
  (* X_INTERFACE_IGNORE = "true" *)
  input [2:0]app_cmd;
  (* X_INTERFACE_IGNORE = "true" *)
  input app_en;
  (* X_INTERFACE_IGNORE = "true" *)
  input [31:0]app_wdf_data;
  (* X_INTERFACE_IGNORE = "true" *)
  input app_wdf_end;
  (* X_INTERFACE_IGNORE = "true" *)
  input [3:0]app_wdf_mask;
  (* X_INTERFACE_IGNORE = "true" *)
  input app_wdf_wren;
  (* X_INTERFACE_IGNORE = "true" *)
  output [31:0]app_rd_data;
  (* X_INTERFACE_IGNORE = "true" *)
  output app_rd_data_end;
  (* X_INTERFACE_IGNORE = "true" *)
  output app_rd_data_valid;
  (* X_INTERFACE_IGNORE = "true" *)
  output app_rdy;
  (* X_INTERFACE_IGNORE = "true" *)
  output app_wdf_rdy;
  (* X_INTERFACE_IGNORE = "true" *)
  input app_sr_req;
  (* X_INTERFACE_IGNORE = "true" *)
  output app_sr_active;
  (* X_INTERFACE_IGNORE = "true" *)
  input app_ref_req;
  (* X_INTERFACE_IGNORE = "true" *)
  output app_ref_ack;
  (* X_INTERFACE_IGNORE = "true" *)
  input app_zq_req;
  (* X_INTERFACE_IGNORE = "true" *)
  output app_zq_ack;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RESET RST" *)
  (* X_INTERFACE_MODE = "master RESET" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RESET, POLARITY ACTIVE_HIGH, INSERT_VIP 0" *)
  output ui_clk_sync_rst;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLOCK CLK" *)
  (* X_INTERFACE_MODE = "master CLOCK" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLOCK, FREQ_HZ 150015002, ASSOCIATED_BUSIF S_AXI:S_AXI_CTRL, ASSOCIATED_RESET aresetn:ui_clk_sync_rst, PHASE 0, FREQ_TOLERANCE_HZ 0, CLK_DOMAIN , ASSOCIATED_PORT , INSERT_VIP 0" *)
  output ui_clk;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 SYS_CLK_I CLK" *)
  (* X_INTERFACE_MODE = "slave SYS_CLK_I" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME SYS_CLK_I, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN , ASSOCIATED_BUSIF , ASSOCIATED_PORT , ASSOCIATED_RESET , INSERT_VIP 0" *)
  input sys_clk_i;
  (* X_INTERFACE_IGNORE = "true" *)
  output init_calib_complete;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ARESETN ARESETN" *)
  (* X_INTERFACE_MODE = "slave ARESETN" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ARESETN, POLARITY ACTIVE_LOW, INSERT_VIP 0" *)
  input aresetn;

  // stub module has no contents

endmodule
