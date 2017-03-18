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
#include "MicSource.h"
#include <dlfcn.h>
#include <videocore/mixers/IAudioMixer.hpp>
#import <videocore/sources/iOS/Categories/AVCaptureSession+VCExtensions.h>
#import <videocore/sources/iOS/Categories/AVCaptureDevice+VCExtensions.h>
#import <Foundation/Foundation.h>

@interface sbAudioCallback: NSObject<AVCaptureAudioDataOutputSampleBufferDelegate> {
    std::weak_ptr<videocore::iOS::MicSource> m_source;
}

- (void) setSource:(std::weak_ptr<videocore::iOS::MicSource>) source;

@end

@implementation sbAudioCallback

- (void)setSource:(std::weak_ptr<videocore::iOS::MicSource>)source {
    m_source = source;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    auto source = m_source.lock();
    if (source) {
        source->bufferCaptured(sampleBuffer);
    }
}

@end



namespace videocore { namespace iOS {

    MicSource::MicSource()
    :
    m_audioBufferListData(nil)
    {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionMixWithOthers error:nil];
        [session setActive:YES error:nil];
//        [captureSession() configureWithBlock:^(AVCaptureSession *session) {
//            session.usesApplicationAudioSession = YES;
//        }];
        
        setAudioBufferListData([NSMutableData dataWithLength:sizeof(AudioBufferList)]);
    }
    
    MicSource::~MicSource() {
        setAudioBufferListData(nil);
    }
    
    void MicSource::setup(AVCaptureSession *session) {    
        CaptureSessionSource::setup(session);
        
        [captureSession() startRunning];
    }
    
    void MicSource::setupCaptureSessionConnections() {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:mediaType()];
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:NULL];
        addCaptureInput(input);
        setCaptureInput(input);

        AVCaptureSession *session = captureSession();
        AVCaptureAudioDataOutput *output = [[[AVCaptureAudioDataOutput alloc] init] autorelease];
        [session configureWithBlock:^(AVCaptureSession *session) {
            if ([session canAddOutput:output]) {
                [session addOutput:output];
            }
        }];
        
        setCaptureOutput(output);
        
        sbAudioCallback *delegate = [[[sbAudioCallback alloc] init] autorelease];
        setCaptureOutputDelegate(delegate);
    }
    
    NSString *MicSource::mediaType() {
        return AVMediaTypeAudio;
    }
    
    void MicSource::bufferCaptured(CMSampleBufferRef sampleBuffer) {
        [writer() encodeAudioBuffer:sampleBuffer];
        
        
        AudioStreamBasicDescription inputFormat = *(CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer)));
        
        auto output = m_output.lock();
        if(output) {
            videocore::AudioBufferMetadata md (0.);

            NSMutableData *data = audioBufferListData();
            
            size_t bufferSize = 0;
            CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, &bufferSize, NULL, 0, NULL, NULL, 0, NULL);
            if (bufferSize > data.length) {
                data.length = bufferSize;
            }
            
            AudioBufferList *bufferList = (AudioBufferList *)data.mutableBytes;
            CMBlockBufferRef blockBuffer = NULL;
            CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                                                                    sampleBuffer,
                                                                    NULL,
                                                                    bufferList,
                                                                    bufferSize,
                                                                    NULL,
                                                                    NULL,
                                                                    kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                                                                    &blockBuffer
                                                                    );
            
            
            AudioBuffer *buffer = bufferList->mBuffers;
            const size_t sampleSize = 2;
            size_t dataSize = buffer->mDataByteSize;
            
            md.setData(inputFormat.mSampleRate,
                       inputFormat.mBitsPerChannel,
                       inputFormat.mChannelsPerFrame,
                       kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                       inputFormat.mBytesPerFrame,
                       dataSize / inputFormat.mBytesPerFrame,
                       false,
                       false,
                       shared_from_this());
            
            
            output->pushBuffer((uint8_t *)buffer->mData, dataSize, md);
            
            CFRelease(blockBuffer);
        }
    }
    
    void MicSource::setAudioBufferListData(NSMutableData *data) {
        CaptureSessionSource::setValueForField(&m_audioBufferListData, data);
    }
    
    NSMutableData *MicSource::audioBufferListData() {
        return m_audioBufferListData;
    }

    void MicSource::setCaptureOutputDelegate(id value) {
        if (value != m_captureOutputDelegate) {
            [m_captureOutputDelegate setSource:std::weak_ptr<MicSource>()];
            
            CaptureSessionSource::setCaptureOutputDelegate(value);
            
            [value setSource:std::static_pointer_cast<MicSource>(shared_from_this())];
            
            [captureOutput() setSampleBufferDelegate:value queue:sharedDispatchQueue()];
        }
    }

    void MicSource::setOutput(std::shared_ptr<IOutput> output) {
        CaptureSessionSource::setOutput(output);
        
        auto mixer = std::dynamic_pointer_cast<IAudioMixer>(output);
        mixer->registerSource(shared_from_this());
    }
}
}
