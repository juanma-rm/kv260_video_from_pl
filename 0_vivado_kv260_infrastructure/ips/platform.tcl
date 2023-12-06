##############################################################################
# Top block design to wrap ZUS+ block, reset, interrupts, user logic, etc.
# 
# It expects to be sources from within the folder that contains the Vivado project
##############################################################################

##############################################################################
# General parameters
##############################################################################

set PL0_CLK_FREQ_MHZ 100
set PROJECT_NAME kv260_infrastructure
set BD_TOP bd_top
set EXTENSIBLE_PLATFORM false

# Select FAN_CONTROL value among the following options
set fan_control_type {ttc0_linux counter_fpga default}
set FAN_CONTROL "counter_fpga"

##############################################################################
# Main block design based on ZUS+ MPSoC + Reset
##############################################################################

# Create block diagram top
create_bd_design "$BD_TOP"
update_compile_order -fileset sources_1

# Zynq Ultrscale+ MPSoC block (default preset)
set zynq_ultra_ps [ create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.4 zynq_ultra_ps ]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1" }  $zynq_ultra_ps
set_property    CONFIG.PSU__USE__M_AXI_GP0 {0}                                  $zynq_ultra_ps
set_property    CONFIG.PSU__USE__M_AXI_GP1 {0}                                  $zynq_ultra_ps
set_property    CONFIG.PSU__USE__M_AXI_GP2 {0}                                  $zynq_ultra_ps
set_property    CONFIG.PSU__USE__S_AXI_GP0 {0}                                  $zynq_ultra_ps
set_property    CONFIG.PSU__USE__S_AXI_GP2 {0}                                  $zynq_ultra_ps
set_property    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ $PL0_CLK_FREQ_MHZ    $zynq_ultra_ps
set_property    CONFIG.PSU__TTC0__PERIPHERAL__ENABLE {1}                        $zynq_ultra_ps
set_property    CONFIG.PSU__TTC0__WAVEOUT__ENABLE {1}                           $zynq_ultra_ps
set_property    CONFIG.PSU__TTC0__WAVEOUT__IO {EMIO}                            $zynq_ultra_ps

set pl_clk0 [get_bd_pins $zynq_ultra_ps/pl_clk0]
set pl_resetn0 [get_bd_pins $zynq_ultra_ps/pl_resetn0]

# Reset block
set proc_sys_reset [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset ]
connect_bd_net $pl_clk0 [get_bd_pins $proc_sys_reset/slowest_sync_clk]
connect_bd_net $pl_resetn0 [get_bd_pins $proc_sys_reset/ext_reset_in]

set peripheral_reset [get_bd_pins $proc_sys_reset/peripheral_reset]

##############################################################################
# Fan control
##############################################################################

if {[lsearch -exact $fan_control_type $FAN_CONTROL] == -1} {
    puts "Error: FAN_CONTROL must be one of {ttc0_linux counter_fpga default}"
    exit 1
}

if {$FAN_CONTROL eq "ttc0_linux"} {
    
    # Fan control from PS TTC0 EMIO waveout

    # Add slice IP and configure to take bit 2 from a 3-bit wide input
    set xlslice_fan [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_fan ]
    set_property    CONFIG.DIN_TO {2}                       $xlslice_fan
    set_property    CONFIG.DIN_FROM {2}                     $xlslice_fan
    set_property    CONFIG.DIN_WIDTH {3}                    $xlslice_fan
    set_property    CONFIG.DOUT_WIDTH {1}                   $xlslice_fan

    # Connect slice output to fan_en_b output port and slice input to ttc0 emio
    create_bd_port -dir O -from 0 -to 0 fan_en_b
    connect_bd_net [get_bd_pins /xlslice_fan/Dout] [get_bd_ports fan_en_b]
    connect_bd_net [get_bd_pins $zynq_ultra_ps/emio_ttc0_wave_o] [get_bd_pins xlslice_fan/Din]

} elseif {$FAN_CONTROL eq "counter_fpga"} {

    # Fan control from FPGA pwm module

    set pwm [ create_bd_cell -type module -reference pwm pwm_inst ]

    connect_bd_net [get_bd_pins pwm_inst/clk_i]  [get_bd_pins $pl_clk0]
    connect_bd_net [get_bd_pins pwm_inst/rst_i]  [get_bd_pins $peripheral_reset]

    # fan_en_b works with negative logic, for what a not gate is used
    create_bd_port -dir O -from 0 -to 0 fan_en_b
    create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 util_vector_logic_0
    set_property -dict [list CONFIG.C_SIZE {1} CONFIG.C_OPERATION {not} CONFIG.LOGO_FILE {data/sym_notgate.png}] [get_bd_cells util_vector_logic_0]
    connect_bd_net [get_bd_pins pwm_inst/pwm_o] [get_bd_pins util_vector_logic_0/Op1]
    connect_bd_net [get_bd_ports fan_en_b]      [get_bd_pins util_vector_logic_0/Res]

    # duty_cycle_in driven by 7-bit constant set at 20 (duty cycle = 20%)
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_0
    set_property -dict [list CONFIG.CONST_WIDTH {7} CONFIG.CONST_VAL {20}] [get_bd_cells xlconstant_0]
    connect_bd_net [get_bd_pins xlconstant_0/dout] [get_bd_pins pwm_inst/duty_cycle_in]

} elseif {[lsearch -exact $fan_control_type $FAN_CONTROL] == -1} {
    puts "Error: FAN_CONTROL must be one of {ttc0_linux counter_fpga default}"
    exit 1
}

##############################################################################
# counter_wrapper
##############################################################################

set counter_wrapper [ create_bd_cell -type module -reference counter_wrapper counter_wrapper_inst ]

create_bd_port -dir O -from 7 -to 0 pmod
connect_bd_net [get_bd_pins counter_wrapper_inst/clk_i]  [get_bd_pins $pl_clk0]
connect_bd_net [get_bd_pins counter_wrapper_inst/rst_i]  [get_bd_pins $peripheral_reset]
connect_bd_net [get_bd_pins counter_wrapper_inst/pmod_o] [get_bd_ports pmod] 

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
