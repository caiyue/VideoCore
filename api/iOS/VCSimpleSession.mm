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

#import <videocore/api/iOS/VCSimpleSession.h>
#import <videocore/api/iOS/VCPreviewView.h>
#import <videocore/sources/iOS/VCWriter.h>

#include <videocore/rtmp/RTMPSession.h>
#include <videocore/transforms/RTMP/AACPacketizer.h>
#include <videocore/transforms/RTMP/H264Packetizer.h>
#include <videocore/transforms/Split.h>
#include <videocore/transforms/AspectTransform.h>
#include <videocore/transforms/PositionTransform.h>

#ifdef __APPLE__
#   include <videocore/mixers/Apple/AudioMixer.h>
#   include <videocore/transforms/Apple/MP4Multiplexer.h>
#   include <videocore/transforms/Apple/H264Encode.h>
#   include <videocore/sources/Apple/PixelBufferSource.h>
#   ifdef TARGET_OS_IPHONE
#       include <videocore/sources/iOS/CameraSource.h>
#       include <videocore/sources/iOS/MicSource.h>
#       include <videocore/mixers/iOS/GLESVideoMixer.h>
#       include <videocore/transforms/iOS/AACEncode.h>

#   else /* OS X */

#   endif
#else
#   include <videocore/mixers/GenericAudioMixer.h>
#endif

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)


#include <sstream>
#import <AVFoundation/AVFoundation.h>

namespace videocore { namespace simpleApi {

    using PixelBufferCallback = std::function<void(const uint8_t* const data,
                                                   size_t size)> ;

    class PixelBufferOutput : public IOutput
    {
    public:
        PixelBufferOutput(PixelBufferCallback callback)
        : m_callback(callback) {};

        void pushBuffer(const uint8_t* const data,
                        size_t size,
                        IMetadata& metadata)
        {
            m_callback(data, size);
        }

    private:

        PixelBufferCallback m_callback;
    };
}
}

@interface VCSimpleSession()
{

    VCPreviewView* _previewView;

    std::shared_ptr<videocore::simpleApi::PixelBufferOutput> m_pbOutput;
    // 是接收图片的Source
    std::shared_ptr<videocore::Apple::PixelBufferSource>     m_pixelBufferSource;
    std::shared_ptr<videocore::AspectTransform>              m_pbAspect;
    std::shared_ptr<videocore::PositionTransform>            m_pbPosition;
    
    std::shared_ptr<videocore::Split> m_videoSplit;
    std::shared_ptr<videocore::AspectTransform>   m_aspectTransform;
    videocore::AspectTransform::AspectMode m_aspectMode;
    std::shared_ptr<videocore::PositionTransform> m_positionTransform;
    std::shared_ptr<videocore::IAudioMixer> m_audioMixer;
    std::shared_ptr<videocore::IVideoMixer> m_videoMixer;
    std::shared_ptr<videocore::ITransform>  m_h264Encoder;
    std::shared_ptr<videocore::ITransform>  m_aacEncoder;
    std::shared_ptr<videocore::ITransform>  m_h264Packetizer;
    std::shared_ptr<videocore::ITransform>  m_aacPacketizer;

    std::shared_ptr<videocore::Split>       m_aacSplit;
    std::shared_ptr<videocore::Split>       m_h264Split;
    std::shared_ptr<videocore::Apple::MP4Multiplexer> m_muxer;

    std::shared_ptr<videocore::IOutputSession> m_outputSession;


    // properties
    // 将所有的控制都在一个线程中处理以避免多线程引起的不稳定
    dispatch_queue_t _graphManagementQueue;

    CGSize _videoSize;
    // video bitRate, the highest bitrate in adaptive mode
    int    _bitrate;
    // video frame per second
    int    _fps;
    // the highest bitrate in adaptive mode
    int    _bpsCeiling;
    int    _estimatedThroughput;

    BOOL   _useInterfaceOrientation;
    float  _videoZoomFactor;
    int    _audioChannelCount;
    float  _audioSampleRate;
    int    _audioBitRate;
    float  _micGain;

    VCCameraState _cameraState;
    VCAspectMode _aspectMode;
    VCSessionState _rtmpSessionState;
    BOOL   _orientationLocked;
    BOOL   _torch;

    BOOL _useAdaptiveBitrate;
    BOOL _continuousAutofocus;
    BOOL _continuousExposure;
    CGPoint _focusPOI;
    CGPoint _exposurePOI;
    int _maxSendBufferSize;
    VCFilter _filter;
    
}
@property (nonatomic, readwrite)    VCSessionState              rtmpSessionState;
// 文件记录保存位置
@property (nonatomic, copy)         NSString                    *filePath;
// 文件记录器
@property (nonatomic, strong)       VCWriter                    *writer;
//
@property (nonatomic, strong)       AVCaptureSession            *captureSession;
// 建立采集和播放回路
- (void) setupGraph;
// 建立文件记录
- (void) setupWriter;

@end

@implementation VCSimpleSession
@dynamic videoSize;
@dynamic bitrate;
@dynamic fps;
@dynamic useInterfaceOrientation;
@dynamic orientationLocked;
@dynamic torch;
@dynamic cameraState;
@dynamic aspectMode;
@dynamic rtmpSessionState;
@dynamic videoZoomFactor;
@dynamic audioChannelCount;
@dynamic audioSampleRate;
@dynamic micGain;
@dynamic continuousAutofocus;
@dynamic continuousExposure;
@dynamic focusPointOfInterest;
@dynamic exposurePointOfInterest;
@dynamic useAdaptiveBitrate;
@dynamic estimatedThroughput;
@synthesize maxSendBufferSize;

@dynamic previewView;
// -----------------------------------------------------------------------------
//  Properties Methods
// -----------------------------------------------------------------------------
#pragma mark - Properties
- (CGSize) videoSize
{
    return _videoSize;
}
- (void) setVideoSize:(CGSize)videoSize
{
    _videoSize = videoSize;
    if(m_aspectTransform) {
        m_aspectTransform->setBoundingSize(videoSize.width, videoSize.height);
    }
    if(m_positionTransform) {
        m_positionTransform->setSize(videoSize.width * self.videoZoomFactor,
                                     videoSize.height * self.videoZoomFactor);
    }
}
- (int) bitrate
{
    return _bitrate;
}
- (void) setBitrate:(int)bitrate
{
    _bitrate = bitrate;
}
- (int) fps
{
    return _fps;
}
- (void) setFps:(int)fps
{
    _fps = fps;
}
- (BOOL) useInterfaceOrientation
{
    return _useInterfaceOrientation;
}
- (BOOL) orientationLocked
{
    return _orientationLocked;
}
- (void) setOrientationLocked:(BOOL)orientationLocked
{
    if(nullptr == m_extCameraSource) {
        _orientationLocked = orientationLocked;
        if(m_cameraSource) {
            m_cameraSource->setOrientationLocked(orientationLocked);
        }
    }
}
- (BOOL) torch
{
    return _torch;
}
- (void) setTorch:(BOOL)torch
{
    if(nullptr == m_extCameraSource) {
        if(m_cameraSource) {
            _torch = m_cameraSource->setTorch(torch);
        }
    }
}
- (VCCameraState) cameraState
{
    return _cameraState;
}
- (void) setAspectMode:(VCAspectMode)aspectMode
{
    _aspectMode = aspectMode;
    switch (aspectMode) {
        case VCAscpectModeFill:
            m_aspectMode = videocore::AspectTransform::AspectMode::kAspectFill;
            break;
        case VCAspectModeFit:
            m_aspectMode = videocore::AspectTransform::AspectMode::kAspectFit;
            break;
        default:
            break;
    }
}
- (void) setCameraState:(VCCameraState)cameraState
{
    if(nullptr == m_extCameraSource) {
        if(_cameraState != cameraState) {
            _cameraState = cameraState;
            if(m_cameraSource) {
               m_cameraSource->toggleCamera();
            }
        }
    }
}
- (void) setRtmpSessionState:(VCSessionState)rtmpSessionState
{
    _rtmpSessionState = rtmpSessionState;
    if (NSOperationQueue.currentQueue != NSOperationQueue.mainQueue) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // trigger in main thread, avoid autolayout engine exception
            if(self.delegate) {
                [self.delegate connectionStatusChanged:rtmpSessionState];
            }
        });
    } else {
        if (self.delegate) {
            [self.delegate connectionStatusChanged:rtmpSessionState];
        }
    }
}
- (VCSessionState) rtmpSessionState
{
    return _rtmpSessionState;
}
- (float) videoZoomFactor
{
    return _videoZoomFactor;
}
- (void) setVideoZoomFactor:(float)videoZoomFactor
{
    _videoZoomFactor = videoZoomFactor;
    if(m_positionTransform) {
        // We could use AVCaptureConnection's zoom factor, but in reality it's
        // doing the exact same thing as this (in terms of the algorithm used),
        // but it is not clear how CoreVideo accomplishes it.
        // In this case this is just modifying the matrix
        // multiplication that is already happening once per frame.
        m_positionTransform->setSize(self.videoSize.width * videoZoomFactor,
                                     self.videoSize.height * videoZoomFactor);
    }
}
- (void) setAudioChannelCount:(int)channelCount
{
    _audioChannelCount = MAX(1, MIN(channelCount, 2));

    if(m_audioMixer) {
        m_audioMixer->setChannelCount(_audioChannelCount);
    }
}
- (int) audioChannelCount
{
    return _audioChannelCount;
}
- (void) setAudioSampleRate:(float)sampleRate
{

    _audioSampleRate = (sampleRate > 33075 ? 44100 : 22050); // We can only support 44100 / 22050 with AAC + RTMP
    if(m_audioMixer) {
        m_audioMixer->setFrequencyInHz(sampleRate);
    }
}
- (float) audioSampleRate
{
    return _audioSampleRate;
}
- (void) setMicGain:(float)micGain
{
    if(m_audioMixer) {
        if(nullptr == m_extMicSource) {
            m_audioMixer->setSourceGain(m_micSource, micGain);
        }else {
            m_audioMixer->setSourceGain(m_extMicSource, micGain);
        }
        _micGain = micGain;
    }
}
- (float) micGain
{
    return _micGain;
}

- (UIView*) previewView {
    if( nullptr == m_extCameraSource ) {
        return _previewView;
    }
    else {
        return nil;
    }
}

- (void) setContinuousAutofocus:(BOOL)continuousAutofocus
{
    if( nullptr == m_extCameraSource ) {
        _continuousAutofocus = continuousAutofocus;
        if( m_cameraSource ) {
            m_cameraSource->setContinuousAutofocus(continuousAutofocus);
        }
    }
}
- (BOOL) continuousAutofocus {
    return _continuousAutofocus;
}

- (void) setContinuousExposure:(BOOL)continuousExposure
{
    if( nullptr == m_extCameraSource ) {
        _continuousExposure = continuousExposure;
        if(m_cameraSource) {
            m_cameraSource->setContinuousExposure(continuousExposure);
        }
    }
}

- (void) setFocusPointOfInterest:(CGPoint)focusPointOfInterest {
    if( nullptr == m_extCameraSource ) {
        _focusPOI = focusPointOfInterest;
        if(m_cameraSource) {
            m_cameraSource->setFocusPointOfInterest(focusPointOfInterest.x, focusPointOfInterest.y);
        }
    }
}
- (CGPoint) focusPointOfInterest {
    return _focusPOI;
}

- (void) setExposurePointOfInterest:(CGPoint)exposurePointOfInterest
{
    if( nullptr == m_extCameraSource ) {
        _exposurePOI = exposurePointOfInterest;
        if(m_cameraSource) {
            m_cameraSource->setExposurePointOfInterest(exposurePointOfInterest.x, exposurePointOfInterest.y);
        }
    }
}

- (CGPoint) exposurePointOfInterest {
    return _exposurePOI;
}

- (BOOL) useAdaptiveBitrate {
    return _useAdaptiveBitrate;
}

- (void) setUseAdaptiveBitrate:(BOOL)useAdaptiveBitrate {
    _useAdaptiveBitrate = useAdaptiveBitrate;
    _bpsCeiling = _bitrate;
}

- (int) estimatedThroughput {
    return _estimatedThroughput;
}

- (void)setWriter:(VCWriter *)writer {
    if (writer != _writer) {
        [_writer release];
        _writer = [writer retain];
        
        if(nullptr == m_extCameraSource) {
            m_cameraSource->setWriter(writer);
        }
        if(nullptr == m_extMicSource) {
            m_micSource->setWriter(writer);
        }
    }
}
// -----------------------------------------------------------------------------
//  Public Methods
// -----------------------------------------------------------------------------
#pragma mark - Public Methods
// -----------------------------------------------------------------------------

- (instancetype) initWithVideoSize:(CGSize)videoSize
                         frameRate:(int)fps
                           bitrate:(int)bps
{
    if((self = [super init])) {
        [self initInternalWithVideoSize:videoSize
                              frameRate:fps
                                bitrate:bps
                useInterfaceOrientation:NO
                            cameraState:VCCameraStateBack
                             aspectMode:VCAspectModeFit
                              extCamera:nullptr
                                 extMic:nullptr];

    }
    return self;
}

- (instancetype) initWithVideoSize:(CGSize)videoSize
                         frameRate:(int)fps
                           bitrate:(int)bps
           useInterfaceOrientation:(BOOL)useInterfaceOrientation
{
    if (( self = [super init] ))
    {
        [self initInternalWithVideoSize:videoSize
                              frameRate:fps
                                bitrate:bps
                useInterfaceOrientation:useInterfaceOrientation
                            cameraState:VCCameraStateBack
                             aspectMode:VCAspectModeFit
                              extCamera:nullptr
                                 extMic:nullptr];
    }
    return self;
}

- (instancetype) initWithVideoSize:(CGSize)videoSize
                         frameRate:(int)fps
                           bitrate:(int)bps
           useInterfaceOrientation:(BOOL)useInterfaceOrientation
                       cameraState:(VCCameraState) cameraState
{
    if (( self = [super init] ))
    {
        [self initInternalWithVideoSize:videoSize
                              frameRate:fps
                                bitrate:bps
                useInterfaceOrientation:useInterfaceOrientation
                            cameraState:cameraState
                             aspectMode:VCAspectModeFit
                              extCamera:nullptr
                                 extMic:nullptr];
    }
    return self;
}

- (instancetype) initWithVideoSize:(CGSize)videoSize
                         frameRate:(int)fps
                           bitrate:(int)bps
           useInterfaceOrientation:(BOOL)useInterfaceOrientation
                       cameraState:(VCCameraState) cameraState
                        aspectMode:(VCAspectMode)aspectMode
{
    if (( self = [super init] ))
    {
        [self initInternalWithVideoSize:videoSize
                              frameRate:fps
                                bitrate:bps
                useInterfaceOrientation:useInterfaceOrientation
                            cameraState:cameraState
                             aspectMode:aspectMode
                              extCamera:nullptr
                                 extMic:nullptr];
    }
    return self;
}

- (instancetype) initWithVideoSize:(CGSize)videoSize
                 frameRate:(int)fps
                   bitrate:(int)bps
   useInterfaceOrientation:(BOOL)useInterfaceOrientation
               cameraState:(VCCameraState) cameraState
                aspectMode:(VCAspectMode)aspectMode
                 extCamera:(std::shared_ptr<videocore::ISource>)extCamera
                    extMic:(std::shared_ptr<videocore::ISource>)extMic
{
    if (( self = [super init] ))
    {
        [self initInternalWithVideoSize:videoSize
                              frameRate:fps
                                bitrate:bps
                useInterfaceOrientation:useInterfaceOrientation
                            cameraState:cameraState
                             aspectMode:aspectMode
                              extCamera:extCamera
                                 extMic:extMic];
    }
    return self;
}



- (void) initInternalWithVideoSize:(CGSize)videoSize
                         frameRate:(int)fps
                           bitrate:(int)bps
           useInterfaceOrientation:(BOOL)useInterfaceOrientation
                       cameraState:(VCCameraState) cameraState
                        aspectMode:(VCAspectMode)aspectMode
                         extCamera:(std::shared_ptr<videocore::ISource>)extCamera
                            extMic:(std::shared_ptr<videocore::ISource>)extMic
{
    m_extMicSource = extMic;
    m_extCameraSource = extCamera;

    self.bitrate = bps;
    self.videoSize = videoSize;
    self.fps = fps;
    _useInterfaceOrientation = useInterfaceOrientation;
    self.micGain = kDefaultAudioGain;
    self.audioChannelCount = kDefaultAudioChannelCount;
    self.audioSampleRate = kDefaultAudioSampleRate;
    _audioBitRate = kDefaultAudioBitRate;
    self.useAdaptiveBitrate = NO;
    self.aspectMode = aspectMode;

    if( nullptr == m_extCameraSource ) {
        _previewView = [[VCPreviewView alloc] init];
    }
    self.videoZoomFactor = 1.f;

    _cameraState = cameraState;
    // center as focus poi
    _exposurePOI = _focusPOI = CGPointMake(0.5f, 0.5f);
    // continuous auto focus 
    _continuousExposure = _continuousAutofocus = YES;

    _graphManagementQueue = dispatch_queue_create("com.videocore.session.graph", 0);

    __block VCSimpleSession* bSelf = self;

    dispatch_async(_graphManagementQueue, ^{
        [bSelf setupGraph];
    });
}

- (void) dealloc
{
    // [self endRtmpSession];
    [self.captureSession stopRunning];
    self.captureSession = nil;
    
    m_audioMixer.reset();
    m_videoMixer.reset();
    m_videoSplit.reset();
    m_aspectTransform.reset();
    m_positionTransform.reset();
    if(nullptr == m_extMicSource) {
        m_micSource.reset();
    }
    else {
        m_extMicSource.reset();
    }
    
    if( nullptr == m_extCameraSource ) {
        m_cameraSource.reset();
    }
    else {
        m_extCameraSource.reset();
    }
    
    m_pbOutput.reset();
    if(nullptr == m_extCameraSource) {
        [_previewView release];
        _previewView = nil;
    }
    
    dispatch_release(_graphManagementQueue);
    
    [super dealloc];
    
}

- (void) startRtmpSessionWithURL:(NSString *)rtmpUrl
                    andStreamKey:(NSString *)streamKey
{
    [self startRtmpSessionWithURL:rtmpUrl andStreamKey:streamKey filePath:nil];
}

- (void) startRtmpSessionWithURL:(NSString *)rtmpUrl
                    andStreamKey:(NSString *)streamKey
                        filePath:(NSString *)path
{
    __block VCSimpleSession* bSelf = self;
    
    self.filePath = path;
    dispatch_async(_graphManagementQueue, ^{
        [bSelf startSessionInternal:rtmpUrl streamKey:streamKey];
        [bSelf setupWriter];
    });
}

- (void) startSessionInternal: (NSString*) rtmpUrl
                    streamKey: (NSString*) streamKey
{
    std::stringstream uri ;
    uri << (rtmpUrl ? [rtmpUrl UTF8String] : "") << "/" << (streamKey ? [streamKey UTF8String] : "");
    
    m_outputSession.reset(
                          new videocore::RTMPSession ( uri.str(),
                                                      MAX(_maxSendBufferSize, kMaxBufferedDuration * (self.bitrate + self.audioBitRate) / 8),
                                                      [=](videocore::RTMPSession& session,
                                                          ClientState_t state) {
                                                          
                                                          DLog("ClientState: %d\n", state);
                                                          
                                                          switch(state) {
                                                              case kClientStateConnected:
                                                                  self.rtmpSessionState = VCSessionStateStarting;
                                                                  break;
                                                              case kClientStateSessionStarted:
                                                              {
                                                                  __block VCSimpleSession* bSelf = self;
                                                                  dispatch_async(_graphManagementQueue, ^{
                                                                      [bSelf addEncodersAndPacketizers];
                                                                  });
                                                              }
                                                                  self.rtmpSessionState = VCSessionStateStarted;

                                                                  break;
                                                              case kClientStateError:
                                                                  self.rtmpSessionState = VCSessionStateError;
                                                                  break;
                                                              case kClientStateNotConnected:
                                                                  self.rtmpSessionState = VCSessionStateEnded;
                                                                  break;
                                                              case kClientStateBufferOverflow:
                                                              {
                                                                  if (NSOperationQueue.currentQueue != NSOperationQueue.mainQueue) {
                                                                      dispatch_async(dispatch_get_main_queue(), ^{
                                                                          // trigger in main thread, avoid autolayout engine exception
                                                                          if(self.delegate) {
                                                                              [self.delegate connectionStatusChanged:VCSessionStateBufferOverflow];
                                                                          }
                                                                      });
                                                                  } else {
                                                                      if (self.delegate) {
                                                                          [self.delegate connectionStatusChanged:VCSessionStateBufferOverflow];
                                                                      }
                                                                  }
                                                              }
                                                                  break;
                                                              default:
                                                                  break;

                                                          }

                                                      }) );
    VCSimpleSession* bSelf = self;

    _bpsCeiling = _bitrate;

    if ( self.useAdaptiveBitrate ) {
        _bitrate = 500000;
    }

    m_outputSession->setBandwidthCallback([=](float vector, float predicted, int inst)
                                          {

                                              bSelf->_estimatedThroughput = predicted;
                                              auto video = std::dynamic_pointer_cast<videocore::IEncoder>( bSelf->m_h264Encoder );
                                              auto audio = std::dynamic_pointer_cast<videocore::IEncoder>( bSelf->m_aacEncoder );
                                              
                                              if( nil == video || nil == audio ) {
                                                  return;
                                              }
                                              
                                              if ([bSelf.delegate respondsToSelector:@selector(detectedThroughput:)]) {
                                                  [bSelf.delegate detectedThroughput:predicted];
                                              }
                                              if ([bSelf.delegate respondsToSelector:@selector(detectedThroughput:videoRate:)]) {
                                                  [bSelf.delegate detectedThroughput:predicted videoRate:video->bitrate()];
                                              }
                                              
                                              if ([bSelf.delegate respondsToSelector:@selector(detectedThroughput:videoRate:audioRate:insBytesPerSecond:)]) {
                                                  [bSelf.delegate detectedThroughput:predicted videoRate:video->bitrate() audioRate:audio->bitrate()insBytesPerSecond:inst];
                                              }
                                              
                                              
                                              if(video && audio && bSelf.useAdaptiveBitrate) {

                                                  int videoBr = 0;

                                                  if(vector != 0) {

                                                      vector = vector < 0 ? -1 : 1 ;

                                                      videoBr = video->bitrate();

                                                      if (audio) {
                                                          audio->setBitrate(96000);
//                                                          if ( videoBr > 500000 ) {
//                                                              audio->setBitrate(128000);
//                                                          } else if (videoBr <= 500000 && videoBr > 250000) {
//                                                              audio->setBitrate(96000);
//                                                          } else {
//                                                              audio->setBitrate(80000);
//                                                          }
                                                      }


                                                      if(videoBr > 1152000) {
                                                          video->setBitrate(std::min(int((videoBr / 384000 + vector )) * 384000, bSelf->_bpsCeiling) );
                                                          [self.delegate didChangeConnectionQuality:kVCConnectionQualityHigh];
                                                      }
                                                      else if( videoBr > 512000 ) {
                                                          video->setBitrate(std::min(int((videoBr / 128000 + vector )) * 128000, bSelf->_bpsCeiling) );
                                                          [self.delegate didChangeConnectionQuality:kVCConnectionQualityMedium];
                                                      }
                                                      else if( videoBr > 128000 ) {
                                                          video->setBitrate(std::min(int((videoBr / 64000 + vector )) * 64000, bSelf->_bpsCeiling) );
                                                          [self.delegate didChangeConnectionQuality:kVCConnectionQualityLow];
                                                      }
                                                      else {
                                                          video->setBitrate(std::max(std::min(int((videoBr / 32000 + vector )) * 32000, bSelf->_bpsCeiling), kMinVideoBitrate) );
                                                          [self.delegate didChangeConnectionQuality:kVCConnectionQualityLow];
                                                      }
                                                      DLog("\n(%f) AudioBR: %d VideoBR: %d (%f)\n", vector, audio->bitrate(), video->bitrate(), predicted);
                                                      
                                                      videoBr = video->bitrate();
                                                      
                                                      auto video = std::dynamic_pointer_cast<videocore::RTMPSession>( bSelf->m_outputSession );
                                                      
                                                      // /8 - bitrate to byterate conversion
                                                      video->setMaxSendBufferSize(kMaxBufferedDuration * videoBr / 8);
                                                      
                                                  } /* if(vector != 0) */

                                              } /* if(video && audio && m_adaptiveBREnabled) */


                                          });

    videocore::RTMPSessionParameters_t sp ( 0. );

    sp.setData(self.videoSize.width,
               self.videoSize.height,
               1. / static_cast<double>(self.fps),
               self.bitrate,
               self.audioSampleRate,
               (self.audioChannelCount == 2),
               self.audioBitRate);

    m_outputSession->setSessionParameters(sp);
}

- (void) pauseRtmpSession {
    dispatch_async(_graphManagementQueue, ^{
        if( nullptr != m_h264Packetizer ) {
            m_h264Packetizer.reset();
        }
        if( nullptr != m_aacPacketizer ) {
            m_aacPacketizer.reset();
        }
        if( nullptr != m_aacPacketizer ) {
            m_videoSplit->removeOutput(m_h264Encoder);
        }
        if( nullptr != m_h264Encoder ) {
            m_h264Encoder.reset();
        }
        if( nullptr != m_aacEncoder ) {
            m_aacEncoder.reset();
        }
        if( nullptr != m_outputSession ) {
            auto video = std::dynamic_pointer_cast<videocore::RTMPSession>(m_outputSession);
            if( nil == video ) {
                video->disconnectServer();
            }
            m_outputSession.reset();
        }
    });
    
    _bitrate = _bpsCeiling;
    if(self.writer) {
        self.writer.paused = YES;
    }
    self.rtmpSessionState = VCSessionStatePaused;
}

- (void) continueRtmpSessionWithURL:(NSString *)rtmpUrl
                       andStreamKey:(NSString *)streamKey
{
    [self startRtmpSessionWithURL:rtmpUrl andStreamKey:streamKey];
    if(self.writer) {
        self.writer.paused = NO;
    }
}

- (void) endRtmpSession {
    [self endRtmpSessionWithCompletionHandler:nil];
}

- (void) endRtmpSessionWithCompletionHandler:(void(^)(void))handler {
    
    if(self.writer) {
        [self.writer finishWritingWithCompletionHandler:^{
            self.filePath = nil;
            self.writer = nil;
            if (handler) {
                handler();
            }
        }];
    }
    
    dispatch_async(_graphManagementQueue, ^{
        if( nullptr != m_h264Packetizer ) {
            m_h264Packetizer.reset();
        }
        if( nullptr != m_aacPacketizer ) {
            m_aacPacketizer.reset();
        }
        if( nullptr != m_aacPacketizer ) {
            m_videoSplit->removeOutput(m_h264Encoder);
        }
        if( nullptr != m_h264Encoder ) {
            m_h264Encoder.reset();
        }
        if( nullptr != m_aacEncoder ) {
            m_aacEncoder.reset();
        }
        if( nullptr != m_outputSession ) {
            m_outputSession.reset();
        }
    });
    
    _bitrate = _bpsCeiling;
    
    self.rtmpSessionState = VCSessionStateEnded;
}

//Set property filter for the new enum + set dynamically the sourceFilter for the video mixer
- (void)setFilter:(VCFilter)filterToChange {
        NSString *filterName = @"com.videocore.filters.bgra";
        
        switch (filterToChange) {
            case VCFilterNormal:
                filterName = @"com.videocore.filters.bgra";
                break;
            case VCFilterGray:
                filterName = @"com.videocore.filters.grayscale";
                break;
            case VCFilterInvertColors:
                filterName = @"com.videocore.filters.invertColors";
                break;
            case VCFilterSepia:
                filterName = @"com.videocore.filters.sepia";
                break;
            case VCFilterFisheye:
                filterName = @"com.videocore.filters.fisheye";
                break;
            case VCFilterGlow:
                filterName = @"com.videocore.filters.glow";
                break;
            default:
                break;
        }
        
        _filter = filterToChange;
        NSLog(@"FILTER IS : [%d]", (int)_filter);
        std::string convertString([filterName UTF8String]);
    
        if( nullptr == m_extCameraSource ) {
            m_videoMixer->setSourceFilter(m_cameraSource, dynamic_cast<videocore::IVideoFilter*>(m_videoMixer->filterFactory().filter(convertString))); // default is com.videocore.filters.bgra
        }
        else {
            m_videoMixer->setSourceFilter(m_extCameraSource, dynamic_cast<videocore::IVideoFilter*>(m_videoMixer->filterFactory().filter(convertString))); // default is com.videocore.filters.bgra
        }
}

// -----------------------------------------------------------------------------
//  Private Methods
// -----------------------------------------------------------------------------
#pragma mark - Private Methods


- (void) setupWriter {
    if (nil == self.filePath) {
        return;
    }
    
    id compressionSettings = @{
                               AVVideoAverageBitRateKey: @(self.bitrate),
                               AVVideoMaxKeyFrameIntervalKey: @(2 * self.fps),
                               AVVideoProfileLevelKey: AVVideoProfileLevelH264Main41,
                               AVVideoAllowFrameReorderingKey: @(NO),
                               AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC
                               };
    
    CGSize videoSize = self.videoSize;
    
    id videoSettings = @{AVVideoCodecKey: AVVideoCodecH264,
                         AVVideoWidthKey: @(videoSize.width),
                         AVVideoHeightKey: @(videoSize.height),
                         AVVideoCompressionPropertiesKey: compressionSettings,
                         };

    
    id audioSettings = @{AVFormatIDKey: @(kAudioFormatMPEG4AAC),
                         AVSampleRateKey: @(self.audioSampleRate),
                         AVNumberOfChannelsKey: @(self.audioChannelCount),
                         AVEncoderBitRateKey: @(_audioBitRate)
                         };
    
    VCWriter *writer = [VCWriter writerWithFilePath:self.filePath
                                      videoSettings:videoSettings
                                      audioSettings:audioSettings];
    
    self.writer = writer;
    
    [writer startWriting];
}

- (void) setupGraph {
    //
    if(nullptr == m_extCameraSource || nullptr == m_extMicSource ) {
        AVCaptureSession *session = [[[AVCaptureSession alloc] init] autorelease];
        self.captureSession = session;
    }
    
    // 1.0/25 = 40ms
    const double frameDuration = 1. / static_cast<double>(self.fps);
    
    {
        // aac use 1024 samples in one packet
        const double aacPacketTime = 1024. / self.audioSampleRate;

        // use 16bit pcm
        m_audioMixer = std::make_shared<videocore::Apple::AudioMixer>(self.audioChannelCount,
                                                                      self.audioSampleRate,
                                                                      8 * kDefaultAudioBytesPerChannel,
                                                                      aacPacketTime);


        // The H.264 Encoder introduces about 2 frames of latency, so we will set the minimum audio buffer duration to 2 frames.
        m_audioMixer->setMinimumBufferDuration(frameDuration*2);
    }
#ifdef __APPLE__
#ifdef TARGET_OS_IPHONE


    {
        // Add video mixer
        m_videoMixer = std::make_shared<videocore::iOS::GLESVideoMixer>(self.videoSize.width,
                                                                        self.videoSize.height,
                                                                        frameDuration);

    }

    {
        auto videoSplit = std::make_shared<videocore::Split>();

        m_videoSplit = videoSplit;
        VCPreviewView* preview = nil;
        
        if(nullptr == m_extCameraSource) {
            preview = (VCPreviewView*)self.previewView;
        }
        m_pbOutput = std::make_shared<videocore::simpleApi::PixelBufferOutput>([=](const void* const data, size_t size){
            
            if(nullptr == m_extCameraSource) {
                CVPixelBufferRef ref = (CVPixelBufferRef)data;
                [preview drawFrame:ref];
            }
            if(self.rtmpSessionState == VCSessionStateNone) {
                self.rtmpSessionState = VCSessionStatePreviewStarted;
            }
        });

        videoSplit->setOutput(m_pbOutput);

        m_videoMixer->setOutput(videoSplit);

    }

#else
#endif // TARGET_OS_IPHONE
#endif // __APPLE__

    // Create sources
    {
        // Add camera source
        if(nullptr == m_extCameraSource ) {
            m_cameraSource = std::make_shared<videocore::iOS::CameraSource>();
        }
        auto aspectTransform = std::make_shared<videocore::AspectTransform>(self.videoSize.width,self.videoSize.height,m_aspectMode);

        auto positionTransform = std::make_shared<videocore::PositionTransform>(self.videoSize.width/2, self.videoSize.height/2,
                                                                                self.videoSize.width * self.videoZoomFactor, self.videoSize.height * self.videoZoomFactor,
                                                                                self.videoSize.width, self.videoSize.height
                                                                                );

        if(nullptr == m_extCameraSource) {
            m_cameraSource->setOrientationLocked(self.orientationLocked);
            m_cameraSource->setup(self.captureSession, self.fps, (self.cameraState == VCCameraStateFront), self.useInterfaceOrientation);
            m_cameraSource->setContinuousAutofocus(true);
            m_cameraSource->setContinuousExposure(true);
        }
        
        if(nullptr == m_extCameraSource) {
            m_cameraSource->setOutput(aspectTransform);
            m_videoMixer->setSourceFilter(m_cameraSource, dynamic_cast<videocore::IVideoFilter*>(m_videoMixer->filterFactory().filter("com.videocore.filters.bgra")));
        }
        else {
            m_extCameraSource->setOutput(aspectTransform);
            m_videoMixer->setSourceFilter(m_extCameraSource, dynamic_cast<videocore::IVideoFilter*>(m_videoMixer->filterFactory().filter("com.videocore.filters.bgra")));
        }
        
        _filter = VCFilterNormal;
        aspectTransform->setOutput(positionTransform);
        positionTransform->setOutput(m_videoMixer);
        m_aspectTransform = aspectTransform;
        m_positionTransform = positionTransform;
        
        // Inform delegate that camera source has been added
        if ([_delegate respondsToSelector:@selector(didAddCameraSource:)]) {
            [_delegate didAddCameraSource:self];
        }
    }
    {
        // Add mic source
        if(nullptr == m_extMicSource) {
            m_micSource = std::make_shared<videocore::iOS::MicSource>();
            m_micSource->setup(self.captureSession);
            m_micSource->setOutput(m_audioMixer);
        }
        else {
            m_extMicSource->setOutput(m_audioMixer);
        }

        const auto epoch = std::chrono::steady_clock::now();

        m_audioMixer->setEpoch(epoch);
        m_videoMixer->setEpoch(epoch);

        m_audioMixer->start();
        m_videoMixer->start();
    }
    
    if(nullptr == m_extCameraSource || nullptr == m_extMicSource ) {
        [self.captureSession startRunning];
    }
}
- (void) addEncodersAndPacketizers
{
    int ctsOffset = 2000 / self.fps; // 2 * frame duration
    {
        // Add encoders

        m_aacEncoder = std::make_shared<videocore::iOS::AACEncode>(self.audioSampleRate, self.audioChannelCount, _audioBitRate);
        if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"8.0")) {
            // If >= iOS 8.0 use the VideoToolbox encoder that does not write to disk.
            m_h264Encoder = std::make_shared<videocore::Apple::H264Encode>(self.videoSize.width,
                                                                           self.videoSize.height,
                                                                           self.fps,
                                                                           self.bitrate,
                                                                           true,
                                                                           ctsOffset);
        } else {
            m_h264Encoder =std::make_shared<videocore::Apple::H264Encode>(self.videoSize.width,
                                                                        self.videoSize.height,
                                                                        self.fps,
                                                                        self.bitrate);
        }
        m_audioMixer->setOutput(m_aacEncoder);
        m_videoSplit->setOutput(m_h264Encoder);

    }
    {
        m_aacSplit = std::make_shared<videocore::Split>();
        m_h264Split = std::make_shared<videocore::Split>();
        m_aacEncoder->setOutput(m_aacSplit);
        m_h264Encoder->setOutput(m_h264Split);

    }
    {
        m_h264Packetizer = std::make_shared<videocore::rtmp::H264Packetizer>(ctsOffset);
        m_aacPacketizer = std::make_shared<videocore::rtmp::AACPacketizer>(self.audioSampleRate, self.audioChannelCount, ctsOffset);

        m_h264Split->setOutput(m_h264Packetizer);
        m_aacSplit->setOutput(m_aacPacketizer);

    }
    {
        /*m_muxer = std::make_shared<videocore::Apple::MP4Multiplexer>();
         videocore::Apple::MP4SessionParameters_t parms(0.) ;
         std::string file = [[[self applicationDocumentsDirectory] stringByAppendingString:@"/output.mp4"] UTF8String];
         parms.setData(file, self.fps, self.videoSize.width, self.videoSize.height);
         m_muxer->setSessionParameters(parms);
         m_aacSplit->setOutput(m_muxer);
         m_h264Split->setOutput(m_muxer);*/
    }


    m_h264Packetizer->setOutput(m_outputSession);
    m_aacPacketizer->setOutput(m_outputSession);

    
}
- (void) addPixelBufferSource: (UIImage*) image
                     withRect:(CGRect)rect {
    CGImageRef ref = [image CGImage];
    
    m_pixelBufferSource = std::make_shared<videocore::Apple::PixelBufferSource>(CGImageGetWidth(ref),
                                                                                CGImageGetHeight(ref),
                                                                                'BGRA');
    
    NSUInteger width = CGImageGetWidth(ref);
    NSUInteger height = CGImageGetHeight(ref);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *rawData = (unsigned char*) calloc(height * width * 4, sizeof(unsigned char));
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                                                 bitsPerComponent, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(colorSpace);
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), ref);
    CGContextRelease(context);
    
    m_pbAspect = std::make_shared<videocore::AspectTransform>(rect.size.width,rect.size.height,videocore::AspectTransform::kAspectFit);
    
    m_pbPosition = std::make_shared<videocore::PositionTransform>(rect.origin.x, rect.origin.y,
                                                                  rect.size.width, rect.size.height,
                                                                  self.videoSize.width, self.videoSize.height
                                                                            );
    m_pixelBufferSource->setOutput(m_pbAspect);
    m_pbAspect->setOutput(m_pbPosition);
    m_pbPosition->setOutput(m_videoMixer);
    m_videoMixer->registerSource(m_pixelBufferSource);
    m_pixelBufferSource->pushPixelBuffer(rawData, width * height * 4);
    
    free(rawData);
    
}
- (NSString *) applicationDocumentsDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}
@end
