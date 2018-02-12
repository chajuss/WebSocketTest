//
//  WebSocketParser.swift
//  Telegraph
//
//  Created by Yvo van Beek on 2/17/17.
//  Copyright © 2017 Building42. All rights reserved.
//

import Foundation

//
// Base Framing Protocol (https://tools.ietf.org/html/rfc6455 - 5.2)
//
// |0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|0 1 2 3 4 5 6 7|
// +-+-+-+-+-------+-+-------------+-------------------------------+
// |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
// |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
// |N|V|V|V|       |S|             |   (if payload len==126/127)   |
// | |1|2|3|       |K|             |                               |
// +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
// |    Extended payload length continued if payload len == 127    |
// + - - - - - - - - - - - - - - - +-------------------------------+
// |                               | Masking-key, if MASK set to 1 |
// +-------------------------------+-------------------------------+
// |    Masking-key (continued)    |          Payload Data         |
// +-------------------------------- - - - - - - - - - - - - - - - +
// :                     Payload Data continued ...                :
// + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
// |                     Payload Data continued ...                |
// +---------------------------------------------------------------+
//

// swiftlint:disable function_body_length

public protocol WebSocketParserDelegate: class {
  func parser(_ parser: WebSocketParser, didCompleteMessage message: WebSocketMessage)
}

public class WebSocketParser {
  public let maxPayloadLength: UInt64
  public weak var delegate: WebSocketParserDelegate?
  public private(set) lazy var message = WebSocketMessage()
  public private(set) lazy var maskingKey = [UInt8](repeating: 0, count: 4)
  public private(set) lazy var payload = Data()
  public private(set) var nextPart = Part.finAndOpcode
  public private(set) var bytesParsed = 0
  public private(set) var payloadLength: UInt64 = 0

  /// Describes the different parts to parse.
  public enum Part {
    case finAndOpcode
    case maskAndPayloadLength
    case extendedPayloadLength16(byteNo: Int)
    case extendedPayloadLength64(byteNo: Int)
    case maskingKey(byteNo: Int)
    case payload
    case endOfMessage
  }

  /// Initializes a websocket parser.
  public init(maxPayloadLength: Int = 10_485_760) {
    self.maxPayloadLength = UInt64(maxPayloadLength)
  }

  /// Parses the incoming data into a websocket message.
  public func parse(data: Data) throws {
    bytesParsed = 0

    while bytesParsed < data.count {
      let byte = data[bytesParsed]
      bytesParsed += 1

      switch nextPart {

      case .finAndOpcode:
        // Extract and store the FIN bit
        message.finBit = byte & WebSocketMasks.finBit != 0

        // Extract and validate the opcode
        guard let opcode = WebSocketOpcode(rawValue: byte & WebSocketMasks.opcode)
        else { throw WebSocketError.invalidOpcode }

        // Store the opcode
        message.opcode = opcode
        nextPart = .maskAndPayloadLength

      case .maskAndPayloadLength:
        // Extract the mask bit
        message.maskBit = byte & WebSocketMasks.maskBit != 0

        // Extract the payload length
        payloadLength = UInt64(byte & WebSocketMasks.payloadLength)

        switch payloadLength {
        case 0: nextPart = message.maskBit ? .maskingKey(byteNo: 1) : .endOfMessage
        case 1..<126: nextPart = message.maskBit ? .maskingKey(byteNo: 1) : .payload
        case 126: nextPart = .extendedPayloadLength16(byteNo: 1)
        case 127: nextPart = .extendedPayloadLength64(byteNo: 1)
        default: break
        }

      case .extendedPayloadLength16(let byteNo):
        // Extract the extended payload length (2 bytes)
        switch byteNo {
        case 1:
          payloadLength = UInt64(byte) << 8
          nextPart = .extendedPayloadLength16(byteNo: 2)
        case 2:
          payloadLength += UInt64(byte)
          nextPart = message.maskBit ? .maskingKey(byteNo: 1) : .payload
        default: break
        }

      case .extendedPayloadLength64(let byteNo):
        // Extract the extended payload length (8 bytes)
        switch byteNo {
        case 1:
          payloadLength = UInt64(byte)
          nextPart = .extendedPayloadLength64(byteNo: 2)
        case 2..<8:
          payloadLength = payloadLength << 8 + UInt64(byte)
          nextPart = .extendedPayloadLength64(byteNo: byteNo + 1)
        case 8:
          payloadLength = payloadLength << 8 + UInt64(byte)
          guard payloadLength <= maxPayloadLength else { throw WebSocketError.payloadTooLarge }

          nextPart = message.maskBit ? .maskingKey(byteNo: 1) : .payload
        default: break
        }

      case .maskingKey(let byteNo):
        // Extract the masking key
        switch byteNo {
        case 1, 2, 3:
          maskingKey[byteNo - 1] = byte
          nextPart = .maskingKey(byteNo: byteNo + 1)
        case 4:
          maskingKey[3] = byte
          nextPart = payloadLength > 0 ? .payload : .endOfMessage
        default: break
        }

      case .payload:
        payload.append(byte)

        // Was that the last byte of payload data?
        if UInt64(payload.count) == payloadLength {
          nextPart = .endOfMessage
        }

      case .endOfMessage: break
      }

      // Are we done with the message?
      if case .endOfMessage = nextPart {
        try finishMessage()
      }
    }
  }

  /// Resets the parser.
  public func reset() {
    message = WebSocketMessage()
    nextPart = .finAndOpcode
    maskingKey = [UInt8](repeating: 0, count: 4)
    payloadLength = 0
    payload = Data()
  }

  /// Interprets the payload and calls the delegate to inform of the new message.
  private func finishMessage() throws {
    // Do we have to unmask the payload?
    if message.maskBit {
      payload.mask(with: maskingKey)
    }

    switch message.opcode {
    case .binaryFrame, .continuationFrame:
      // Binary payload
      message.payload = .binary(payload)
    case .textFrame:
      // Text payload
      guard let text = String(data: payload, encoding: .utf8) else { throw WebSocketError.payloadIsNotText }
      message.payload = .text(text)
    case .connectionClose:
      // Close payload
      // TODO: properly handle WebSocket close codes
      message.payload = .close(code: 0, reason: "Close payloads are not implemented")
    case .ping, .pong:
      // Ping / pong with optional payload
      message.payload = payload.isEmpty ? .none : .binary(payload)
    }

    // Keep a reference to the message and reset
    let completedMessage = message
    reset()

    // Inform the delegate
    delegate?.parser(self, didCompleteMessage: completedMessage)
  }
}
