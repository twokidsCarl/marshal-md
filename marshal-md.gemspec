# frozen_string_literal: true

require_relative "lib/marshal-md/version"

Gem::Specification.new do |spec|
  spec.name = "marshal-md"
  spec.version = MarshalMd::VERSION
  spec.authors = ["twokidsCarl"]
  spec.email = ["carl@anz.io"]
  spec.summary = "Human-readable Ruby Marshal alternative using Markdown"
  spec.description = "Serialize Ruby objects to readable Markdown format. API-compatible with Ruby's built-in Marshal. Passes the CRuby official Marshal test suite."
  spec.homepage = "https://twokidscarl.github.io/marshal-md"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.5.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/twokidsCarl/marshal-md",
    "changelog_uri" => "https://github.com/twokidsCarl/marshal-md/releases"
  }

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.0"
end
