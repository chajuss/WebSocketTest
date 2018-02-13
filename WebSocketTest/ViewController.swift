//
//  ViewController.swift
//  WebSocketTest
//
//  Created by Ori Chajuss on 12/02/2018.
//  Copyright © 2018 Ori Chajuss. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // MARK: - UIElements
    @IBOutlet weak var serverButton: UIButton!
    @IBOutlet weak var clientButton: UIButton!
    @IBOutlet weak var stopButton: UIButton!
    @IBOutlet weak var transmitButton: UIButton!
    
    // MARK: - Members
    private var testServer: TestServer?
    private var testClient: TestClient?
    private var videoEncoder: VideoEncoder?
    
    // MARK: - Video Componants
    private var isTransmitting: Bool = false
    private let videoSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput!
    private var videoDataOutput: AVCaptureVideoDataOutput!
    private var videoDevice: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "com.chajuss.view.sessionQueue", attributes: .concurrent)
    
    //MARK: - RxElements
    private let disposeBag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. We suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    print("User denied camera access")
                }
                self.sessionQueue.resume()
            })
        default: break
            // The user has previously denied access.
        }
        setupServerButtonTapped()
        setupClientButtonTapped()
        setupStopButtonTapped()
        setupTransmitButtonTapped()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    private func configureVideoSession() {
        videoSession.beginConfiguration()
        do {
            var defaultVideoDevice: AVCaptureDevice?
            if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                /*
                 In some cases where users break their phones, the back wide angle camera is not available.
                 In this case, we should default to the front wide angle camera.
                 */
                defaultVideoDevice = frontCameraDevice
            } else {
                if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                    defaultVideoDevice = dualCameraDevice
                } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                    // If the back dual camera is not available, default to the back wide angle camera.
                    defaultVideoDevice = backCameraDevice
                }
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice!)
            videoDevice = defaultVideoDevice
            guard videoSession.canAddInput(videoDeviceInput) == true else {
                videoSession.commitConfiguration()
                return
            }
            videoSession.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
            
            let dataOutput = AVCaptureVideoDataOutput()
            dataOutput.videoSettings = [((kCVPixelBufferPixelFormatTypeKey as NSString) as String): NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange as UInt32)]
            dataOutput.alwaysDiscardsLateVideoFrames = true
            if videoSession.canSetSessionPreset(.hd1920x1080) {
                videoSession.sessionPreset = .hd1920x1080
            }
            
            guard videoSession.canAddOutput(dataOutput) == true else {
                videoSession.commitConfiguration()
                return
            }
            let videoQueue = DispatchQueue(label: "com.chajuss.view.videoQueue", attributes: .concurrent)
            dataOutput.setSampleBufferDelegate(self, queue: videoQueue)
            self.videoDataOutput = dataOutput
            videoSession.addOutput(dataOutput)
            videoSession.commitConfiguration()
            
        } catch {
            videoSession.commitConfiguration()
            print(error)
        }
    }
    
    // MARK: - RxCocoa functions
    private func setupServerButtonTapped() {
        serverButton.rx.tap.subscribe({ [unowned self] _ in
            self.clientButton.isHidden = true
            self.serverButton.isHidden = true
            self.stopButton.isHidden = false
            self.transmitButton.isHidden = false
            self.testServer = TestServer()
            self.videoEncoder = VideoEncoder()
            self.sessionQueue.sync {
                self.configureVideoSession()
                self.videoSession.startRunning()
            }
        }).disposed(by: disposeBag)
    }

    private func setupClientButtonTapped() {
        clientButton.rx.tap.subscribe({ [unowned self] _ in
            self.serverButton.isHidden = true
            self.clientButton.isHidden = true
            self.stopButton.isHidden = false
            self.testClient = TestClient()
        }).disposed(by: disposeBag)
    }
    
    private func setupStopButtonTapped() {
        stopButton.rx.tap.subscribe({ [unowned self] _ in
            self.serverButton.isHidden = false
            self.clientButton.isHidden = false
            self.stopButton.isHidden = true
            self.transmitButton.isHidden = true
            self.testServer?.stopServer()
            self.testClient?.stopClient()
        }).disposed(by: disposeBag)
    }
    
    private func setupTransmitButtonTapped() {
        transmitButton.rx.tap.subscribe({ [unowned self] _ in
            ServerWrapper.shared.setupServer(server: self.testServer!)
            self.isTransmitting = true
        }).disposed(by: disposeBag)
    }
    
    // MARK: - Video capture
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if isTransmitting {
            videoEncoder?.captureVideoOutput(sampleBuffer: sampleBuffer, presentationTimestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer), presentationDuration: CMSampleBufferGetDuration(sampleBuffer))
        }
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("Frame dropped")
    }
}

