# frozen_string_literal: true

require "json"
require "fileutils"

module Claw
  # Extends Mana::FileStore with session persistence.
  # Sessions store conversation state (short-term memory, summaries) across restarts.
  class FileStore < Mana::FileStore
    # Read session data for a namespace. Returns nil if no session exists.
    def read_session(namespace)
      path = session_path(namespace)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path), symbolize_names: true)
    rescue JSON::ParserError
      nil
    end

    # Write session data for a namespace to disk.
    def write_session(namespace, data)
      path = session_path(namespace)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(data))
    end

    # Delete session data for a namespace.
    def clear_session(namespace)
      path = session_path(namespace)
      File.delete(path) if File.exist?(path)
    end

    private

    def session_path(namespace)
      File.join(session_dir, "#{namespace}_session.json")
    end

    def session_dir
      File.join(base_dir, "sessions")
    end

    # Expose base_dir for session_dir — reuse parent's resolution logic
    def base_dir
      super
    end
  end
end
