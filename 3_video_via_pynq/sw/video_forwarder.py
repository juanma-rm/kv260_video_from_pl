#####################################################################################
# Import libraries
#####################################################################################

from pynq import Overlay
from pynq.lib.video import *
from pynq import PL
from pynq import allocate
import numpy as np
import time

#####################################################################################
# Load the overlay
#####################################################################################

PL.reset()
overlay = Overlay("video_via_pynq.xsa")
# print(overlay.ip_dict)

#####################################################################################
# Configure VDMA
#####################################################################################

vdma = overlay.axi_vdma_0
vdma.readchannel.mode = VideoMode(1920, 1080, 24)
vdma.readchannel.cacheable_frames = False
vdma.readchannel.start()

#####################################################################################
# Configure DisplayPort
#####################################################################################

displayport = DisplayPort()
displayport.modes
displayport.configure(VideoMode(1920, 1080, 24), PIXEL_RGB)

#####################################################################################
# Get frames and display via DP
#####################################################################################

NB_FRAMES = 1000
for _ in range(NB_FRAMES):

    start_time = time.time()

    frame_dp = displayport.newframe()
    frame_dp[:] = vdma.readchannel.readframe()
    displayport.writeframe(frame_dp)

    end_time = time.time()
    print("Time in ms: " + str((end_time - start_time)*1000) + ", fps = " + str(1/(end_time - start_time)))

#####################################################################################
# Clean
#####################################################################################

vdma.readchannel.stop()