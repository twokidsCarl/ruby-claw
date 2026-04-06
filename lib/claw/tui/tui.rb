# frozen_string_literal: true

require "bubbletea"
require "lipgloss"
require "bubbles"

require_relative "styles"
require_relative "messages"
require_relative "status_bar"
require_relative "chat_panel"
require_relative "status_panel"
require_relative "command_bar"
require_relative "layout"
require_relative "agent_executor"
require_relative "input_handler"
require_relative "object_explorer"
require_relative "file_card"
require_relative "folding"
require_relative "model"

module Claw
  module TUI
    # Start the TUI application.
    #
    # @param caller_binding [Binding] the caller's binding for variable access
    def self.start(caller_binding)
      # Load session state
      load_session(caller_binding)

      model = Model.new(caller_binding)
      Bubbletea.run(model, alt_screen: true)
    end

    # --- Session loading (extracted from Chat) ---

    def self.load_session(caller_binding)
      # Load compiled mana def methods
      cache_dir = Mana::Compiler.cache_dir
      if Dir.exist?(cache_dir)
        Dir.glob(File.join(cache_dir, "*.rb")).each do |path|
          caller_binding.eval(File.read(path), path, 1) rescue nil
        end
      end

      # Restore runtime state
      return unless Claw.config.persist_session
      dir = File.join(Dir.pwd, ".ruby-claw")
      return unless File.exist?(File.join(dir, "values.json")) || File.exist?(File.join(dir, "definitions.rb"))
      Claw::Serializer.restore(caller_binding, dir) rescue nil
    end

    private_class_method :load_session
  end
end
