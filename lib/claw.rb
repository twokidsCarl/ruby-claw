# frozen_string_literal: true

require "mana"
require_relative "claw/version"
require_relative "claw/config"
require_relative "claw/memory_store"
require_relative "claw/memory"
require_relative "claw/knowledge"
require_relative "claw/serializer"
require_relative "claw/chat"

module Claw
  class << self
    def config
      @config ||= Config.new
    end

    def configure
      yield(config) if block_given?
      config
    end

    def chat
      Chat.start(binding.of_caller(1))
    end

    def memory
      Memory.current
    end

    def reset!
      @config = Config.new
      Thread.current[:mana_memory] = nil
    end
  end
end

# Register Claw's enhanced implementations via Mana's provider interfaces.
# No monkey-patching — Mana reads these from its config.
Mana.config.memory_class = Claw::Memory
Mana.config.knowledge_provider = Claw::Knowledge
