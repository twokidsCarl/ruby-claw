# frozen_string_literal: true

module Claw
  # Agent role management. Roles are Markdown files in .ruby-claw/roles/
  # that define the agent's system prompt identity.
  #
  # Single-agent: /role data_analyst to switch identity.
  # Multi-agent (V8): child agents reference roles via role: parameter.
  module Roles
    # List available role names.
    #
    # @param claw_dir [String] path to .ruby-claw/
    # @return [Array<String>] role names (without extension)
    def self.list(claw_dir = ".ruby-claw")
      roles_dir = File.join(claw_dir, "roles")
      return [] unless Dir.exist?(roles_dir)

      Dir.glob(File.join(roles_dir, "*.md")).map { |f| File.basename(f, ".md") }.sort
    end

    # Load a role's content by name.
    #
    # @param name [String] role name (e.g., "data_analyst")
    # @param claw_dir [String] path to .ruby-claw/
    # @return [String] role file content
    # @raise [RuntimeError] if role file not found
    def self.load(name, claw_dir = ".ruby-claw")
      normalized = name.tr(" ", "_").downcase
      path = File.join(claw_dir, "roles", "#{normalized}.md")
      raise "Role not found: #{name} (expected #{path})" unless File.exist?(path)

      File.read(path)
    end

    # Switch the current agent's role (thread-local).
    #
    # @param name [String] role name
    # @param claw_dir [String] path to .ruby-claw/
    def self.switch!(name, claw_dir = ".ruby-claw")
      content = load(name, claw_dir)
      Thread.current[:claw_role] = { name: name, content: content }
    end

    # Get the current role.
    #
    # @return [Hash, nil] { name:, content: } or nil
    def self.current
      Thread.current[:claw_role]
    end

    # Clear the current role.
    def self.clear!
      Thread.current[:claw_role] = nil
    end
  end
end
