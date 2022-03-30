
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "elasticsearch_repositories/version"

Gem::Specification.new do |spec|
  spec.name          = "elasticsearch_model_repositories"
  spec.version       = ElasticsearchRepositories::VERSION
  spec.authors       = ["Pato"]
  spec.email         = ["pato_devilla@hotmail.com"]

  spec.summary       = %q{Repositories pattern for activerecord models.}
  spec.description   = %q{Support multiple repositories for each model.}
  # spec.homepage      = "TODO: Put your gem's website or public repo URL here."

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  # if spec.respond_to?(:metadata)
  #   spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  #   spec.metadata["homepage_uri"] = spec.homepage
  #   spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  #   spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."
  # else
  #   raise "RubyGems 2.0 or newer is required to protect against " \
  #     "public gem pushes."
  # end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "elasticsearch",  '~> 8'
  spec.add_dependency "activesupport", '~> 6'

  # spec.add_development_dependency 'activemodel', '> 3'
  spec.add_development_dependency "bundler", "2.1.4"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", ">= 5.14"
  spec.add_development_dependency "minitest-reporters", ">= 1.4"
  spec.add_development_dependency "byebug", "~> 9.1.0"

end
