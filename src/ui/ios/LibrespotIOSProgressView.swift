//
//  LibrespotProgressView.swift
//  LibrespotSwift
//
//  Created by Luis Finke on 3/9/25.
//

#if os(iOS)
import UIKit

class LibrespotIOSProgressView: UIView {
	private static let hudSize = CGSize(width: 100, height: 100)
	
	private var hudView = UIView(frame: CGRect(origin: .zero, size: hudSize));
	var activityIndicator = UIActivityIndicatorView(style: .large);
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		
		self.autoresizingMask = [.flexibleWidth, .flexibleHeight];
		
		hudView.backgroundColor = UIColor(white: 0, alpha: 0.6);
		hudView.layer.cornerRadius = 10;
		
		activityIndicator.center = CGPoint(x: Self.hudSize.width / 2, y: Self.hudSize.height / 2);
		
		hudView.addSubview(activityIndicator)
		self.addSubview(hudView)
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	override func layoutSubviews() {
		super.layoutSubviews()
		
		let size = self.bounds.size
		hudView.center = CGPoint(x: size.width / 2, y: size.height / 2)
	}
	
	override func willMove(toSuperview newSuperview: UIView?) {
		super.willMove(toSuperview: newSuperview)
		
		if newSuperview != nil {
			activityIndicator.startAnimating()
		} else {
			activityIndicator.stopAnimating()
		}
	}
	
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
}
#endif
