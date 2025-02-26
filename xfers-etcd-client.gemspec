require_relative "lib/xfers/etcd/version"

Gem::Specification.new do |s|
  s.name          = "xfers-etcd-client"
  s.version       = Xfers::Etcd::VERSION
  s.license       = "MIT"
  s.authors       = ["Arlo Liu", "Eshton Robateau"]
  s.email         = "arlo@xfers.com, eshton.robateau@fazzfinancial.com"

  s.summary       = "Xfers etcd client module"
  s.description   = "Xfers etcd client"
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0")

  s.files         = Dir["README.md", "lib/xfers_etcd_client.rb", "lib/**/*"]
  s.homepage      = "https://github.com/Xfers/xfers-etcd-client-ruby"
  s.require_paths = ["lib"]

  s.add_dependency "connection_pool", "~> 2.5"
  s.add_dependency "etcdv3", "~> 0.11"
  s.add_dependency "google-protobuf", "3.25"
  s.add_dependency "grpc", "1.64"
end
