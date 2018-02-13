//
//  ServerWrapper.swift
//  WebSocketTest
//
//  Created by Ori Chajuss on 13/02/2018.
//  Copyright © 2018 Ori Chajuss. All rights reserved.
//

import Foundation

class ServerWrapper: NSObject {
    
    // MARK: - Singleton
    static let shared = ServerWrapper()
    
    private override init() {
        super.init()
    }
    
    private var server: TestServer?
    
    public func setupServer(server: TestServer) {
        self.server = server
    }
    
    public func sendData(data: Data) {
        server?.sendData(data: data)
    }
}
