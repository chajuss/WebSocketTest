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
        let firstByte = data.withUnsafeBytes {(ptr: UnsafePointer<UInt8>) -> UInt8 in return ptr.pointee}
        guard firstByte == 101 else {
            print("Currupted data=\(firstByte) (expected 101)")
            return
        }
    }
    
    
}

class TestClient: NSObject {
    
    private var udpTimer: DispatchSourceTimer?
    private let broadcastPort = 1111 //UDP
    private let broadcastRetransmitTime = 1
    private let websocketStringPrefix = "ws://"
    private let serverPortStringSuffix = ":5000/"
    
    private var webSocket: Starscream.WebSocket!
    private var udpSocket: Socket!
    
    override init() {
        super.init()
        udpSocket = try? Socket.create(family: Socket.ProtocolFamily.inet, type: Socket.SocketType.datagram, proto: Socket.SocketProtocol.udp)
        startTimerClient()
        
    }
    
    deinit {
        stopClient()
    }
    
    func stopClient() {
        print("Stopping Client")
        stopTimerClient()
        if udpSocket != nil {
            udpSocket.close()
            udpSocket = nil
        }
        if webSocket != nil {
            webSocket.disconnect()
            webSocket = nil
        }
    }
    
    private func startTimerClient() {
        let queue = DispatchQueue(label: "com.chajuss.client.timer")
        udpTimer = DispatchSource.makeTimerSource(queue: queue)
        udpTimer!.schedule(deadline: .now(), repeating: .seconds(broadcastRetransmitTime))
        udpTimer!.setEventHandler { [weak self] in
            self?.detectServer()
        }
        udpTimer!.resume()
    }
    
    private func stopTimerClient() {
        udpTimer?.cancel()
        udpTimer = nil
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
            self.stopTimerClient()
            self.connectToServer(serverIP: hostIP)
        }
    }

}
