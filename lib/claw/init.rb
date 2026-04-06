# frozen_string_literal: true

require "fileutils"
require "open3"

module Claw
  # Scaffolds a new Claw project in the current directory.
  #
  # Creates .ruby-claw/ with:
  #   gems/         — cloned ruby-claw and ruby-mana source (editable)
  #   system_prompt.md — default agent personality (customizable)
  #   MEMORY.md     — empty long-term memory
  #   .git/         — git repo for filesystem snapshots
  #
  # Also generates a project-root Gemfile pointing to local gem copies.
  module Init
    GITHUB_CLAW = "https://github.com/twokidsCarl/ruby-claw.git"
    GITHUB_MANA = "https://github.com/twokidsCarl/ruby-mana.git"

    class << self
      # Run the full init sequence.
      #
      # @param dir [String] project root (defaults to pwd)
      # @param stdout [IO] output stream for progress messages
      def run(dir: Dir.pwd, stdout: $stdout)
        claw_dir = File.join(dir, ".ruby-claw")

        if File.directory?(claw_dir) && !Dir.empty?(claw_dir)
          stdout.puts "  ⚠ .ruby-claw/ already exists — skipping init"
          return false
        end

        FileUtils.mkdir_p(claw_dir)

        clone_gems(claw_dir, stdout)
        write_gemfile(dir, stdout)
        write_system_prompt(claw_dir, stdout)
        write_memory(claw_dir, stdout)
        create_roles(claw_dir, stdout)
        create_tools_dir(claw_dir, stdout)
        git_init(claw_dir, stdout)

        stdout.puts "  ✓ claw init complete"
        stdout.puts "  Run `bundle install` to use local gem copies"
        true
      end

      private

      # Clone ruby-claw and ruby-mana into .ruby-claw/gems/
      def clone_gems(claw_dir, stdout)
        gems_dir = File.join(claw_dir, "gems")
        FileUtils.mkdir_p(gems_dir)

        [
          ["ruby-claw", GITHUB_CLAW],
          ["ruby-mana", GITHUB_MANA]
        ].each do |name, url|
          target = File.join(gems_dir, name)
          if Dir.exist?(target)
            stdout.puts "  · #{name} already cloned"
            next
          end
          stdout.puts "  ↓ cloning #{name}..."
          out, status = Open3.capture2e("git", "clone", "--depth=1", url, target)
          unless status.success?
            raise "Failed to clone #{name}: #{out}"
          end
        end
      end

      # Generate a Gemfile in the project root with path references to local gems.
      def write_gemfile(dir, stdout)
        path = File.join(dir, "Gemfile")
        if File.exist?(path)
          stdout.puts "  · Gemfile already exists — skipping"
          stdout.puts "    Add these lines manually:"
          stdout.puts '    gem "ruby-claw", path: ".ruby-claw/gems/ruby-claw"'
          stdout.puts '    gem "ruby-mana", path: ".ruby-claw/gems/ruby-mana"'
          return
        end

        content = <<~RUBY
          source "https://rubygems.org"

          gem "ruby-claw", path: ".ruby-claw/gems/ruby-claw"
          gem "ruby-mana", path: ".ruby-claw/gems/ruby-mana"
          gem "dotenv"
        RUBY

        File.write(path, content)
        stdout.puts "  ✓ Gemfile created"
      end

      # Write the default system prompt template.
      def write_system_prompt(claw_dir, stdout)
        path = File.join(claw_dir, "system_prompt.md")
        File.write(path, default_system_prompt)
        stdout.puts "  ✓ system_prompt.md created"
      end

      # Create an empty MEMORY.md.
      def write_memory(claw_dir, stdout)
        path = File.join(claw_dir, "MEMORY.md")
        File.write(path, "# Long-term Memory\n")
        stdout.puts "  ✓ MEMORY.md created"
      end

      # Create roles/ directory with a default role.
      def create_roles(claw_dir, stdout)
        roles_dir = File.join(claw_dir, "roles")
        FileUtils.mkdir_p(roles_dir)
        default_path = File.join(roles_dir, "default.md")
        File.write(default_path, <<~ROLE)
          # Default Role

          You are a helpful Ruby assistant with access to the runtime binding.
          Help the user analyze data, write code, and manage their Ruby environment.
        ROLE
        stdout.puts "  ✓ roles/ directory created"
      end

      # Create tools/ directory for project tools.
      def create_tools_dir(claw_dir, stdout)
        tools_dir = File.join(claw_dir, "tools")
        FileUtils.mkdir_p(tools_dir)
        readme = File.join(tools_dir, "README.md")
        File.write(readme, <<~MD) unless File.exist?(readme)
          # Project Tools

          Place `Claw::Tool` class files here. They will be indexed at startup
          and available via `search_tools` / `load_tool`.

          Example:
          ```ruby
          class MyTool
            include Claw::Tool
            tool_name   "my_tool"
            description "Does something useful"
            parameter   :input, type: "String", required: true, desc: "The input"

            def call(input:)
              "Result: \#{input}"
            end
          end
          ```
        MD
        stdout.puts "  ✓ tools/ directory created"
      end

      # Initialize a git repo in .ruby-claw/ with an initial commit.
      def git_init(claw_dir, stdout)
        if Dir.exist?(File.join(claw_dir, ".git"))
          stdout.puts "  · git already initialized"
          return
        end

        run_git(claw_dir, "init")
        run_git(claw_dir, "add", "-A")
        run_git(claw_dir, "commit", "-m", "claw init", "--allow-empty")
        stdout.puts "  ✓ git initialized with initial snapshot"
      end

      def run_git(dir, *args)
        out, status = Open3.capture2e("git", "-C", dir, *args)
        raise "git #{args.first} failed: #{out}" unless status.success?
        out
      end

      def default_system_prompt
        <<~MD
          # System Prompt

          You are a helpful AI assistant embedded in a Ruby runtime.
          You have full access to the Ruby environment through tools.

          ## Personality

          - Be concise and direct
          - Show code when helpful
          - Explain your reasoning when the task is non-trivial
          - Match the user's language (Chinese → Chinese, English → English)

          ## Guidelines

          - Use read_var/write_var for variable access
          - Use call_func for calling Ruby methods
          - Use eval only for defining new methods or requiring libraries
          - Always return a result via the done tool
          - Use the knowledge tool when unsure about your capabilities

          ## Custom Instructions

          Add your project-specific instructions here.
        MD
      end
    end
  end
end
