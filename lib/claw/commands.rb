# frozen_string_literal: true

module Claw
  # Pure-function slash commands. Each method returns a structured result Hash
  # instead of printing directly, making commands testable and reusable
  # across TUI, CLI, and tests.
  #
  # Result format: { type: :success | :error | :info | :data, message: String, data: Any }
  module Commands
    COMMANDS = %w[snapshot rollback diff history status evolve role forge].freeze

    # Dispatch a slash command by name. Returns a result Hash.
    #
    # @param cmd [String] command name (without /)
    # @param arg [String, nil] argument string
    # @param runtime [Claw::Runtime] the runtime instance
    # @param claw_dir [String, nil] path to .ruby-claw/ directory
    # @return [Hash] { type:, message:, data: }
    def self.dispatch(cmd, arg, runtime:, claw_dir: nil)
      unless COMMANDS.include?(cmd)
        return { type: :error, message: "Unknown command: /#{cmd}",
                 data: { available: COMMANDS.map { |c| "/#{c}" } } }
      end

      unless runtime
        return { type: :error, message: "Runtime not initialized" }
      end

      send("cmd_#{cmd}", arg, runtime: runtime, claw_dir: claw_dir)
    rescue => e
      { type: :error, message: "#{e.class}: #{e.message}" }
    end

    # --- Individual commands ---

    def self.cmd_snapshot(arg, runtime:, **)
      id = runtime.snapshot!(label: arg || "manual")
      { type: :success, message: "snapshot ##{id} created#{arg ? " (#{arg})" : ""}", data: { id: id } }
    end

    def self.cmd_rollback(arg, runtime:, **)
      unless arg
        return { type: :error, message: "Usage: /rollback <id>" }
      end
      snap_id = arg.to_i
      runtime.rollback!(snap_id)
      { type: :success, message: "rolled back to snapshot ##{snap_id}", data: { id: snap_id } }
    end

    def self.cmd_diff(arg, runtime:, **)
      snaps = runtime.snapshots
      if snaps.size < 2 && !arg
        return { type: :error, message: "Need at least 2 snapshots to diff" }
      end

      ids = arg ? arg.split.map(&:to_i) : [snaps[-2].id, snaps[-1].id]
      if ids.size < 2
        return { type: :error, message: "Usage: /diff <id_a> <id_b>" }
      end

      diffs = runtime.diff(ids[0], ids[1])
      { type: :data, message: "Diff ##{ids[0]} → ##{ids[1]}",
        data: { from: ids[0], to: ids[1], diffs: diffs } }
    end

    def self.cmd_history(_, runtime:, **)
      snaps = runtime.snapshots
      if snaps.empty?
        return { type: :info, message: "No snapshots" }
      end

      items = snaps.map { |s| { id: s.id, label: s.label, timestamp: s.timestamp } }
      { type: :data, message: "#{items.size} snapshots", data: { snapshots: items } }
    end

    def self.cmd_status(_, runtime:, **)
      { type: :data, message: "Runtime status", data: { markdown: runtime.to_md } }
    end

    def self.cmd_evolve(_, runtime:, claw_dir: nil, **)
      claw_dir ||= File.join(Dir.pwd, ".ruby-claw")
      unless File.directory?(claw_dir)
        return { type: :error, message: "No .ruby-claw/ directory — run `claw init` first" }
      end

      evo = Claw::Evolution.new(runtime: runtime, claw_dir: claw_dir)
      result = evo.evolve
      { type: :data, message: "Evolution cycle completed", data: result }
    end

    def self.cmd_role(arg, runtime:, claw_dir: nil, **)
      claw_dir ||= File.join(Dir.pwd, ".ruby-claw")

      unless arg
        current = Claw::Roles.current
        available = Claw::Roles.list(claw_dir)
        return { type: :data, message: "Roles",
                 data: { current: current&.dig(:name), available: available } }
      end

      Claw::Roles.switch!(arg, claw_dir)
      { type: :success, message: "Switched to role: #{arg}" }
    end

    def self.cmd_forge(arg, runtime:, claw_dir: nil, **)
      unless arg && !arg.strip.empty?
        return { type: :error, message: "Usage: /forge <method_name>" }
      end

      claw_dir ||= File.join(Dir.pwd, ".ruby-claw")
      # Get binding from runtime's binding resource
      binding_res = runtime.resources["binding"]
      unless binding_res
        return { type: :error, message: "No binding resource available" }
      end

      caller_binding = binding_res.instance_variable_get(:@binding)
      result = Claw::Forge.promote(arg.strip, binding: caller_binding, claw_dir: claw_dir)

      if result[:success]
        { type: :success, message: result[:message] }
      else
        { type: :error, message: result[:message] }
      end
    end

    # Make individual commands private from external dispatch
    private_class_method :cmd_snapshot, :cmd_rollback, :cmd_diff,
                         :cmd_history, :cmd_status, :cmd_evolve, :cmd_role, :cmd_forge
  end
end
