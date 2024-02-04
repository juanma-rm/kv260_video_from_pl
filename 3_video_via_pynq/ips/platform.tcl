##############################################################################
# Top block design to wrap ZUS+ block, reset, interrupts, user logic, etc.
# 
# It expects to be sourced from within the folder that contains the Vivado project
##############################################################################

##############################################################################
# General parameters
##############################################################################

set PL0_CLK_FREQ_MHZ 100
set PROJECT_NAME video_via_pynq
set BD_TOP bd_top
set EXTENSIBLE_PLATFORM false

# Select FAN_CONTROL value among the following options
set fan_control_type {ttc0_linux counter_fpga default}
set FAN_CONTROL "counter_fpga"

##############################################################################
# Main block design based on ZUS+ MPSoC
##############################################################################

# Create block diagram top
create_bd_design "$BD_TOP"
update_compile_order -fileset sources_1

# Zynq Ultrscale+ MPSoC block (default preset)
set zynq_ultra_ps [ create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.4 zynq_ultra_ps ]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1" }  $zynq_ultra_ps
set_property -dict [ list \
    CONFIG.PSU__USE__M_AXI_GP0 {1}                               \
    CONFIG.PSU__USE__M_AXI_GP1 {0}                               \
    CONFIG.PSU__USE__M_AXI_GP2 {0}                               \
    CONFIG.PSU__USE__S_AXI_GP0 {0}                               \
    CONFIG.PSU__USE__S_AXI_GP2 {0}                               \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ $PL0_CLK_FREQ_MHZ \
    CONFIG.PSU__TTC0__PERIPHERAL__ENABLE {1}                     \
    CONFIG.PSU__TTC0__WAVEOUT__ENABLE {1}                        \
    CONFIG.PSU__TTC0__WAVEOUT__IO {EMIO}                         \
    CONFIG.PSU__USE__VIDEO {1}                                   \
] $zynq_ultra_ps

##############################################################################
# Clocking Wizard block
##############################################################################

set clk_wiz_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0 ]
set_property -dict [ list \
    CONFIG.CLKOUT1_DRIVES {Buffer} \
    CONFIG.CLKOUT1_JITTER {97.198} \
    CONFIG.CLKOUT1_PHASE_ERROR {76.002} \
    CONFIG.CLKOUT2_DRIVES {Buffer} \
    CONFIG.CLKOUT2_JITTER {80.036} \
    CONFIG.CLKOUT2_PHASE_ERROR {76.002} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {300.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT3_DRIVES {Buffer} \
    CONFIG.CLKOUT3_JITTER {90.524} \
    CONFIG.CLKOUT3_PHASE_ERROR {76.002} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {148.5} \
    CONFIG.CLKOUT3_USED {true} \
    CONFIG.CLKOUT4_DRIVES {Buffer} \
    CONFIG.CLKOUT5_DRIVES {Buffer} \
    CONFIG.CLKOUT6_DRIVES {Buffer} \
    CONFIG.CLKOUT7_DRIVES {Buffer} \
    CONFIG.CLK_OUT1_PORT {clk_100M} \
    CONFIG.CLK_OUT2_PORT {clk_300M} \
    CONFIG.CLK_OUT3_PORT {clk_148_5M} \
    CONFIG.FEEDBACK_SOURCE {FDBK_AUTO} \
    CONFIG.MMCM_BANDWIDTH {OPTIMIZED} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {14.875} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {14.875} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {5} \
    CONFIG.MMCM_CLKOUT2_DIVIDE {10} \
    CONFIG.MMCM_COMPENSATION {AUTO} \
    CONFIG.NUM_OUT_CLKS {3} \
    CONFIG.OPTIMIZE_CLOCKING_STRUCTURE_EN {true} \
    CONFIG.PRIMITIVE {Auto} \
    CONFIG.USE_LOCKED {false} \
    CONFIG.USE_RESET {false} \
] $clk_wiz_0

##############################################################################
# Reset blocks
##############################################################################

set ps_reset_100M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 ps_reset_100M ]
set ps_reset_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 ps_reset_300M ]

##############################################################################
# Interrupts (xlconcat)
##############################################################################

set xlconcat_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0 ]

##############################################################################
# AXI Interconnects
##############################################################################

set axi_interc_hpm0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interc_hpm0 ]
set_property -dict [ list \
    CONFIG.NUM_MI {1} \
] $axi_interc_hpm0

##############################################################################
# Fan control
##############################################################################

if {$FAN_CONTROL eq "ttc0_linux"} {
    # Fan control from PS TTC0 EMIO waveout
    # Add slice IP and configure to take bit 2 from a 3-bit wide input
    set xlslice_fan [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_fan ]
    set_property    CONFIG.DIN_TO {2}                       $xlslice_fan
    set_property    CONFIG.DIN_FROM {2}                     $xlslice_fan
    set_property    CONFIG.DIN_WIDTH {3}                    $xlslice_fan
    set_property    CONFIG.DOUT_WIDTH {1}                   $xlslice_fan
} elseif {$FAN_CONTROL eq "counter_fpga"} {
    # Fan control from FPGA pwm module
    set pwm [ create_bd_cell -type module -reference pwm pwm_inst ]
    # fan_en_b works with negative logic, for what a not gate is used
    create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 util_vector_logic_0
    set_property -dict [list CONFIG.C_SIZE {1} CONFIG.C_OPERATION {not} CONFIG.LOGO_FILE {data/sym_notgate.png}] [get_bd_cells util_vector_logic_0]
    # duty_cycle_in driven by 7-bit constant set at 20 (duty cycle = 20%)
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_0
    set_property -dict [list CONFIG.CONST_WIDTH {7} CONFIG.CONST_VAL {20}] [get_bd_cells xlconstant_0]
} elseif {[lsearch -exact $fan_control_type $FAN_CONTROL] == -1} {
    puts "Error: FAN_CONTROL must be one of {ttc0_linux counter_fpga default}"
    exit 1
}

##############################################################################
# counter_wrapper
##############################################################################

set counter_wrapper [ create_bd_cell -type module -reference counter_wrapper counter_wrapper_inst ]

##############################################################################
# Video control: video generator + Video Timing Controller + AXI4S to Video Out
##############################################################################

# Video generator
set axis_video_gen_wrapper_inst [ create_bd_cell -type module -reference axis_video_pattern_generator_wrapper axis_video_gen_wrapper_inst ]
set_property -dict [ list \
    CONFIG.NUM_COLS {1920} \
    CONFIG.NUM_ROWS {1080} \
] $axis_video_gen_wrapper_inst

# Video Timing Controller
set v_tc_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_tc:6.2 v_tc_0 ]
set_property -dict [ list \
    CONFIG.GEN_F0_VBLANK_HEND {2008} \
    CONFIG.GEN_F0_VBLANK_HSTART {2008} \
    CONFIG.GEN_F0_VFRAME_SIZE {1125} \
    CONFIG.GEN_F0_VSYNC_HEND {2008} \
    CONFIG.GEN_F0_VSYNC_HSTART {2008} \
    CONFIG.GEN_F0_VSYNC_VEND {1088} \
    CONFIG.GEN_F0_VSYNC_VSTART {1083} \
    CONFIG.GEN_F1_VBLANK_HEND {2008} \
    CONFIG.GEN_F1_VBLANK_HSTART {2008} \
    CONFIG.GEN_F1_VFRAME_SIZE {1125} \
    CONFIG.GEN_F1_VSYNC_HEND {2008} \
    CONFIG.GEN_F1_VSYNC_HSTART {2008} \
    CONFIG.GEN_F1_VSYNC_VEND {1088} \
    CONFIG.GEN_F1_VSYNC_VSTART {1083} \
    CONFIG.GEN_HACTIVE_SIZE {1920} \
    CONFIG.GEN_HFRAME_SIZE {2200} \
    CONFIG.GEN_HSYNC_END {2052} \
    CONFIG.GEN_HSYNC_START {2008} \
    CONFIG.GEN_VACTIVE_SIZE {1080} \
    CONFIG.VIDEO_MODE {1080p} \
    CONFIG.enable_detection {false} \
    CONFIG.max_clocks_per_line {8192} \
] $v_tc_0

# axis4 stream to video out
set v_axi4s_vid_out_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_axi4s_vid_out:4.0 v_axi4s_vid_out_0 ]
set_property -dict [ list \
    CONFIG.C_HAS_ASYNC_CLK {1} \
    CONFIG.C_NATIVE_COMPONENT_WIDTH {12} \
] $v_axi4s_vid_out_0

##############################################################################
# Connections
##############################################################################

set pl_clk0 [get_bd_pins $zynq_ultra_ps/pl_clk0]
set pl_resetn0 [get_bd_pins $zynq_ultra_ps/pl_resetn0]

# clk_wiz_0
connect_bd_net -net zynq_ultra_ps_e_0_pl_clk0 [get_bd_pins clk_wiz_0/clk_in1] $pl_clk0
connect_bd_net -net clk_wiz_0_clk_100M [get_bd_pins clk_wiz_0/clk_100M] [get_bd_pins axi_interc_hpm0/ACLK] [get_bd_pins axi_interc_hpm0/M00_ACLK] [get_bd_pins axi_interc_hpm0/S00_ACLK] [get_bd_pins ps_reset_100M/slowest_sync_clk] [get_bd_pins v_tc_0/s_axi_aclk] [get_bd_pins zynq_ultra_ps/maxihpm0_fpd_aclk]
connect_bd_net -net clk_wiz_0_clk_148_5M [get_bd_pins clk_wiz_0/clk_148_5M] [get_bd_pins system_ila_0/clk] [get_bd_pins v_axi4s_vid_out_0/vid_io_out_clk] [get_bd_pins v_tc_0/clk] [get_bd_pins zynq_ultra_ps/dp_video_in_clk]
connect_bd_net -net clk_wiz_0_clk_300M [get_bd_pins clk_wiz_0/clk_300M] [get_bd_pins axi_interc_hpm0/M01_ACLK] [get_bd_pins ps_reset_300M/slowest_sync_clk] [get_bd_pins system_ila_1/clk] [get_bd_pins v_axi4s_vid_out_0/aclk] [get_bd_pins axis_video_gen_wrapper_inst/clk_i]

# ps_reset_100M
connect_bd_net $pl_resetn0 [get_bd_pins ps_reset_100M/ext_reset_in]
connect_bd_net -net ps_reset_100M_peripheral_aresetn [get_bd_pins ps_reset_100M/peripheral_aresetn] [get_bd_pins axi_interc_hpm0/ARESETN] [get_bd_pins axi_interc_hpm0/M00_ARESETN] [get_bd_pins axi_interc_hpm0/S00_ARESETN] [get_bd_pins v_tc_0/s_axi_aresetn]

# ps_reset_300M
connect_bd_net $pl_resetn0 [get_bd_pins ps_reset_300M/ext_reset_in]
connect_bd_net -net ps_reset_300M_peripheral_aresetn [get_bd_pins ps_reset_300M/peripheral_aresetn] [get_bd_pins axi_interc_hpm0/M01_ARESETN] [get_bd_pins v_axi4s_vid_out_0/aresetn]
connect_bd_net -net ps_reset_300M_peripheral_reset [get_bd_pins ps_reset_300M/peripheral_reset] [get_bd_pins axis_video_gen_wrapper_inst/rst_i]

# Interrupts
connect_bd_net -net xlconcat_0_dout [get_bd_pins xlconcat_0/dout] [get_bd_pins zynq_ultra_ps/pl_ps_irq0]
connect_bd_net -net v_tc_0_irq [get_bd_pins v_tc_0/irq] [get_bd_pins xlconcat_0/In0]

# axi_interc_hpm0
connect_bd_intf_net -intf_net zynq_ultra_ps_M_AXI_HPM0_FPD [get_bd_intf_pins axi_interc_hpm0/S00_AXI] [get_bd_intf_pins zynq_ultra_ps/M_AXI_HPM0_FPD]
connect_bd_intf_net -intf_net axi_interc_hpm0_M00_AXI [get_bd_intf_pins axi_interc_hpm0/M00_AXI] [get_bd_intf_pins v_tc_0/ctrl]

# Video generator
connect_bd_intf_net -intf_net axis_video_gen_wrapper_m_axis_video [get_bd_intf_pins axis_video_gen_wrapper_inst/m_axis_video] [get_bd_intf_pins v_axi4s_vid_out_0/video_in] 
# Avoid Vivado from complaining when connecting axis interfaces
set_property CONFIG.FREQ_HZ 297497025 [get_bd_intf_pins /axis_video_gen_wrapper_inst/m_axis_video]

# Video Timing Controller
connect_bd_intf_net -intf_net v_tc_0_vtiming_out [get_bd_intf_pins v_tc_0/vtiming_out] [get_bd_intf_pins v_axi4s_vid_out_0/vtiming_in]
connect_bd_net -net v_axi4s_vid_out_0_sof_state_out [get_bd_pins v_tc_0/sof_state] [get_bd_pins v_axi4s_vid_out_0/sof_state_out]
connect_bd_net -net v_axi4s_vid_out_0_vtg_ce [get_bd_pins v_tc_0/gen_clken] [get_bd_pins v_axi4s_vid_out_0/vtg_ce]

# axis4 stream to video out
connect_bd_net -net v_axi4s_vid_out_0_vid_active_video [get_bd_pins v_axi4s_vid_out_0/vid_active_video] [get_bd_pins zynq_ultra_ps/dp_live_video_in_de]
connect_bd_net -net v_axi4s_vid_out_0_vid_data [get_bd_pins v_axi4s_vid_out_0/vid_data] [get_bd_pins zynq_ultra_ps/dp_live_video_in_pixel1]
connect_bd_net -net v_axi4s_vid_out_0_vid_hsync [get_bd_pins v_axi4s_vid_out_0/vid_hsync] [get_bd_pins zynq_ultra_ps/dp_live_video_in_hsync]
connect_bd_net -net v_axi4s_vid_out_0_vid_vsync [get_bd_pins v_axi4s_vid_out_0/vid_vsync] [get_bd_pins zynq_ultra_ps/dp_live_video_in_vsync]

# counter_wrapper
create_bd_port -dir O -from 7 -to 0 pmod
connect_bd_net [get_bd_pins counter_wrapper_inst/clk_i]  [get_bd_pins ps_reset_100M/slowest_sync_clk]
connect_bd_net [get_bd_pins counter_wrapper_inst/rst_i]  [get_bd_pins ps_reset_100M/peripheral_reset]
connect_bd_net [get_bd_pins counter_wrapper_inst/pmod_o] [get_bd_ports pmod] 

# Fan control
if {$FAN_CONTROL eq "ttc0_linux"} {
    create_bd_port -dir O -from 0 -to 0 fan_en_b
    connect_bd_net [get_bd_pins /xlslice_fan/Dout] [get_bd_ports fan_en_b]
    connect_bd_net [get_bd_pins $zynq_ultra_ps/emio_ttc0_wave_o] [get_bd_pins xlslice_fan/Din]
} elseif {$FAN_CONTROL eq "counter_fpga"} {
    connect_bd_net [get_bd_pins pwm_inst/clk_i]  [get_bd_pins ps_reset_100M/slowest_sync_clk]
    connect_bd_net [get_bd_pins pwm_inst/rst_i]  [get_bd_pins ps_reset_100M/peripheral_reset]
    create_bd_port -dir O -from 0 -to 0 fan_en_b
    connect_bd_net [get_bd_pins pwm_inst/pwm_o] [get_bd_pins util_vector_logic_0/Op1]
    connect_bd_net [get_bd_ports fan_en_b]      [get_bd_pins util_vector_logic_0/Res]
    connect_bd_net [get_bd_pins xlconstant_0/dout] [get_bd_pins pwm_inst/duty_cycle_in]
} elseif {[lsearch -exact $fan_control_type $FAN_CONTROL] == -1} {
    puts "Error: FAN_CONTROL must be one of {ttc0_linux counter_fpga default}"
    exit 1
}

##############################################################################
# AXI address mapping
##############################################################################

assign_bd_address -offset 0xA0000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps/Data] [get_bd_addr_segs v_tc_0/ctrl/Reg] -force

##############################################################################
# Regenerate layout and validate design
##############################################################################

regenerate_bd_layout
update_compile_order -fileset sources_1
save_bd_design [current_bd_design]

validate_bd_design
save_bd_design [current_bd_design]

##############################################################################
# Make wrapper around bd and set bd_top_wrapper as top
##############################################################################

make_wrapper -files [get_files $PROJECT_NAME.srcs/sources_1/bd/$BD_TOP/$BD_TOP.bd] -top
add_files -norecurse $PROJECT_NAME.gen/sources_1/bd/$BD_TOP/hdl/bd_top_wrapper.v
update_compile_order -fileset sources_1
set_property top bd_top_wrapper [current_fileset]
update_compile_order -fileset sources_1

##############################################################################
# extensible platform
##############################################################################

if {$EXTENSIBLE_PLATFORM} {
    set_property platform.extensible true [current_project]
    set_property PFM.AXI_PORT {M_AXI_HPM0_FPD {memport "M_AXI_GP" sptag "" memory "" is_range "false"} M_AXI_HPM1_FPD {memport "M_AXI_GP" sptag "" memory "" is_range "false"} M_AXI_HPM0_LPD {memport "M_AXI_GP" sptag "" memory "" is_range "false"} S_AXI_HPC0_FPD {memport "S_AXI_HP" sptag "HPC0" memory "" is_range "false"} S_AXI_HPC1_FPD {memport "S_AXI_HP" sptag "HPC1" memory "" is_range "false"} S_AXI_HP0_FPD {memport "S_AXI_HP" sptag "HP0" memory "" is_range "false"} S_AXI_HP1_FPD {memport "S_AXI_HP" sptag "HP1" memory "" is_range "false"} S_AXI_HP2_FPD {memport "S_AXI_HP" sptag "HP2" memory "" is_range "false"} S_AXI_HP3_FPD {memport "S_AXI_HP" sptag "HP3" memory "" is_range "false"}} $zynq_ultra_ps
    # set_property PFM.AXI_PORT {M00_AXI {memport "M_AXI_GP" sptag "" memory "" is_range "true"} M01_AXI {memport "M_AXI_GP" sptag "" memory "" is_range "true"}  M02_AXI {memport "M_AXI_GP" sptag "" memory "" is_range "true"} M03_AXI {memport "M_AXI_GP" sptag "" memory "" is_range "true"} M04_AXI {memport "M_AXI_GP" sptag "" memory "" is_range "true"} M05_AXI {memport "M_AXI_GP" sptag "" memory "" is_range "true"} M06_AXI {memport "M_AXI_GP" sptag "" memory "" is_range "true"} M07_AXI {memport "M_AXI_GP" sptag "" memory "" is_range "true"}} [get_bd_cells /smartconnect_1]
    set_property PFM.CLOCK {pl_clk0 {id "0" is_default "true" proc_sys_reset "/proc_sys_reset" status "fixed" freq_hz "$(PL0_CLK_FREQ_MHZ)"}} $zynq_ultra_ps
    # set_property PFM.IRQ {In0 {is_range "true"} In1 {is_range "true"}} [get_bd_cells /xlconcat_0]
    set_property platform.vendor {vendor} [current_project]
    set_property platform.board_id {lib} [current_project]
    set_property platform.version {1.0} [current_project]
    set_property pfm_name {vendor:lib:$PROJECT_NAME:1.0} [get_files -all $BD_TOP.bd]
}

##############################################################################
# Generate output products
##############################################################################

generate_target all [get_files  $PROJECT_NAME.srcs/sources_1/bd/$BD_TOP/$BD_TOP.bd]
# catch { config_ip_cache -export [get_ips -all bd_top_zynq_ultra_ps_e_0_0] }
# catch { config_ip_cache -export [get_ips -all bd_top_proc_sys_reset_0_0] }
# catch { config_ip_cache -export [get_ips -all bd_top_c_counter_binary_0_0] }
# catch { config_ip_cache -export [get_ips -all bd_top_system_ila_0_1] }
export_ip_user_files -of_objects [get_files $PROJECT_NAME.srcs/sources_1/bd/$BD_TOP/$BD_TOP.bd] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] $PROJECT_NAME.srcs/sources_1/bd/$BD_TOP/$BD_TOP.bd]

close_bd_design [current_bd_design]
