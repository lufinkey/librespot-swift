
Pod::Spec.new do |s|
	s.name             = 'Librespot'
	s.version          = '0.1.0'
	s.summary          = 'Swift bindings for Librespot'

	s.description      = <<-DESC
	Allows using the librespot library within Swift
							DESC

	s.homepage         = 'https://github.com/lufinkey/librespot-swift'
	s.author           = { 'Luis Finke' => 'luisfinke@gmail.com' }
	s.source           = { :git => 'https://github.com/lufinkey/librespot-swift.git', :tag => s.version.to_s }
	s.social_media_url = 'https://twitter.com/lufinkey'

	s.source_files = "src/*.{h,m,mm,cpp,swift}", "rust/generated/**/*.{h,m,mm,cpp,swift}"
	s.vendored_frameworks = "rust/lib/librespot_swift_gen.xcframework"
	#s.pod_target_xcconfig = { "DEFINES_MODULE" => "YES" }

	s.prepare_command = <<-CMD
		cd rust
		make
	CMD
end
