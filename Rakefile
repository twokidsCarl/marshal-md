# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :test do
  ruby "-Ilib", "test/test_marshal_md.rb"
end

task default: [:spec, :test]
