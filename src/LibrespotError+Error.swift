//
//  CoreError.swift
//  Speck
//
//  Created by Jari on 11/11/2024.
//

extension LibrespotError: Error {
	init(kind: String, message: String) {
		self.init(kind: RustString(kind), message: RustString(message));
	}
	
	static func badResponse(message: String? = nil) -> LibrespotError {
		return LibrespotError(kind: "BadResponse", message: message ?? "Bad response");
	}
	
	static func missingSessionParam(_ paramName: String) -> LibrespotError {
		return LibrespotError(kind: "MissingSessionParam", message: "Missing \"\(paramName)\"");
	}
	
	static func missingOption(_ optionName: String) -> LibrespotError {
		return LibrespotError(kind: "MissingOption", message: "Missing \"\(optionName)\"");
	}
	
	static func httpError(status: Int, message: String? = nil) -> LibrespotError {
		return LibrespotError(kind: httpErrorKind(status: status), message: message ?? "HTTP \(status)");
	}
	
	static func httpErrorKind(status: Int) -> String {
		return "HTTPError\(status)";
	}
}
