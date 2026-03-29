# frozen_string_literal: true

require "fileutils"

module Claw
  # Extends Mana::FileStore with Markdown-based persistence.
  # Replaces JSON memory/session files with human-readable Markdown.
  #
  # Directory layout:
  #   .mana/
  #     MEMORY.md      — long-term memory
  #     session.md     — session summary
  #     values.json    — kept as-is (Marshal data)
  #     definitions.rb — kept as-is
  #     log/
  #       YYYY-MM-DD.md — daily interaction log
  class FileStore < Mana::FileStore
    # Read long-term memories from MEMORY.md.
    # Returns [{id:, content:, created_at:}, ...]
    def read(namespace)
      path = memory_md_path
      return [] unless File.exist?(path)

      parse_memory_md(File.read(path))
    end

    # Write long-term memories to MEMORY.md.
    def write(namespace, memories)
      FileUtils.mkdir_p(base_dir)
      File.write(memory_md_path, generate_memory_md(memories))
    end

    # Delete MEMORY.md.
    def clear(namespace)
      File.delete(memory_md_path) if File.exist?(memory_md_path)
    end

    # Read session data from session.md. Returns {summaries: [...]} or nil.
    def read_session(namespace)
      path = session_md_path
      return nil unless File.exist?(path)

      parse_session_md(File.read(path))
    end

    # Write session data to session.md.
    def write_session(namespace, data)
      FileUtils.mkdir_p(base_dir)
      File.write(session_md_path, generate_session_md(data))
    end

    # Delete session.md.
    def clear_session(namespace)
      File.delete(session_md_path) if File.exist?(session_md_path)
    end

    # Append an entry to the daily log file (log/YYYY-MM-DD.md).
    def append_log(entry)
      dir = File.join(base_dir, "log")
      FileUtils.mkdir_p(dir)
      date = Time.now.strftime("%Y-%m-%d")
      path = File.join(dir, "#{date}.md")

      unless File.exist?(path)
        File.write(path, "# #{date}\n\n")
      end

      time = Time.now.strftime("%H:%M")
      File.open(path, "a") { |f| f.puts "## #{time} — #{entry[:title]}\n#{entry[:detail]}\n" }
    end

    private

    def base_dir
      @base_path || Mana.config.memory_path || File.join(Dir.pwd, ".mana")
    end

    def memory_md_path
      File.join(base_dir, "MEMORY.md")
    end

    def session_md_path
      File.join(base_dir, "session.md")
    end

    # Parse MEMORY.md: split on ## id:N | date headers
    def parse_memory_md(text)
      memories = []
      current = nil
      text.each_line do |line|
        if line.match?(/^## id:(\d+) \| (.+)/)
          if current
            current[:content] = current[:content].strip
            memories << current
          end
          md = line.match(/^## id:(\d+) \| (.+)/)
          current = { id: md[1].to_i, content: "", created_at: md[2].strip }
        elsif current
          current[:content] += line
        end
      end
      if current
        current[:content] = current[:content].strip
        memories << current
      end
      memories
    end

    # Generate MEMORY.md from array of memories
    def generate_memory_md(memories)
      lines = ["# Long-term Memory\n"]
      memories.each do |m|
        date = m[:created_at] || Time.now.iso8601
        lines << "## id:#{m[:id]} | #{date}"
        lines << m[:content].to_s
        lines << ""
      end
      lines.join("\n")
    end

    # Parse session.md: extract summaries and short_term from sections
    def parse_session_md(text)
      summaries = []
      short_term = []
      in_summary = false
      in_short_term = false
      text.each_line do |line|
        if line.strip == "## Summary"
          in_summary = true
          in_short_term = false
          next
        elsif line.strip == "## Short-term"
          in_short_term = true
          in_summary = false
          next
        elsif line.start_with?("## ")
          in_summary = false
          in_short_term = false
        elsif in_summary && line.strip.start_with?("- ")
          summaries << line.strip.sub(/^- /, "")
        elsif in_short_term && line.strip.start_with?("- ")
          # Format: "- role: content"
          stripped = line.strip.sub(/^- /, "")
          if (md = stripped.match(/\A(\w+): (.*)\z/m))
            short_term << { role: md[1], content: md[2] }
          end
        end
      end
      { summaries: summaries, short_term: short_term }
    end

    # Generate session.md from session data hash
    def generate_session_md(data)
      return "" unless data
      lines = ["# Session State\n"]
      summaries = data[:summaries] || data["summaries"] || []
      unless summaries.empty?
        lines << "## Summary"
        summaries.each { |s| lines << "- #{s}" }
        lines << ""
      end
      short_term = data[:short_term] || data["short_term"] || []
      unless short_term.empty?
        lines << "## Short-term"
        short_term.each do |msg|
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"]
          lines << "- #{role}: #{content}" if content.is_a?(String)
        end
        lines << ""
      end
      lines << "## Last Updated"
      lines << (data[:updated_at] || data["updated_at"] || data[:saved_at] || data["saved_at"] || Time.now.iso8601)
      lines << ""
      lines.join("\n")
    end
  end
end
