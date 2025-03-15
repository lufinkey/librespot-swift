//
//  LibrespotAuthViewController.swift
//  LibrespotSwift
//
//  Created by Luis Finke on 3/9/25.
//

#if os(iOS)
import UIKit
import WebKit

public class LibrespotIOSAuthViewController: UINavigationController, WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
	private let loginOptions: LibrespotLoginOptions
	private let progressView: LibrespotIOSProgressView = LibrespotIOSProgressView()
	private let webViewController = LibrespotIOSWebViewController()
	private let xssState: String = UUID().uuidString
	
	public var onCancel: (() -> Void)? = nil;
	public var onDismissed: (() -> Void)? = nil;
	public var onDenied: (() -> Void)? = nil;
	public var onError: ((_ error: Error) -> Void)? = nil;
	public var onAuthenticated: ((_ session: LibrespotSession) -> Void)? = nil
	
	init(_ options: LibrespotLoginOptions) {
		self.loginOptions = options;
		super.init(rootViewController: webViewController);
		
		self.navigationBar.barTintColor = .black;
		self.navigationBar.tintColor = .white;
		self.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white];
		self.view.backgroundColor = .white;
		self.modalPresentationStyle = .formSheet;
		
		if let loginUserAgent = options.loginUserAgent {
			self.webViewController.webView.customUserAgent = loginUserAgent;
		}
		self.webViewController.webView.navigationDelegate = self;
		//_webController.title = @"Log into Spotify";
		self.webViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action:#selector(didSelectCancelButton));
		
		if let url = options.spotifyWebAuthenticationURL(
			responseType: options.tokenSwapURL != nil ? .Code : .Token,
			state: xssState) {
			self.webViewController.webView.load(URLRequest(url: url));
		} else {
			print("Failed to create auth url")
		}
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	override public var preferredStatusBarStyle: UIStatusBarStyle { .lightContent };
	
	@objc func didSelectCancelButton(_ sender: Any) {
		self.onCancel?();
	}
	
	public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
		self.onDismissed?();
	}
	
	
	
	static func decodeQueryString(_ queryString: String) -> [String: String] {
		let parts = queryString.components(separatedBy: "&")
		var params = [String: String]()

		for part in parts {
			let escapedPart = part.replacingOccurrences(of: "+", with: "%20")
			let expressionParts = escapedPart.components(separatedBy: "=")
			
			if expressionParts.count != 2 {
				continue
			}

			let key = expressionParts[0].removingPercentEncoding ?? ""
			let value = expressionParts[1].removingPercentEncoding ?? ""
			params[key] = value
		}

		return params
	}

	static func parseOAuthQueryParams(_ url: URL?) -> [String: String] {
		guard let url = url else {
			return [:]
		}

		let queryParams = decodeQueryString(url.query ?? "")
		
		if queryParams.count > 0 {
			return queryParams
		}

		let fragmentParams = decodeQueryString(url.fragment ?? "")
		if fragmentParams.count > 0 {
			return fragmentParams
		}

		return [:]
	}

	func canHandleRedirectURL(_ url: URL) -> Bool {
		let redirectURL = self.loginOptions.redirectURL;
		
		if !url.absoluteString.hasPrefix(redirectURL.absoluteString) {
			return false
		}
		
		return redirectURL.path == url.path
	}

	@MainActor
	func handleRedirectURL(_ url: URL) async {
		let params = Self.parseOAuthQueryParams(url)
		let state = params["state"]
		let error = params["error"]
		
		// check for error
		if let error = error {
			// Error
			if error == "access_denied" {
				self.onDenied?();
			} else {
				self.onError?(LibrespotError(kind: error, message: error));
			}
			return
		}
		// validate state
		if self.xssState != state {
			// State mismatch
			self.onError?(LibrespotError(kind: "state_mismatch", message: "State mismatch"))
			return;
		}
		// parse response
		if let accessToken = params["access_token"] {
			// Access token
			guard let expiresIn = params["expires_in"], let expireSeconds = Int(expiresIn), expireSeconds != 0 else {
				onError?(LibrespotError.badResponse(message: "Access token expire time was 0"));
				return;
			}
			let session = LibrespotSession(
				accessToken: accessToken,
				expireDate: LibrespotSession.expireDateFromSeconds(expireSeconds),
				refreshToken: params["refresh_token"],
				scopes: params["scope"]?.components(separatedBy: " ") ?? self.loginOptions.scopes);
			onAuthenticated?(session);
		} else if let code = params["code"] {
			// Authentication code
			guard let tokenSwapURL = self.loginOptions.tokenSwapURL else {
				onError?(LibrespotError.missingOption("tokenSwapURL"));
				return
			}

			// swap code for token
			let session: LibrespotSession;
			do {
				session = try await LibrespotAuth.retrieveAccessTokenFrom(code: code, url: tokenSwapURL);
			} catch let error {
				self.onError?(error);
				return;
			}
			if session.scopes.isEmpty {
				session.scopes = self.loginOptions.scopes
			}
			self.onAuthenticated?(session)
		} else {
			onError?(LibrespotError.badResponse(message: "Missing expected parameters in redirect URL"));
		}
	}
	
	public static func findTopViewController() -> UIViewController? {
		guard var topController = UIApplication
			.shared
			.connectedScenes
			.compactMap({ ($0 as? UIWindowScene)?.keyWindow })
			.first(where: { $0.rootViewController != nil })?.rootViewController else {
				return nil
			}
		while let aboveController = topController.presentedViewController {
			topController = aboveController;
		}
		return topController;
	}
	
	
	
	public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
		if let url = navigationAction.request.url, self.canHandleRedirectURL(url) {
			progressView.show(in: self.view, animated: true)
			Task {
				await self.handleRedirectURL(url)
			}
			return .cancel;
		}
		return .allow;
	}
}
#endif
