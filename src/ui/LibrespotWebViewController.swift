//
//  LibrespotWebViewController.swift
//  LibrespotSwift
//
//  Created by Luis Finke on 3/9/25.
//

#if os(iOS)
import UIKit
import WebKit

class LibrespotWebViewController: UIViewController {
	public let webView: WKWebView = WKWebView();
	
	override func viewDidLoad() {
		super.viewDidLoad();
		self.view.addSubview(self.webView);
	}
	
	override func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()
		let size = self.view.bounds.size;
		webView.frame = CGRectMake(0,0,size.width, size.height);
	}
}

#elseif os(macOS)
import Cocoa
import WebKit

class LibrespotWebViewController: NSViewController {
	public let webView: WKWebView = WKWebView()

	override func loadView() {
		self.view = NSView()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		self.view.addSubview(webView)

		// Set up autoresizing mask for flexible width and height
		webView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			webView.topAnchor.constraint(equalTo: view.topAnchor),
			webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])
	}
}
#endif

