//
//  LibrespotProgressView.swift
//  LibrespotSwift
//
//  Created by Luis Finke on 3/9/25.
//

#if os(iOS)
import UIKit

typealias LibrespotProgressViewBase = UIView;
#elseif os(macOS)
import AppKit

typealias LibrespotProgressViewBase = NSView;
#endif

#if os(iOS) || os(macOS)
class LibrespotProgressView: LibrespotProgressViewBase {
	private static let hudSize = CGSize(width: 100, height: 100)
	
	#if os(iOS)
	private var hudView = UIView(frame: CGRect(origin: .zero, size: hudSize));
	var activityIndicator = UIActivityIndicatorView(style: .large);
	#elseif os(macOS)
	private var hudView: NSView = NSView(frame: NSRect(origin: .zero, size: hudSize))
	var activityIndicator: NSProgressIndicator = NSProgressIndicator()
	#endif
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		
		#if os(iOS)
		self.autoresizingMask = [.flexibleWidth, .flexibleHeight];
		
		hudView.backgroundColor = UIColor(white: 0, alpha: 0.6);
		hudView.layer.cornerRadius = 10;
		
		activityIndicator.center = CGPoint(x: Self.hudSize.width / 2, y: Self.hudSize.height / 2);
		#elseif os(macOS)
		self.autoresizingMask = [.width, .height];
		
		hudView.wantsLayer = true;
		hudView.layer?.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor;
		hudView.layer?.cornerRadius = 10;

		activityIndicator.style = .spinning;
		activityIndicator.controlSize = .large;
		activityIndicator.isDisplayedWhenStopped = false;
		var frame = activityIndicator.frame;
		frame.origin = .init(x: (Self.hudSize.width - frame.width) / 2, y: (Self.hudSize.height - frame.height) / 2);
		activityIndicator.frame = frame
		#endif
		
		hudView.addSubview(activityIndicator)
		self.addSubview(hudView)
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	#if os(iOS)
	override func layoutSubviews() {
		super.layoutSubviews()
		
		let size = self.bounds.size
		hudView.center = CGPoint(x: size.width / 2, y: size.height / 2)
	}
	#elseif os(macOS)
	override func layout() {
		super.layout()
		
		let size = self.bounds.size
		hudView.frame.origin = NSPoint(
			x: (size.width - Self.hudSize.width) / 2,
			y: (size.height - Self.hudSize.height) / 2
		)
	}
	#endif
	
	#if os(iOS)
	override func willMove(toSuperview newSuperview: UIView?) {
		super.willMove(toSuperview: newSuperview)
		
		if newSuperview != nil {
			activityIndicator.startAnimating()
		} else {
			activityIndicator.stopAnimating()
		}
	}
	#elseif os(macOS)
	override func viewWillMove(toSuperview newSuperview: NSView?) {
		super.viewWillMove(toSuperview: newSuperview)
		
		if newSuperview != nil {
			activityIndicator.startAnimation(nil)
		} else {
			activityIndicator.stopAnimation(nil)
		}
	}
	#endif
	
	#if os(iOS)
	func show(in view: UIView, animated: Bool, completion: (() -> Void)? = nil) {
		let viewSize = view.bounds.size
		self.frame = CGRect(x: 0, y: 0, width: viewSize.width, height: viewSize.height)
		self.setNeedsLayout()
		
		if animated {
			hudView.alpha = 0
			hudView.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
			view.addSubview(self)
			
			UIView.animate(withDuration: 0.25, animations: {
				self.hudView.alpha = 1
				self.hudView.transform = .identity
			}, completion: { finished in
				completion?()
			})
		} else {
			view.addSubview(self)
			completion?()
		}
	}
	#elseif os(macOS)
	func show(in view: NSView, animated: Bool, completion: (() -> Void)? = nil) {
		self.frame = view.bounds
		self.needsLayout = true
		
		if animated {
			hudView.alphaValue = 0
			hudView.layer?.setAffineTransform(CGAffineTransform(scaleX: 1.4, y: 1.4))
			view.addSubview(self)
			
			NSAnimationContext.runAnimationGroup({ context in
				context.duration = 0.25
				self.hudView.animator().alphaValue = 1
				self.hudView.layer?.setAffineTransform(.identity)
			}, completionHandler: {
				completion?()
			})
		} else {
			view.addSubview(self)
			completion?()
		}
	}
	#endif
	
	#if os(iOS)
	func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
		if animated {
			UIView.animate(withDuration: 0.25, animations: {
				self.alpha = 0
			}, completion: { finished in
				self.removeFromSuperview()
				self.alpha = 1
				completion?()
			})
		} else {
			self.removeFromSuperview()
			completion?()
		}
	}
	#elseif os(macOS)
	func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
		if animated {
			NSAnimationContext.runAnimationGroup({ context in
				context.duration = 0.25
				self.animator().alphaValue = 0
			}, completionHandler: {
				self.removeFromSuperview()
				self.alphaValue = 1
				completion?()
			})
		} else {
			self.removeFromSuperview()
			completion?()
		}
	}
	#endif
}
#endif
