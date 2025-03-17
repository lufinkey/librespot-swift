//
//  LibrespotLoginOptions.swift
//  LibrespotSwift
//
//  Created by Luis Finke on 3/9/25.
//

public struct LibrespotAuthOptions {
	public enum AuthResponseType: String {
		case Code = "code"
		case Token = "token"
	}
	
	public enum CodeChallengeMethod: String {
		case S256 = "S256"
	}
	
	public enum ParamKey: String {
		case ShowDialog = "show_dialog"
	}
	
	public var clientID: String
	public var redirectURL: URL
	public var scopes: [String]
	public var tokenSwapURL: URL?
	public var tokenRefreshURL: URL?
	public var loginUserAgent: String?
	public var params: [String: String]?
	
	public var showDialog: Bool? {
		get {
			if let valueStr = self.params?[ParamKey.ShowDialog.rawValue] as? String {
				return valueStr == "true";
			}
			return nil;
		}
		set {
			if let newValue = newValue {
				let newValueStr = newValue ? "true" : "false"
				if self.params == nil {
					self.params = [ParamKey.ShowDialog.rawValue: newValueStr];
				} else {
					self.params![ParamKey.ShowDialog.rawValue] = newValueStr
				}
			} else {
				self.params?.removeValue(forKey: ParamKey.ShowDialog.rawValue)
			}
		}
	}
	
	public static var `default`: LibrespotAuthOptions {
		return LibrespotAuthOptions(
			clientID: "65b708073fc0480ea92a077233ca87bd",// librespot_default_client_id().toString(),
			redirectURL: URL(string:"http://127.0.0.1/login")!,
			scopes: ["streaming"],
			tokenSwapURL: URL(string: "https://accounts.spotify.com/api/token")!,
			tokenRefreshURL: URL(string: "https://accounts.spotify.com/api/token")!,
			//loginUserAgent: "Mozilla/5.0",
			params: [ParamKey.ShowDialog.rawValue:"true"])
	}
	
	public func spotifyWebAuthenticationURL(
		responseType: AuthResponseType,
		state: String? = nil,
		codeChallengeMethod: CodeChallengeMethod? = nil,
		codeChallenge: String? = nil
	) -> URL? {
		var components = URLComponents(string: "https://accounts.spotify.com/authorize");
		
		var queryItems: [URLQueryItem] = [
			URLQueryItem(name: "client_id", value: clientID),
			URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
			URLQueryItem(name: "scope", value: scopes.joined(separator: " "))
		];
		
		queryItems.append(URLQueryItem(name: "response_type", value: responseType.rawValue));
		
		if let state = state {
			queryItems.append(URLQueryItem(name: "state", value: state))
		}
		if let codeChallengeMethod = codeChallengeMethod {
			queryItems.append(URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod.rawValue))
		}
		if let codeChallenge = codeChallenge {
			queryItems.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
		}
		
		if let params = self.params {
			for (key, value) in params {
				// Remove duplicate query items if they exist
				queryItems.removeAll { $0.name == key }
				queryItems.append(URLQueryItem(name: key, value: value))
			}
		}
		
		components?.queryItems = queryItems
		return components?.url
	}
	
	public static func from(dictionary dict: [String: Any], fallback fallbackDict: [String: Any], ignore: [String] = []) throws -> LibrespotAuthOptions {
		
		// Extract values from dict or fallbackDict
		let clientID = dict["clientID"] as? String ?? fallbackDict["clientID"] as? String
		let redirectURLString = dict["redirectURL"] as? String ?? fallbackDict["redirectURL"] as? String
		let scopes = dict["scopes"] as? [String] ?? fallbackDict["scopes"] as? [String]
		let tokenSwapURLString = dict["tokenSwapURL"] as? String ?? fallbackDict["tokenSwapURL"] as? String
		let tokenRefreshURLString = dict["tokenRefreshURL"] as? String ?? fallbackDict["tokenRefreshURL"] as? String
		let loginUserAgent = dict["loginUserAgent"] as? String ?? fallbackDict["loginUserAgent"] as? String
		let showDialog = dict["showDialog"] as? Bool ?? fallbackDict["showDialog"] as? Bool
		
		// Validate required fields
		guard let validClientID = clientID else {
			throw LibrespotError.missingOption("clientID")
		}
		
		guard let redirectURLString = redirectURLString, let validRedirectURL = URL(string: redirectURLString) else {
			throw LibrespotError.missingOption("redirectURL")
		}
		
		guard let validScopes = scopes else {
			throw LibrespotError.missingOption("scopes")
		}
		
		var params: [String: String] = [:]
		if let showDialog = showDialog {
			params["show_dialog"] = showDialog ? "true" : "false"
		}
		
		// Create options object at the end
		return LibrespotAuthOptions(
			clientID: validClientID,
			redirectURL: validRedirectURL,
			scopes: validScopes,
			tokenSwapURL: tokenSwapURLString.flatMap { URL(string: $0) },
			tokenRefreshURL: tokenRefreshURLString.flatMap { URL(string: $0) },
			loginUserAgent: loginUserAgent,
			params: params);
	}
}
