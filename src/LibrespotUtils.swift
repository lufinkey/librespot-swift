//
//  LibrespotUtils.swift
//  LibrespotSwift
//
//  Created by Luis Finke on 3/9/25.
//

import CryptoKit

@objc
public class LibrespotUtils: NSObject {
	static func makeQueryString(_ params: [String: Any]) -> String {
		var parts: [String] = []
		
		for (key, value) in params {
			let keyStr = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
			
			if let value = value as? CustomStringConvertible, !(value is NSNull) {
				var valueStr = value.description.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
				valueStr = valueStr.replacingOccurrences(of: "+", with: "%2B")
				let part = "\(keyStr)=\(valueStr)"
				parts.append(part)
			}
		}
		
		return parts.joined(separator: "&")
	}
	
	static let urlSafeCharacters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
	
	static func randomURLSafe(length: Int) -> String {
		let generator = SystemRandomNumberGenerator()
		let characters = (0..<length).map { _ -> Character in
			var copy = generator  // fixes EXC_BAD_ACCESS bug
			return urlSafeCharacters.randomElement(
				using: &copy
			)!
		}
		return String(characters)
	}
	
	static func makeCodeChallenge(codeVerifier: String) -> String {
		let data = codeVerifier.data(using: .utf8)!
		// The hash is an array of bytes (UInt8).
		let hash = SHA256.hash(data: data)
		// Convert the array of bytes into data.
		let bytes = Data(hash)
		// Base-64 URL-encode the bytes.
		return base64URLEncodedString(bytes)
	}
	
	static func base64URLEncodedString(_ data: Data, options: Data.Base64EncodingOptions = []) -> String {
		return data.base64EncodedString(options: options)
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}
	
	
	static func runOnDispatchQueue(_ queue: DispatchQueue, action: @escaping () -> Void) {
		if OperationQueue.current?.underlyingQueue === queue {
			action()
		} else {
			queue.async(execute: action)
		}
	}
	
	static func runOnMainQueue(_ action: @escaping () -> Void) {
		runOnDispatchQueue(DispatchQueue.main, action: action);
	}
	
	static func date(fromISO8601 isoString: String) -> Date? {
		let dateFormatter = DateFormatter()
		dateFormatter.locale = Locale(identifier: "en_US_POSIX") // set locale to reliable US_POSIX
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
		return dateFormatter.date(from: isoString)
	}
	
	@objc(kindOfError:)
	public static func kindOf(error: NSError) -> String {
		if let lrsError = error as? LibrespotError {
			let kind = lrsError.kind.toString();
			if kind.starts(with: "HTTP") {
				return kind;
			}
			return "Librespot.\(kind)";
		}
		return error.domain;
	}
}
