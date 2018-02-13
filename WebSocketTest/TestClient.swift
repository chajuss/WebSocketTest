//
//  TestClient.swift
//  WebSocketTest
//
//  Created by Ori Chajuss on 12/02/2018.
//  Copyright © 2018 Ori Chajuss. All rights reserved.
//

import Foundation
import Starscream
import Socket // BlueSocket

// MARK: - WebSocketDelegate
extension TestClient: WebSocketDelegate {
    func websocketDidConnect(socket: WebSocketClient) {
        print("websocket is connected to server")
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        print("websocket is disconnected from server with error=\(String(describing: error?.localizedDescription))")
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        // Not implemented
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        print("got some data from websocket")
        parseData(data: data)
        respondToServer(data: data)
        
    }
}

class TestClient: NSObject {
    
    private var listenerTimer: DispatchSourceTimer?
    private let broadcastPort = 1111 //UDP
    private let broadcastRetransmitTime = 1
    private let websocketStringPrefix = "ws://"
    private let serverPortStringSuffix = ":5000/"
    
    private var webSocket: Starscream.WebSocket!
    private var udpSocket: Socket!
    
    override init() {
        super.init()
        udpSocket = try? Socket.create(family: Socket.ProtocolFamily.inet, type: Socket.SocketType.datagram, proto: Socket.SocketProtocol.udp)
        startClientListenerTimer()
        
    }
    
    deinit {
        stopClient()
    }
    
    func stopClient() {
        print("Stopping Client")
        stopClientListenerTimer()
        if udpSocket != nil {
            udpSocket.close()
            udpSocket = nil
        }
        if webSocket != nil {
            webSocket.disconnect()
            webSocket = nil
        }
    }
    
    private func parseData(data: Data) {
        let firstByte = data.withUnsafeBytes {(ptr: UnsafePointer<UInt8>) -> UInt8 in return ptr.pointee}
        guard firstByte == 101 else {
            print("Currupted data=\(firstByte) (expected 101)")
            return
        }
        var currData = data.advanced(by: MemoryLayout<UInt8>.size)
        let byte0 = currData.withUnsafeBytes {(ptr: UnsafePointer<UInt8>) -> UInt8 in return ptr.pointee}
        currData = currData.advanced(by: MemoryLayout<UInt8>.size)
        guard byte0 == 0 else {
            print("Currupted data=\(firstByte) (expected 0)")
            return
        }
        
        let short = currData.withUnsafeBytes {(ptr: UnsafePointer<Int16>) -> Int16 in return ptr.pointee.bigEndian}
        currData = currData.advanced(by: MemoryLayout<Int16>.size)
        guard short == 255 else {
            print("Currupted data=\(firstByte) (expected 255)")
            return
        }
        
        let byte1 = currData.withUnsafeBytes {(ptr: UnsafePointer<UInt8>) -> UInt8 in return ptr.pointee}
        currData = currData.advanced(by: MemoryLayout<UInt8>.size)
        guard byte1 == 1 else {
            print("Currupted data=\(firstByte) (expected 1)")
            return
        }
        
        let byte2 = currData.withUnsafeBytes {(ptr: UnsafePointer<UInt8>) -> UInt8 in return ptr.pointee}
        currData = currData.advanced(by: MemoryLayout<UInt8>.size)
        guard byte2 == 0 else {
            print("Currupted data=\(firstByte) (expected 0)")
            return
        }
        
        let int = currData.withUnsafeBytes {(ptr: UnsafePointer<Int32>) -> Int32 in return ptr.pointee.bigEndian}
        guard int == 300 else {
            print("Currupted data=\(firstByte) (expected 300)")
            return
        }
    }
    
    private func respondToServer(data: Data) {
        webSocket.write(data: data)
    }
    
    private func startClientListenerTimer() {
        let queue = DispatchQueue(label: "com.chajuss.client.timer")
        listenerTimer = DispatchSource.makeTimerSource(queue: queue)
        listenerTimer!.schedule(deadline: .now(), repeating: .seconds(broadcastRetransmitTime))
        listenerTimer!.setEventHandler { [weak self] in
            self?.detectServer()
        }
        listenerTimer!.resume()
    }
    
    private func stopClientListenerTimer() {
        listenerTimer?.cancel()
        listenerTimer = nil
    }
    
    private func connectToServer(serverIP: String) {
        DispatchQueue.global(qos: .utility).async {
            let connectionString = self.websocketStringPrefix.appending(serverIP).appending(self.serverPortStringSuffix)
            guard let url = URL(string: connectionString) else {
                print("Failed to parse server URL")
                return
            }
            if self.webSocket == nil {
                self.webSocket = WebSocket(url: url)
            }
            self.webSocket.delegate = self
            self.webSocket.connect()
        }
    }
    
    private func detectServer() {
        var data = Data()
        var address: Socket.Address
        do {
            print("listen on UDP socket")
            let response = try self.udpSocket.listen(forMessage: &data, on: broadcastPort)

            guard let responseAddress = response.address else {
                return
            }
            address = responseAddress
        } catch let error {
            print("Got UDP error: \(error.localizedDescription)")
            return
        }
        guard let hostName = Socket.hostnameAndPort(from: address) else {
            return
        }
        let hostIP = hostName.hostname
        print("got UDP code from \(hostIP)")
        
        DispatchQueue.main.async {
            self.stopClientListenerTimer()
            self.connectToServer(serverIP: hostIP)
        }
    }

}
