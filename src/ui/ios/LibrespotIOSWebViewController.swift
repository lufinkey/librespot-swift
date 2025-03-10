//
//  LibrespotWebViewController.swift
//  LibrespotSwift
//
//  Created by Luis Finke on 3/9/25.
//

#if os(iOS)
import UIKit
import WebKit

class LibrespotIOSWebViewController: UIViewController {
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
#endif

