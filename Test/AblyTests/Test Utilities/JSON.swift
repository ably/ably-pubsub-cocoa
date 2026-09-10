//
//  JSON.swift
//  Ably
//
//  Created by Łukasz Szyszkowski on 14/04/2023.
//  Copyright © 2023 Ably. All rights reserved.
//

import Foundation

enum JSONUtility {
    enum Error: Swift.Error {
        case couldNotDecodeString
        case serializedObjectIsNotOfExpectedType
        case dataArgumentIsNil
    }

    private static var decoder: JSONDecoder  {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase

        return jsonDecoder
    }

    private static var encoder: JSONEncoder {
        let jsonEncoder = JSONEncoder()

        return jsonEncoder
    }

    static func decode<T: Codable>(path: String) throws -> T {
        let url = URL(fileURLWithPath: path)

        return try decode(url: url)
    }

    static func decode<T: Codable>(url: URL) throws -> T {
        let data = try Data(contentsOf: url)

        return try decode(data: data)
    }

    static func decode<T: Codable>(data: Data) throws -> T {
        try decoder.decode(T.self, from: data)
    }

    static func encode(_ model: Encodable) throws -> Data {
        try encoder.encode(model)
    }

    static func serialize(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }

    static func toJSONString( _ object: Any, encoding: String.Encoding = .utf8) throws -> String {
        let data = try serialize(object)

        guard let string = String(bytes: data, encoding: encoding) else {
            throw Error.couldNotDecodeString
        }

        return string
    }

    static func codableToDictionary( _ model: Codable) throws -> [String: Any] {
        let data = try encode(model)

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error.serializedObjectIsNotOfExpectedType
        }

        return object
    }

    static func jsonObject<T: Any>(data: Data?) throws -> T {
        guard let data else {
            throw Error.dataArgumentIsNil
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? T else {
            throw Error.serializedObjectIsNotOfExpectedType
        }

        return object
    }
}
