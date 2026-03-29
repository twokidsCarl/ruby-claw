# frozen_string_literal: true

require_relative "lib/claw/version"

Gem::Specification.new do |s|
  s.name = "ruby-claw"
  s.version = Claw::VERSION
  s.summary = "AI Agent framework for Ruby — chat, memory, persistence"
  s.description = "Claw is an Agent framework built on ruby-mana. Adds interactive chat, persistent memory with compaction, knowledge base, and runtime state persistence."
  s.authors = ["Carl Li"]
  s.license = "MIT"
  s.homepage = "https://github.com/twokidsCarl/ruby-claw"
  s.required_ruby_version = ">= 3.3"

  s.files = Dir["lib/**/*.rb"] + Dir["exe/*"] + Dir["*.md"] + ["LICENSE"]
  s.bindir = "exe"
  s.executables = ["claw"]
  s.require_paths = ["lib"]

  s.add_dependency "ruby-mana", ">= 0.5.11"
  s.add_dependency "binding_of_caller", ">= 1.0"
end
