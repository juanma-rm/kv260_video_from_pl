/*************************************************************************************
 * main.c
 *
 * Configures the video components (Video Test Pattern Generator, Video Timing Controller,
 * and DisplayPort Controller (DPPSU)) and runs them.
 * 
 * Makes use of the psu_dpdma example provided by Xilinx to control the DisplayPort controller
 * and based on the xdppsu DisplayPort standalone driver.
 *
 * Usage: select video mode in config.h and run as a standalone application based on
 * a Vivado platform containing all required elements.
 *************************************************************************************/

/*************************************************************************************
 * Includes
 *************************************************************************************/

#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xv_tpg.h"
#include "xvtc.h"
#include "xvidc.h"
#include "xdpdma_video.h"
#include "config.h"

/*************************************************************************************
 * Global data
 *************************************************************************************/

XV_tpg tpg;
XVtc vtc;
XVtc_Config *vtc_config;

/*************************************************************************************
 * Function definitions
 *************************************************************************************/

/**
 * @brief Initialise the video driver components.
 */
void driverInit() {
	XV_tpg_Initialize(&tpg, 0);
	vtc_config = XVtc_LookupConfig(XPAR_VTC_0_DEVICE_ID);
	XVtc_CfgInitialize(&vtc, vtc_config, vtc_config->BaseAddress);
}

/**
 * @brief Configure the Video Timing Controller (VTC) based on the provided video stream parameters.
 */
void configVTC(XVidC_VideoStream *StreamPtr) {

	XVtc_Timing vtc_timing = {0};
	u16 PixelsPerClock = 1;

    // Extract and set horizontal timing parameters
	vtc_timing.HActiveVideo = StreamPtr->Timing.HActive / PixelsPerClock;
	vtc_timing.HFrontPorch = StreamPtr->Timing.HFrontPorch / PixelsPerClock;
	vtc_timing.HSyncWidth = StreamPtr->Timing.HSyncWidth / PixelsPerClock;
	vtc_timing.HBackPorch = StreamPtr->Timing.HBackPorch / PixelsPerClock;
	vtc_timing.HSyncPolarity = StreamPtr->Timing.HSyncPolarity;

    // Extract and set vertical timing parameters
	vtc_timing.VActiveVideo = StreamPtr->Timing.VActive;
	vtc_timing.V0FrontPorch = StreamPtr->Timing.F0PVFrontPorch;
	vtc_timing.V0SyncWidth = StreamPtr->Timing.F0PVSyncWidth;
	vtc_timing.V0BackPorch = StreamPtr->Timing.F0PVBackPorch;
	vtc_timing.VSyncPolarity = StreamPtr->Timing.VSyncPolarity;

    // Set VTC registers and enable it
	XVtc_SetGeneratorTiming(&vtc, &vtc_timing);
	XVtc_Enable(&vtc);
	XVtc_EnableGenerator(&vtc);
	XVtc_RegUpdateEnable(&vtc);
}

/**
 * @brief Configure the Display Processor (DPPSU) subsystem.
 */
int configDPPSU(void) {

	Run_Config RunCfg;
    InitRunConfig(&RunCfg);
    u32 status = InitDpDmaSubsystem(&RunCfg);
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    SetupInterrupts(&RunCfg);

    return XST_SUCCESS;
}

/**
 * @brief
 */
void configTPG(XVidC_VideoStream *StreamPtr) {
    // Disable auto restart to configure the TPG settings
    XV_tpg_DisableAutoRestart(&tpg);
    // Set the height and width of the TPG based on the video stream parameters
    XV_tpg_Set_height(&tpg, StreamPtr->Timing.VActive);
    XV_tpg_Set_width(&tpg, StreamPtr->Timing.HActive);
    // Set the color format to RGB
    XV_tpg_Set_colorFormat(&tpg, XVIDC_CSF_RGB);
    // Set the background pattern to color bars
    XV_tpg_Set_bckgndId(&tpg, XTPG_BKGND_COLOR_BARS);
    // Set overlay ID and other TPG parameters
    XV_tpg_Set_ovrlayId(&tpg, 1);
    XV_tpg_Set_boxSize(&tpg, 100);
    XV_tpg_Set_motionSpeed(&tpg, 10);
    // Enable auto restart to apply the configured settings
    XV_tpg_EnableAutoRestart(&tpg);
    // Start the TPG
    XV_tpg_Start(&tpg);
}

/**
 * @brief Main function for initialising and configuring video processing components.
 *
 * This function initializes the platform, sets video stream and timing parameters, and configures
 * the Test Pattern Generator (TPG), Video Timing Controller (VTC), and other components. Finally,
 * it runs the display processor (DPPSU) and cleans up the platform before exiting.
 *
 * @return Returns 0 upon successful execution.
 */

int main() {

    init_platform();	
	xil_printf("Platform initialised. \n\r");

    // Set video stream and timing parameters
	XVidC_VideoStream VidStream;
    XVidC_VideoTiming const *TimingPtr;
	VidStream.PixPerClk = tpg.Config.PixPerClk;
	VidStream.ColorFormatId = XVIDC_CSF_RGB;
	VidStream.ColorDepth = tpg.Config.MaxDataWidth;
	VidStream.VmId = VIDEO_MODE_CONFIG;
	TimingPtr = XVidC_GetTimingInfo(VidStream.VmId);
	VidStream.Timing = *TimingPtr;
	VidStream.FrameRate = XVidC_GetFrameRate(VidStream.VmId);
    xil_printf("Stream features: \n\r - Video Mode: %s \n\r - Colour format: (%s) \n\r", XVidC_GetVideoModeStr(VidStream.VmId), XVidC_GetColorFormatStr(VidStream.ColorFormatId));

    // Initialise and configure Video components 
	driverInit();
	configTPG(&VidStream);
	configVTC(&VidStream);
	configDPPSU();

	cleanup_platform();
	return 0;
}
