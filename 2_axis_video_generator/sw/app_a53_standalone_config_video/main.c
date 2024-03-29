/*************************************************************************************
 * main.c
 *
 * Configures the video components (Video Timing Controller and DisplayPort Controller
 * (DPPSU)) and runs them.
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
#include "xvtc.h"
#include "xvidc.h"
#include "xdpdma_video.h"
#include "config.h"

/*************************************************************************************
 * Global data
 *************************************************************************************/

XVtc vtc;
XVtc_Config *vtc_config;

/*************************************************************************************
 * Function definitions
 *************************************************************************************/

/**
 * @brief Initialise the video driver components.
 */
void driverInit() {
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
 * @brief Main function for initialising and configuring video processing components.
 *
 * This function initializes the platform, sets video stream and timing parameters, and configures
 * the Video Timing Controller (VTC), and other components. Finally, it runs the display processor 
 * (DPPSU) and cleans up the platform before exiting.
 *
 * @return Returns 0 upon successful execution.
 */

int main() {

    init_platform();	
	xil_printf("Platform initialised. \n\r");

    // Set video stream and timing parameters
	XVidC_VideoStream VidStream;
    XVidC_VideoTiming const *TimingPtr;
	VidStream.ColorFormatId = XVIDC_CSF_RGB;
	VidStream.VmId = VIDEO_MODE_CONFIG;
	TimingPtr = XVidC_GetTimingInfo(VidStream.VmId);
	VidStream.Timing = *TimingPtr;
	VidStream.FrameRate = XVidC_GetFrameRate(VidStream.VmId);
    xil_printf("Stream features: \n\r - Video Mode: %s \n\r - Colour format: (%s) \n\r", XVidC_GetVideoModeStr(VidStream.VmId), XVidC_GetColorFormatStr(VidStream.ColorFormatId));

    // Initialise and configure Video components 
	driverInit();
	configVTC(&VidStream);
	configDPPSU();

	cleanup_platform();
	return 0;
}
