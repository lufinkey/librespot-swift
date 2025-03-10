//
//  LibrespotSession.swift
//  LibrespotSwift
//
//  Created by Luis Finke on 3/9/25.
//

@objc
public class LibrespotSession: NSObject {
	public var accessToken: String;
	public var expireDate: Date;
	public var refreshToken: String?;
	public var scopes: [String];
	
	@objc public init(accessToken: String, expireDate: Date, refreshToken: String?, scopes: [String]) {
		self.accessToken = accessToken;
		self.expireDate = expireDate;
		self.refreshToken = refreshToken;
		self.scopes = scopes;
	}
	
	public var isValid: Bool {
		return (self.expireDate.timeIntervalSince1970 > Date().timeIntervalSince1970);
	}
	
	func saveToUserDefaults(_ userDefaults: UserDefaults, key: String) {
		var data: [String: Any] = [:]
		data["accessToken"] = self.accessToken;
		data["expireDate"] = self.expireDate.ISO8601Format();
		data["refreshToken"] = self.refreshToken;
		data["scopes"] = self.scopes;
		userDefaults.set(data, forKey: key)
	}
	
	static func fromUserDefaults(_ userDefaults: UserDefaults, key: String) -> LibrespotSession? {
		guard let sessionData = userDefaults.object(forKey: key) as? [String: Any] else {
			return nil
		}
		return try? fromDictionary(sessionData)
	}
	
	static func fromDictionary(_ data: [String: Any]) throws -> LibrespotSession {
		// Access token
		guard let accessToken = data["accessToken"] as? String else {
			throw LibrespotError.missingSessionParam("accessToken")
		}
		
		// Expiry date
		var expireDate: Date! = data["expireDate"] as? Date
		if expireDate == nil {
			guard let expireTime = data["expireTime"] as? NSNumber else {
				throw LibrespotError.missingSessionParam("expireTime");
			}
			expireDate = Date(timeIntervalSince1970: expireTime.doubleValue / 1000.0);
		}
		
		// Refresh token
		let refreshToken = data["refreshToken"] as? String;
		
		// Scopes
		guard let scopes = data["scopes"] as? [String] else {
			throw LibrespotError.missingSessionParam("scopes");
		}
		
		return LibrespotSession(
			accessToken: accessToken,
			expireDate: expireDate,
			refreshToken: refreshToken,
			scopes: scopes);
	}
	
	static func expireDateFromSeconds(_ seconds: Int) -> Date {
		let time = Date().timeIntervalSince1970 + TimeInterval(seconds)
		return Date(timeIntervalSince1970: time)
	}
}
