//
//  LibrespotAuthViewController.swift
//  LibrespotSwift
//
//  Created by Luis Finke on 3/9/25.
//

#if os(iOS)
import UIKit
import WebKit

class LibrespotAuthViewControllerBase: UINavigationController, WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {}
#elseif os(macOS)
import Cocoa
import WebKit

class LibrespotAuthViewControllerBase: NSViewController, WKNavigationDelegate, NSWindowDelegate {}
#endif

#if os(iOS) || os(macOS)
class LibrespotAuthViewController: LibrespotAuthViewControllerBase {
	private let loginOptions: LibrespotAuthOptions
	private let progressView: LibrespotProgressView = LibrespotProgressView()
	private let webViewController = LibrespotWebViewController()
	private let xssState: String = LibrespotUtils.randomURLSafe(length: 128)
	private let codeVerifier: String = LibrespotUtils.randomURLSafe(length: 128)
	
	#if os(iOS)
	public var onCancel: (() -> Void)? = nil;
	#endif
	public var onDismissed: (() -> Void)? = nil;
	public var onDenied: (() -> Void)? = nil;
	public var onError: ((_ error: Error) -> Void)? = nil;
	public var onAuthenticated: ((_ session: LibrespotSession) -> Void)? = nil
	
	private var redirectedURL: URL? = nil;
	
	init(_ options: LibrespotAuthOptions) {
		self.loginOptions = options;
		#if os(iOS)
		super.init(rootViewController: webViewController);
		#elseif os(macOS)
		super.init(nibName: nil, bundle: nil);
		#endif
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	#if os(iOS)
	override public func viewDidLoad() {
		super.viewDidLoad();
		
		print("redirectHookURL = \(self.loginOptions.redirectHookURL)");
		
		self.navigationBar.barTintColor = .black;
		self.navigationBar.tintColor = .white;
		self.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white];
		self.view.backgroundColor = .white;
		self.modalPresentationStyle = .formSheet;
		self.presentationController?.delegate = self;
		
		self.webViewController.webView.navigationDelegate = self;
		//self.webController.title = @"Log into Spotify";
		self.webViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action:#selector(didSelectCancelButton));
		
		if let loginUserAgent = self.loginOptions.loginUserAgent {
			self.webViewController.webView.customUserAgent = loginUserAgent;
		}
		
		if let url = self.loginOptions.spotifyWebAuthenticationURL(
			responseType: self.loginOptions.tokenSwapURL != nil ? .Code : .Token,
			state: self.xssState,
			codeChallengeMethod: .S256,
			codeChallenge: LibrespotUtils.makeCodeChallenge(codeVerifier: self.codeVerifier)) {
			self.webViewController.webView.load(URLRequest(url: url));
		} else {
			print("Failed to create auth url")
		}
	}
	#elseif os(macOS)
	override public func viewDidLoad() {
		super.viewDidLoad()
		
		self.addChild(webViewController)
		self.view.addSubview(webViewController.view)
		webViewController.view.frame = self.view.bounds
		webViewController.view.autoresizingMask = [.width, .height]
		
		self.webViewController.webView.navigationDelegate = self
		
		if let loginUserAgent = self.loginOptions.loginUserAgent {
			self.webViewController.webView.customUserAgent = loginUserAgent
		}
		
		if let url = self.loginOptions.spotifyWebAuthenticationURL(
			responseType: self.loginOptions.tokenSwapURL != nil ? .Code : .Token,
			state: self.xssState,
			codeChallengeMethod: .S256,
			codeChallenge: LibrespotUtils.makeCodeChallenge(codeVerifier: self.codeVerifier)) {
			self.webViewController.webView.load(URLRequest(url: url))
		} else {
			print("Failed to create auth url")
		}
	}
	#endif
	
	#if os(iOS)
	override public var preferredStatusBarStyle: UIStatusBarStyle { .lightContent };
	
	public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
		self.onDismissed?();
	}
	#elseif os(macOS)
	func windowShouldClose(_ sender: NSWindow) -> Bool {
		self.onDismissed?();
		return true;
	}
	#endif
	
	#if os(iOS)
	@objc func didSelectCancelButton(_ sender: Any) {
		self.onCancel?();
	}
	#endif
	
	
	
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

	func canHandleRedirectURL(_ url: URL, redirectURL: URL) -> Bool {
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
				clientID: self.loginOptions.clientID,
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
				session = try await LibrespotAuth.retrieveAccessTokenFrom(
					code: code,
					codeVerifier: self.codeVerifier,
					clientID: self.loginOptions.clientID,
					redirectURI: self.loginOptions.redirectURL.absoluteString,
					url: tokenSwapURL);
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
	
	#if os(iOS)
	private static func findTopViewController() -> UIViewController? {
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
	
	public func show() -> Bool {
		guard let topController = Self.findTopViewController() else {
			return false;
		}
		topController.present(self, animated: true, completion: nil);
		return true;
	}
	
	public func hide(completion: (() -> Void)? = nil) {
		if let presentingVC = self.presentingViewController {
			presentingVC.dismiss(animated:true) {
				completion?();
			};
		} else {
			completion?()
		}
	}
	#elseif os(macOS)
	public func show() -> Bool {
		let window = NSWindow(contentViewController: self);
		window.title = "Login to Spotify";
		window.makeKeyAndOrderFront(nil);
		window.delegate = self;
		return true;
	}
	
	public func hide(completion: (() -> Void)? = nil) {
		self.view.window?.close();
		completion?();
	}
	#endif
	
	
	public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
		if let url = navigationAction.request.url {
			if self.redirectedURL == nil && self.canHandleRedirectURL(url, redirectURL: self.loginOptions.redirectURL) {
				// initial redirect was hit, so start loading
				self.progressView.show(in: self.view, animated: true)
				if self.loginOptions.redirectHookURL != nil && self.loginOptions.redirectHookURL != self.loginOptions.redirectURL {
					// save redirect URL
					self.redirectedURL = url;
					return .allow;
				} else {
					// handle redirect
					Task {
						await self.handleRedirectURL(url)
					}
					return .cancel;
				}
			}
			else if let redirectHookURL = self.loginOptions.redirectHookURL, self.canHandleRedirectURL(url, redirectURL: redirectHookURL) {
				// handle redirect
				let redirectedURL = self.redirectedURL;
				self.redirectedURL = nil;
				Task {
					await self.handleRedirectURL(redirectedURL ?? url)
				}
				return .cancel;
			}
		}
		return .allow;
	}
}
#endif
