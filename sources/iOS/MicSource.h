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
#ifndef __videocore__MicSource__
#define __videocore__MicSource__

#include <iostream>
#import <CoreAudio/CoreAudioTypes.h>
#import <AudioToolbox/AudioToolbox.h>
#include <videocore/sources/ISource.hpp>
#include <videocore/transforms/IOutput.hpp>
#include <videocore/sources/iOS/CaptureSessionSource.h>

#import <Foundation/Foundation.h>

@class InterruptionHandler;

namespace videocore { namespace iOS {

    /*!
     *  Capture audio from the device's microphone.
     *
     */

    class MicSource : public CaptureSessionSource
    {
    public:

        /*!
         *  Constructor.
         *
         *  \param audioSampleRate the sample rate in Hz to capture audio at.  Best results if this matches the mixer's sampling rate.
         *  \param excludeAudioUnit An optional lambda method that is called when the source generates its Audio Unit.
         *                          The parameter of this method will be a reference to its Audio Unit.  This is useful for
         *                          applications that may be capturing Audio Unit data and do not wish to capture this source.
         *
         */
        MicSource();

        /*! Destructor */
        ~MicSource();


    public:
        /*!
         *  Setup microphone properties
         *
         *  \param session
         */
        void setup(AVCaptureSession *session);

        /*! ISource::setOutput */
        void setOutput(std::shared_ptr<IOutput> output);
        
        void bufferCaptured(CMSampleBufferRef sampleBuffer);

    protected:
        /*!
         *  Returns media type for the source
         */
        NSString *mediaType();
        
        /*!
         *  Method to create and setup capture session connections from inputs to outputs
         */
        void setupCaptureSessionConnections();
        
        /*!
         *  Property for capture output delegate
         */
        void setCaptureOutputDelegate(id value);
        
    private:
        /*!
         *  Property for capture output delegate
         */
        NSMutableData *m_audioBufferListData;
        void setAudioBufferListData(NSMutableData *data);
        NSMutableData *audioBufferListData();
    };

}
}

#endif /* defined(__videocore__MicSource__) */
