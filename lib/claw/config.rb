# frozen_string_literal: true

module Claw
  # Claw-specific configuration — extends Mana's config with agent features.
  # Set via Claw.configure { |c| ... }.
  class Config
    attr_accessor :memory_pressure, :memory_keep_recent, :compact_model,
                  :on_compact, :persist_session, :memory_top_k,
                  :tools_dir, :hub_url, :console_port

    def initialize
      @memory_pressure = 0.7
      @memory_keep_recent = 4
      @compact_model = nil
      @on_compact = nil
      @persist_session = true
      @memory_top_k = 10
      @tools_dir = nil   # auto-detect: .ruby-claw/tools/
      @hub_url = nil     # disabled by default
      @console_port = 4567
    end
  end
end
