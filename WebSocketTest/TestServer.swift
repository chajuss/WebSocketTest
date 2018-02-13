//
//  Server.swift
//  WebSocketTest
//
//  Created by Ori Chajuss on 12/02/2018.
//  Copyright © 2018 Ori Chajuss. All rights reserved.
//

import Foundation
import Telegraph


// MARK: - ServerWebSocketDelegate
extension TestServer: ServerWebSocketDelegate {
    func server(_ server: Server, webSocketDidConnect webSocket: WebSocket, handshake: HTTPRequest) {
        print("WebSocket connected to Server")
        websocketMap[webSocket as! WebSocketConnection] = webSocket
    }
    
    func server(_ server: Server, webSocketDidDisconnect webSocket: WebSocket, error: Error?) {
        print("WebSocket disconnected from Server")
        _ = websocketMap.removeValue(forKey: webSocket as! WebSocketConnection)
    }
    
    func server(_ server: Server, webSocket: WebSocket, didReceiveMessage message: WebSocketMessage) {
        print("WebSocket receivea message")
    }
    
    func server(_ server: Server, webSocket: WebSocket, didSendMessage message: WebSocketMessage) {
        // Not Implemented
    }
}

class TestServer: NSObject {
    //MARK: - TestServer Members
    private let serverPort: UInt = 5000
    private var server: Server!
    
    private var socketDescriptor: Int32 = -1
    private let broadcastPort: UInt16 = 1111 //UDP
    private var broadcastTimer: DispatchSourceTimer?
    private let broadcastRetransmitTime = 1
    
    private var transmitTimer: DispatchSourceTimer?
    private let retransmitTime = 30
    
    private var websocketMap: [Telegraph.WebSocketConnection: Telegraph.WebSocket]!
    
    private let socketQueue = DispatchQueue(label: "com.chajuss.server.socket")

    // MARK: - TestServer Functions
    override init() {
        super.init()
        websocketMap = [Telegraph.WebSocketConnection: Telegraph.WebSocket]()
        server = Server()
        server.webSocketDelegate = self
        print("Starting WebSocketServer with pingInterval=\(server.webSocketConfig.pingInterval) readTimeout=\(server.webSocketConfig.readTimeout) writeHeaderTimeout=\(server.webSocketConfig.writeHeaderTimeout) writePayloadTimeout=\(server.webSocketConfig.writePayloadTimeout)")
        try? server.start(onPort: UInt16(serverPort))
        guard bindBroadcastSocket() != -1 else {
            print("failed to bind broadcast socket")
            startServerBroadcastTimer()
            return
        }
        startServerBroadcastTimer()
    }
    
    deinit {
        stopServer()
    }
    
    public func stopServer() {
        print("Stopping server")
//        stopServerTransmitTimer()
        stopServerBroadcastTimer()
        if server != nil {
            server.stop()
            server = nil
        }
        if socketDescriptor != -1 {
            close(socketDescriptor)
            socketDescriptor = -1
        }
    }
    
    // MARK: - Send Data
//    public func startSendingData() {
//        startServerTransmitTimer()
//    }
//
//    private func startServerTransmitTimer() {
//        let queue = DispatchQueue(label: "com.chajuss.server.transmitTimer")
//        transmitTimer = DispatchSource.makeTimerSource(queue: queue)
//        transmitTimer!.schedule(deadline: .now(), repeating: .milliseconds(retransmitTime))
//        transmitTimer!.setEventHandler { [weak self] in
//            self?.sendData()
//        }
//        transmitTimer!.resume()
//    }
//
//    private func stopServerTransmitTimer() {
//        transmitTimer?.cancel()
//        transmitTimer = nil
//    }
    
    public func sendData(data: Data) {
        print("Sending \(data.count) bytes on WebSocket")
        socketQueue.async {
            for (_, websocket) in self.websocketMap {
                websocket.send(data: data)
            }
        }
    }
    
    private func prapareData() -> Data {
        var data = Data()
        var byte101: UInt8 = UInt8(101).bigEndian
        withUnsafePointer(to: &byte101) {
            data.append($0.withMemoryRebound(to: UInt8.self, capacity: 1, {$0}), count: MemoryLayout<UInt8>.size)
        }
        var byte0: UInt8 = UInt8(0).bigEndian
        withUnsafePointer(to: &byte0) {
            data.append($0.withMemoryRebound(to: UInt8.self, capacity: 1, {$0}), count: MemoryLayout<UInt8>.size)
        }
        var short: Int16 = Int16(255).bigEndian
        withUnsafePointer(to: &short) {
            data.append($0.withMemoryRebound(to: UInt8.self, capacity: 1, {$0}), count: MemoryLayout<Int16>.size)
        }
        var byte1: UInt8 = UInt8(1).bigEndian
        withUnsafePointer(to: &byte1) {
            data.append($0.withMemoryRebound(to: UInt8.self, capacity: 1, {$0}), count: MemoryLayout<UInt8>.size)
        }
        var byte2: UInt8 = UInt8(0).bigEndian
        withUnsafePointer(to: &byte2) {
            data.append($0.withMemoryRebound(to: UInt8.self, capacity: 1, {$0}), count: MemoryLayout<UInt8>.size)
        }
        var int: Int32 = Int32(300).bigEndian
        withUnsafePointer(to: &int) {
            data.append($0.withMemoryRebound(to: UInt8.self, capacity: 1, {$0}), count: MemoryLayout<Int32>.size)
        }
        return data
    }
    
    // MARK: - Broadcast Methods
    private func startServerBroadcastTimer() {
        let queue = DispatchQueue(label: "com.chajuss.server.broadcastTimer")
        broadcastTimer = DispatchSource.makeTimerSource(queue: queue)
        broadcastTimer!.schedule(deadline: .now(), repeating: .seconds(broadcastRetransmitTime))
        broadcastTimer!.setEventHandler { [weak self] in
            self?.sendBroadcast()
        }
        broadcastTimer!.resume()
    }
    
    private func stopServerBroadcastTimer() {
        broadcastTimer?.cancel()
        broadcastTimer = nil
    }
    
    private func sendBroadcast() {
        guard socketDescriptor != -1 else {
            _ = bindBroadcastSocket()
            return
        }
        var data = Data()
        var short: UInt16 = UInt16(111).bigEndian
        withUnsafePointer(to: &short) {
            data.append($0.withMemoryRebound(to: UInt8.self, capacity: 1, {$0}), count: MemoryLayout<Int16>.size)
        }
//        print("Server sending broadcast")
        data.withUnsafeBytes { (u8Ptr: UnsafePointer<UInt8>) in
            let rawPtr = UnsafeRawPointer(u8Ptr)
            let bytesSent = send(socketDescriptor, rawPtr, data.count, 0)
            if bytesSent == -1 {
                let time = Date().timeIntervalSince1970
                let strError = String(utf8String: strerror(errno)) ?? "Unknown error code"
                let message = "\(time) Socket send error \(errno) (\(strError)), closing socket"
                if socketDescriptor != -1 {
                    close(socketDescriptor)
                    socketDescriptor = -1
                }
                print(message)
            }
        }
    }
    
    private func bindBroadcastSocket() -> Int32 {
        if socketDescriptor != -1 {
            close(socketDescriptor)
        }
        var broadcastIP: String!
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else {
            print("getifaddrs failed")
            return -1
        }
        guard let firstAddr = ifaddr else {
            return -1
        }
        var foundBroadcastInterface = false
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            guard interface.ifa_dstaddr != nil else {
                continue
            }
            let flags = Int32(ifptr.pointee.ifa_flags)
            /// Check for running IPv4, IPv6 interfaces. Skip the loopback interface.
            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK|IFF_BROADCAST)) == (IFF_UP|IFF_RUNNING|IFF_BROADCAST) {
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                    print("IPv4=\(addrFamily == UInt8(AF_INET)) IPv6=\(addrFamily == UInt8(AF_INET6))")
                    // Check interface name:
                    let name = String(cString: interface.ifa_name)
                    print("Broadcast UDP Interface name: \(name)")
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_dstaddr, socklen_t(interface.ifa_dstaddr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    broadcastIP = String(cString: hostname)
                    print("IP Address to broadcast from=\(broadcastIP)")
                    foundBroadcastInterface = true
                    break
                }
            }
        }
        freeifaddrs(ifaddr)
        guard foundBroadcastInterface else {
            print("foundBroadcastInterface failed")
            return socketDescriptor
        }
        socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        if socketDescriptor == -1 {
            let strError = String(utf8String: strerror(errno)) ?? "Unknown error code"
            let message = "Socket creation error \(errno) (\(strError))"
            print(message)
            return socketDescriptor
        }
        var yes: Int = 1
        if setsockopt(socketDescriptor, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int>.size)) == -1 {
            let strError = String(utf8String: strerror(errno)) ?? "Unknown error code"
            let message = "Socket set options error \(errno) (\(strError))"
            print(message)
            close(socketDescriptor)
            socketDescriptor = -1
            return socketDescriptor
        }
        var sa = sockaddr_in(sin_len: __uint8_t(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: in_port_t(bigEndian: broadcastPort), sin_addr: in_addr(s_addr: inet_addr(broadcastIP)), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        var res: Int32 = -1
        res = withUnsafeMutablePointer(to: &sa) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketDescriptor, $0, socklen_t(MemoryLayout.size(ofValue: sa)))
            }
        }
        
        if res != 0 {
            let strError = String(utf8String: strerror(errno)) ?? "Unknown error code"
            let message = "Socket connect error \(errno) (\(strError))"
            close(socketDescriptor)
            print(message)
            socketDescriptor = -1
        }
        print("bindBroadcastSocket returned socket \(socketDescriptor)")
        return socketDescriptor
    }
}
