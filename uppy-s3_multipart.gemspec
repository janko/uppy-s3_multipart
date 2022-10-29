Gem::Specification.new do |gem|
  gem.name         = "uppy-s3_multipart"
  gem.version      = "1.2.1"

  gem.required_ruby_version = ">= 2.3"

  gem.summary      = "Provides a Rack application that implements endpoints for the AwsS3Multipart Uppy plugin."
  gem.homepage     = "https://github.com/janko/uppy-s3_multipart"
  gem.authors      = ["Janko Marohnić"]
  gem.email        = ["janko.marohnic@gmail.com"]
  gem.license      = "MIT"

  gem.files        = Dir["README.md", "LICENSE.txt", "lib/**/*.rb", "*.gemspec"]
  gem.require_path = "lib"

  gem.add_dependency "roda", ">= 2.27", "< 4"
  gem.add_dependency "aws-sdk-s3", "~> 1.0"
  gem.add_dependency "content_disposition", "~> 1.0"

  gem.add_development_dependency "rake"
  gem.add_development_dependency "minitest"
  gem.add_development_dependency "rack-test_app"
  gem.add_development_dependency "shrine", "~> 2.13"
  gem.add_development_dependency "shrine-memory"
  gem.add_development_dependency "aws-sdk-core", "~> 3.23"
  gem.add_development_dependency "rexml"
end
