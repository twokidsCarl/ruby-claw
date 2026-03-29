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

# Override Mana::Memory.current to return Claw::Memory instances.
# This is the key integration point — when claw is loaded, all memory is enhanced.
class Mana::Memory
  class << self
    alias_method :_original_current, :current

    def current
      return nil if incognito?

      Thread.current[:mana_memory] ||= Claw::Memory.new
    end
  end
end
