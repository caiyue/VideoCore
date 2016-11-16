/*
 
 Video Core
 Copyright (c) 2014 James G. Hurley
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 
 */
#ifndef __videocore__CameraSource__
#define __videocore__CameraSource__

#include <iostream>
#include <videocore/sources/iOS/CaptureSessionSource.h>
#include <videocore/transforms/IOutput.hpp>
#include <CoreVideo/CoreVideo.h>
#include <glm/glm.hpp>

#import <Foundation/Foundation.h>


namespace videocore { namespace iOS {
    
    /*!
     *  Capture video from the device's cameras.
     */
    class CameraSource : public CaptureSessionSource
    {
    public:
        
        
        /*! Constructor */
        CameraSource();
        
        /*! Destructor */
        ~CameraSource();
        
        
        /*!
         *  Setup camera properties
         *
         *  \param session  Capture session to use
         *  \param fps      Optional parameter to set the output frames per second.
         *  \param useFront Start with the front-facing camera
         *  \param useInterfaceOrientation whether to use interface or device orientation as reference for video capture orientation
         *  \param callbackBlock block to be called after everything is set
         */
        void setup(AVCaptureSession *session, int fps, bool useFront, bool useInterfaceOrientation);
        
        
        /*!
         *  Toggle the camera between front and back-facing cameras.
         */
        void toggleCamera();
        
        /*!
         * If the orientation is locked, we ignore device / interface
         * orientation changes.
         *
         * \return `true` is returned if the orientation is locked
         */
        bool orientationLocked();
        
        /*!
         * Lock the camera orientation so that device / interface
         * orientation changes are ignored.
         *
         *  \param orientationLocked  Bool indicating whether to lock the orientation.
         */
        void setOrientationLocked(bool orientationLocked);
        
        /*!
         *  Attempt to turn the torch mode on or off.
         *
         *  \param torchOn  Bool indicating whether the torch should be on or off.
         *
         *  \return the actual state of the torch.
         */
        bool setTorch(bool torchOn);
        
        /*!
         *  Attempt to set the POI for focus.
         *  (0,0) represents top left, (1,1) represents bottom right.
         *
         *  \return Success. `false` is returned if the device doesn't support a POI.
         */
        bool setFocusPointOfInterest(float x, float y);
        
        bool setContinuousAutofocus(bool wantsContinuous);
        
        bool setExposurePointOfInterest(float x, float y);
        
        bool setContinuousExposure(bool wantsContinuous);
        
        /*!
         *  Returns media type for the source
         */
        NSString *mediaType();
        
        
    public:
        
        /*! Used by Objective-C Device/Interface Orientation Notifications */
        void reorientCamera();
        void bufferCaptured(CMSampleBufferRef sampleBuffer);
        void bufferCaptured(CVPixelBufferRef pixelBufferRef);
        bool isConnectionForCurrentInput(AVCaptureConnection *connection);
        
    protected:
        /*!
         *  Method to create and setup capture session connections from inputs to outputs
         */
        void setupCaptureSessionConnections();
        
        /*!
         * Get a camera with a specified position
         *
         * \param position The position to search for.
         *
         * \return the camera device, if found.
         */
        AVCaptureDevice *cameraWithPosition(int position);
        
        /*!
         * Get a camera device for currently active input.
         */
        AVCaptureDevice *captureDevice();
        
        /*!
         *  Get video orientation for device orientation
         *
         *  \param orientation Device or interface orientation
         *
         *  \return Video orientation
         */
        AVCaptureVideoOrientation videoOrientationForInterfaceOrientation(long orientation);
        
        /*!
         *  Sets up and adds camera capture input for position.
         *
         *  \param position The position of camera.
         *
         *  \return Capture input.
         */
        AVCaptureDeviceInput *setupCaptureInputWithCameraPosition(int position);
        
        /*!
         *  Removes capture outputs and inputs from session
         */
        void removeSessionConnections();
        
        /*!
         * Sets up the camera capture output.
         */
        void setupCaptureOutput();
        
        /*!
         *  Property for capture output delegate
         */
        void setCaptureOutputDelegate(id value);
        
        /*!
         *  Start listening to orientation change notifications
         */
        void startListeningToOrientationChange();
        
        /*!
         *  Stop listening to orientation change notifications
         */
        void stopListeningToOrientationChange();
        
        /*!
         *  Returns capture input for camera.
         *
         *  \param position The position of camera.
         *
         *  \return Capture input.
         */
        AVCaptureDeviceInput *captureInputForCameraPosition(int position);
        
        /*!
         *  Gets current capture device position
         */
        AVCaptureDevicePosition captureDevicePosition();
        
        /*!
         *  Gets frame duration based on fps
         */
        CMTime frameDuration();
        
        glm::mat4 m_matrix;
        struct { float x, y, w, h, vw, vh, a; } m_size, m_targetSize;
        
        int  m_fps;
        bool m_torchOn;
        bool m_useInterfaceOrientation;
        bool m_orientationLocked;
        bool m_isFront;
        
        /*!
         *  Property for input array.
         */
        NSArray *m_inputs;
        NSArray *inputs();
        void setInputs(NSArray *inputs);
    };
    
}
}
#endif /* defined(__videocore__CameraSource__) */
