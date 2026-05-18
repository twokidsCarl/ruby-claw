# frozen_string_literal: true

require "fileutils"

module Claw
  # Simple file-backed logger. Writes to `.ruby-claw/claw.log` so users can
  # tail the file to see what's happening inside the TUI (whose stderr is
  # eaten by alt-screen mode and therefore useless for debugging).
  #
  # Levels:
  #   info  — always written
  #   debug — only written when verbose (MANA_VERBOSE=1 or Mana.config.verbose)
  #   error — always written
  #
  # Usage:
  #   Claw::Log.info "loop start: prompt=#{prompt}"
  #   Claw::Log.error e
  #
  # The log file is opened on first write and kept open for the process
  # lifetime. Rotation is a non-goal — users can `rm claw.log` and the next
  # write recreates it.
  module Log
    class << self
      def path
        @path ||= default_path
      end

      # Override (e.g. for tests, or to put the log somewhere outside the
      # project directory). Resets the open file handle.
      def path=(value)
        @file&.close
        @file = nil
        @path = value
      end

      def info(msg)
        write("INFO ", msg)
      end

      def error(msg_or_exception)
        if msg_or_exception.is_a?(Exception)
          e = msg_or_exception
          write("ERROR", "#{e.class}: #{e.message}")
          e.backtrace&.first(5)&.each { |line| write("ERROR", "  #{line}") }
        else
          write("ERROR", msg_or_exception)
        end
      end

      def debug(msg)
        return unless verbose?
        write("DEBUG", msg)
      end

      # Close the file handle. Mainly for tests; not normally needed.
      def close
        @file&.close
        @file = nil
      end

      private

      def default_path
        claw_dir = File.join(Dir.pwd, ".ruby-claw")
        FileUtils.mkdir_p(claw_dir)
        File.join(claw_dir, "claw.log")
      end

      def file
        @file ||= File.open(path, "a").tap do |f|
          f.sync = true  # don't lose lines on crash
        end
      end

      def write(level, msg)
        ts = Time.now.strftime("%Y-%m-%d %H:%M:%S.%3N")
        file.puts("#{ts} #{level} #{msg}")
      rescue => e
        # Logging itself failing should never break the app. Surface to
        # stderr (even if eaten by TUI, it's the only fallback we have).
        $stderr.puts "Claw::Log write failed: #{e.message}"
      end

      def verbose?
        return Mana.config.verbose if defined?(Mana) && Mana.respond_to?(:config)
        false
      end
    end
  end
end
