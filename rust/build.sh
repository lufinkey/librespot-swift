#!/bin/bash

# Code adapted from https://ospfranco.com/post/2024/05/08/react-native-rust-module-guide/

if [ -z "$(which cargo)" ]; then
	>&2 echo "Missing cargo command"
	exit 1
fi
if [ -z "$(which xcodebuild)" ]; then
	>&2 echo "Missing xcodebuild command"
	exit 1
fi

LIB_FILE="librespot_swift_gen.a"
XCFRAMEWORK_FILE="librespot_swift_gen.xcframework"
XCFRAMEWORK_HEADERS_DIR="include"
export RUST_BACKTRACE=full

cd "$(dirname "$0")" || exit $?
cargo build \
	--target "x86_64-apple-ios" \
	--target "aarch64-apple-ios" \
	--target "aarch64-apple-ios-sim" \
	--target "x86_64-apple-darwin" \
	--target "aarch64-apple-darwin" \
	--release || exit $?
mkdir -p lib || exit $?
# build combined ios simulator lib
mkdir -p lib/ios_simulator || exit $?
if [ -f "lib/ios_simulator/$LIB_FILE" ]; then
	rm -rf "lib/ios_simulator/$LIB_FILE" || exit $?
fi
lipo -create "target/x86_64-apple-ios/release/$LIB_FILE" "target/aarch64-apple-ios-sim/release/$LIB_FILE" -output "lib/ios_simulator/$LIB_FILE" || exit $?
# build combined macos lib
mkdir -p lib/macos || exit $?
if [ -f "lib/macos/$LIB_FILE" ]; then
	rm -rf "lib/macos/$LIB_FILE" || exit $?
fi
lipo -create "target/x86_64-apple-darwin/release/$LIB_FILE" "target/aarch64-apple-darwin/release/$LIB_FILE" -output "lib/macos/$LIB_FILE" || exit $?
# build xcframework
if [ -d "lib/$XCFRAMEWORK_FILE" ]; then
	rm -rf "lib/$XCFRAMEWORK_FILE" || exit $?
fi
xcodebuild -create-xcframework \
	-library "target/aarch64-apple-ios/release/$LIB_FILE" -headers "$XCFRAMEWORK_HEADERS_DIR" \
	-library "lib/ios_simulator/$LIB_FILE" -headers "$XCFRAMEWORK_HEADERS_DIR" \
	-library "lib/macos/$LIB_FILE" -headers "$XCFRAMEWORK_HEADERS_DIR" \
	-output "lib/$XCFRAMEWORK_FILE" || exit $?
