require_relative "lib/version"

Gem::Specification.new do |s|
  s.name          = "xfers-etcd-client"
  s.version       = Xfers::Etcd::VERSION
  s.license       = "MIT"
  s.authors       = ["Arlo Liu"]
  s.email         = "arlo@xfers.com"

  s.summary       = "Xfers etcd client module"
  s.description   = "Xfers etcd client"
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0")

  s.files         = Dir["README.md", "Rakefile", "lib/*"]
  s.homepage      = "https://github.com/Xfers/xfers-etcd-client-ruby"
  s.require_paths = ["lib"]

  s.add_dependency "etcdv3", "~> 0.10"
  s.add_development_dependency "pry-byebug", "~> 3.9"
  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "rspec", "~> 3.7"
end
