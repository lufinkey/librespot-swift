//
//  LibrespotLoginOptions.swift
//  LibrespotSwift
//
//  Created by Luis Finke on 3/9/25.
//

public struct LibrespotLoginOptions {
	enum AuthResponseType: String {
		case Code = "code"
		case Token = "token"
	}
	
	enum CodeChallengeMethod: String {
		case S256 = "S256"
	}
	
	enum ParamKey: String {
		case ShowDialog = "show_dialog"
	}
	
	var clientID: String
	var redirectURL: URL
	var scopes: [String]
	var tokenSwapURL: URL?
	var tokenRefreshURL: URL?
	var loginUserAgent: String?
	var params: [String: Any]?
	
	var showDialog: Bool? {
		get { self.params?["show_dialog"] as? Bool }
		set {
			if let newValue = newValue {
				if self.params == nil {
					self.params = [ParamKey.ShowDialog.rawValue: newValue];
				} else {
					self.params![ParamKey.ShowDialog.rawValue] = newValue
				}
			} else {
				self.params?.removeValue(forKey: ParamKey.ShowDialog.rawValue)
			}
		}
	}
	
	func spotifyWebAuthenticationURL(
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
				queryItems.append(URLQueryItem(name: key, value: value as? String))
			}
		}
		
		components?.queryItems = queryItems
		return components?.url
	}
	
	static func from(dictionary dict: [String: Any], fallback fallbackDict: [String: Any], ignore: [String] = []) throws -> LibrespotLoginOptions {
		
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
		
		var params: [String: Any] = [:]
		if let showDialog = showDialog {
			params["show_dialog"] = showDialog ? "true" : "false"
		}
		
		// Create options object at the end
		return LibrespotLoginOptions(
			clientID: validClientID,
			redirectURL: validRedirectURL,
			scopes: validScopes,
			tokenSwapURL: tokenSwapURLString.flatMap { URL(string: $0) },
			tokenRefreshURL: tokenRefreshURLString.flatMap { URL(string: $0) },
			loginUserAgent: loginUserAgent,
			params: params);
	}
}
