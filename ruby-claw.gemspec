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

  s.files = Dir["lib/**/*.rb"] + Dir["lib/**/*.erb"] + Dir["lib/**/*.css"] + Dir["lib/**/*.js"] + Dir["exe/*"] + Dir["*.md"] + ["LICENSE"]
  s.bindir = "exe"
  s.executables = ["claw"]
  s.require_paths = ["lib"]

  s.add_dependency "ruby-mana", ">= 0.5.11"
  s.add_dependency "marshal-md", ">= 0.1.0"
  s.add_dependency "binding_of_caller", ">= 1.0"
  s.add_dependency "reline", ">= 0.5"

  # Charm Ruby TUI ecosystem (V6)
  s.add_dependency "bubbletea", ">= 0.1.0"
  s.add_dependency "lipgloss", ">= 0.2.0"
  s.add_dependency "bubbles", ">= 0.1.0"
  s.add_dependency "glamour", ">= 0.2.0"
  s.add_dependency "ntcharts", ">= 0.1.0"
  s.add_dependency "bubblezone", ">= 0.1.0"
  s.add_dependency "huh", ">= 1.0"
  s.add_dependency "harmonica", ">= 0.1.0"

  # Console (V10)
  s.add_dependency "sinatra", ">= 4.0"
  s.add_dependency "rackup", ">= 2.0"
end
