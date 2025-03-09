# Code adapted from https://ospfranco.com/post/2024/05/08/react-native-rust-module-guide/

ARCHS_IOS = x86_64-apple-ios aarch64-apple-ios aarch64-apple-ios-sim
ARCHS_MACOS = x86_64-apple-darwin aarch64-apple-darwin
LIB = librespot_swift_gen.a
XCFRAMEWORK = lib/librespot_swift_gen.xcframework
XCFRAMEWORK_HEADERS_DIR = include

all: ios macos xcframework

.PHONY: bindgen-cli
bindgen-cli:
	cargo install bindgen-cli

.PHONY: ios
ios: bindgen-cli $(ARCHS_IOS)
	mkdir -p lib/ios_simulator
	@if [ -f "lib/ios_simulator/$(LIB)" ]; then \
		rm -rf "lib/ios_simulator/$(LIB)"; \
	fi
	lipo -create "target/x86_64-apple-ios/release/$(LIB)" "target/aarch64-apple-ios-sim/release/$(LIB)" -output "lib/ios_simulator/$(LIB)"

.PHONY: $(ARCHS_IOS)
$(ARCHS_IOS): %:
	cargo build --target $@ --release

.PHONY: macos
macos: bindgen-cli $(ARCHS_MACOS)
	mkdir -p lib/macos
	@if [ -f "lib/macos/$(LIB)" ]; then \
		rm -rf "lib/macos/$(LIB)"; \
	fi
	lipo -create "target/x86_64-apple-darwin/release/$(LIB)" "target/aarch64-apple-darwin/release/$(LIB)" -output "lib/macos/$(LIB)"

.PHONY: $(ARCHS_MACOS)
$(ARCHS_MACOS): %:
	cargo build --target $@ --release

.PHONY: xcframework
xcframework: $(XCFRAMEWORK)

$(XCFRAMEWORK): $(ARCHS_IOS) $(ARCHS_MACOS)
	mkdir -p lib
	@if [ -d $@ ]; then \
		rm -rf $@; \
	fi
	xcodebuild -create-xcframework \
		-library "target/aarch64-apple-ios/release/$(LIB)" -headers "$(XCFRAMEWORK_HEADERS_DIR)" \
		-library "lib/ios_simulator/$(LIB)" -headers "$(XCFRAMEWORK_HEADERS_DIR)" \
		-library "lib/macos/$(LIB)" -headers "$(XCFRAMEWORK_HEADERS_DIR)" \
		-output $@

.PHONY: clean
clean:
	rm -rf lib generated target
