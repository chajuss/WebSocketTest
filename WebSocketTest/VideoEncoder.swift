//
//  VideoEncoder.swift
//  WebSocketTest
//
//  Created by Ori Chajuss on 13/02/2018.
//  Copyright © 2018 Ori Chajuss. All rights reserved.
//

import Foundation
import VideoToolbox

class VideoEncoder: NSObject {
    private var session: VTCompressionSession?
    
    override init() {
        super.init()
        print("Init Encoder called")
        let ret = VTCompressionSessionCreate(nil, 1920, 1080, kCMVideoCodecType_H264, nil, nil, nil, didEncodeFrameCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self), &session)
        guard ret == noErr else {
            print("VTCompressionSessionCreate Error=\(ret)")
            return
        }
        VTSessionSetProperty(session!, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        VTSessionSetProperty(session!, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        var value: Int32 = 1024 * 1000 * 8
        let avgBitRate = CFNumberCreate(nil, .sInt32Type, &value)
        VTSessionSetProperty(session!, kVTCompressionPropertyKey_AverageBitRate, avgBitRate)
        VTCompressionSessionPrepareToEncodeFrames(session!)
    }
    
    deinit {
        stopSession()
    }
    
    public func stopSession() {
        if session != nil {
            VTCompressionSessionInvalidate(session!)
            session = nil
        }
    }
    
    // MARK: - Encoding Functions
    private var didEncodeFrameCallback: VTCompressionOutputCallback = {(
        outputCallbackRefCon: UnsafeMutableRawPointer?,
        sourceFrameRefCon: UnsafeMutableRawPointer?,
        status: OSStatus,
        infoFlags: VTEncodeInfoFlags,
        sampleBuffer: CMSampleBuffer?) in
        
        guard let sampleBuffer = sampleBuffer else {
            let error = NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
            print("didEncodeFrameCallback: \(error.localizedDescription)")
            return
        }
        guard status == noErr else {
            let error = NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
            print("didEncodeFrameCallback: \(error.localizedDescription)")
            return
        }
        var isKeyFrame = false
        if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false) {
            let dictionary = CFArrayGetValueAtIndex(attachmentsArray, 0)
            if let notSyncPtr = CFDictionaryGetValue(unsafeBitCast(dictionary, to: CFDictionary.self), Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()) {
                let notSync = Unmanaged<NSNumber>.fromOpaque(notSyncPtr).takeUnretainedValue()
                isKeyFrame = !notSync.boolValue
            } else {
                isKeyFrame = true
            }
        }
        var elementaryStream = NSMutableData()
        let naluStart: [UInt8] = [0x00, 0x00, 0x00, 0x01]
        let startCodeLength = naluStart.count
        var status: OSStatus
        if isKeyFrame {
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
            var numParams = Int()
            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription!, 0, nil, nil, &numParams, nil)
            guard status == noErr else {
                let error = NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
                print("CMVideoFormatDescriptionGetH264ParameterSetAtIndex: \(error.localizedDescription)")
                return
            }
            for i in 0..<numParams {
                var parameterSetPointer: UnsafePointer<UInt8>?
                var parameterSetLength: size_t = 0
                status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription!, i, &parameterSetPointer, &parameterSetLength, nil, nil)
                guard status == noErr else {
                    let error = NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
                    print("CMVideoFormatDescriptionGetH264ParameterSetAtIndex: \(error.localizedDescription)")
                    return
                }
                elementaryStream.append(naluStart, length: startCodeLength)
                elementaryStream.append(parameterSetPointer!, length: parameterSetLength)
            }
        }
        let numberOfSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
        var totalLength = Int()
        var dataPointer: UnsafeMutablePointer<Int8>?
        status = CMBlockBufferGetDataPointer(blockBuffer!, 0, nil, &totalLength, &dataPointer)
        guard status == noErr else {
            let error = NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
            print("CMBlockBufferGetDataPointer: \(error.localizedDescription)")
            return
        }
        var bufferOffset = 0
        let AVCCHeaderLength = 4
        var sampleIndex = 0
        var timeInfo = CMSampleTimingInfo()
        while bufferOffset < totalLength - AVCCHeaderLength {
            var NALUnitLength: UInt32 = 0
            memcpy(&NALUnitLength, dataPointer! + bufferOffset, AVCCHeaderLength)
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength)
            elementaryStream.append(naluStart, length: startCodeLength)
            elementaryStream.append(dataPointer! + bufferOffset + AVCCHeaderLength, length: Int(NALUnitLength))
            let bufferSize = (AVCCHeaderLength + Int(NALUnitLength))
            bufferOffset += bufferSize
            status = CMSampleBufferGetSampleTimingInfo(sampleBuffer, sampleIndex, &timeInfo)
            ServerWrapper.shared.sendData(data: elementaryStream as Data)
            elementaryStream = NSMutableData()
            if sampleIndex < numberOfSamples {
                sampleIndex += 1
            }
        }
    }
    
    private func sendData(data: Data) {

    }
    
    public func captureVideoOutput(sampleBuffer: CMSampleBuffer, presentationTimestamp: CMTime, presentationDuration: CMTime) {
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        VTCompressionSessionEncodeFrame(session!, imageBuffer!, presentationTimestamp, kCMTimeInvalid, nil, nil, nil)
        VTCompressionSessionEndPass(session!, nil, nil)
    }
}
