# frozen_string_literal: true

module Claw
  # Reversible Runtime — manages resources and provides atomic snapshot/rollback.
  #
  # All registered resources are snapshot/rolled-back together. A snapshot captures
  # the state of every resource at a point in time; rollback restores all of them
  # atomically.
  #
  # Resources must be registered at startup. Dynamic registration during execution
  # is not allowed — it would break snapshot consistency.
  class Runtime
    Snapshot = Struct.new(:id, :label, :tokens, :timestamp, keyword_init: true)
    Step = Struct.new(:number, :tool_name, :target, :elapsed_ms, keyword_init: true)

    STATES = %i[idle thinking executing_tool failed].freeze

    attr_reader :resources, :snapshots, :events, :state, :current_step, :children

    def initialize
      @resources = {}       # name => resource instance
      @snapshot_data = {}   # snapshot_id => { name => token }
      @snapshots = []       # ordered list of Snapshot metadata
      @next_id = 1
      @locked = false
      @events = []          # append-only event log
      @state = :idle
      @current_step = nil
      @state_callbacks = []
      @children = {}        # id => ChildRuntime (V8)
    end

    # Transition the runtime execution state.
    # Fires registered callbacks with (old_state, new_state, step).
    def transition!(new_state, step: nil)
      raise ArgumentError, "Invalid state: #{new_state}" unless STATES.include?(new_state)

      old = @state
      @state = new_state
      @current_step = step
      @state_callbacks.each { |cb| cb.call(old, new_state, step) }
    end

    # Register an observer for state transitions.
    def on_state_change(&block)
      @state_callbacks << block
    end

    # Register a named resource. Must be called before any snapshot.
    # Raises if called after the first snapshot (resources are locked).
    def register(name, resource)
      raise "Cannot register resources after first snapshot" if @locked
      raise ArgumentError, "Resource must include Claw::Resource" unless resource.is_a?(Claw::Resource)
      raise ArgumentError, "Resource '#{name}' already registered" if @resources.key?(name)

      @resources[name] = resource
    end

    # Atomic snapshot: captures all registered resources.
    # Returns the snapshot id.
    def snapshot!(label: nil)
      @locked = true
      tokens = {}
      @resources.each do |name, resource|
        tokens[name] = resource.snapshot!
      end

      snap = Snapshot.new(
        id: @next_id,
        label: label,
        tokens: tokens.values.sum { |t| t.respond_to?(:size) ? t.size : 0 },
        timestamp: Time.now.iso8601
      )
      @snapshot_data[@next_id] = tokens
      @snapshots << snap
      record_event(action: "snapshot", target: "runtime", detail: "id=#{@next_id} label=#{label}")
      @next_id += 1
      snap.id
    end

    # Atomic rollback: restores all resources to a previous snapshot.
    def rollback!(snap_id)
      tokens = @snapshot_data[snap_id]
      raise ArgumentError, "Unknown snapshot id: #{snap_id}" unless tokens

      @resources.each do |name, resource|
        resource.rollback!(tokens[name])
      end
      record_event(action: "rollback", target: "runtime", detail: "to snapshot id=#{snap_id}")
    end

    # Compare two snapshots across all resources.
    # Returns a Hash { resource_name => diff_string }.
    def diff(snap_id_a, snap_id_b)
      tokens_a = @snapshot_data[snap_id_a]
      tokens_b = @snapshot_data[snap_id_b]
      raise ArgumentError, "Unknown snapshot id: #{snap_id_a}" unless tokens_a
      raise ArgumentError, "Unknown snapshot id: #{snap_id_b}" unless tokens_b

      result = {}
      @resources.each do |name, resource|
        result[name] = resource.diff(tokens_a[name], tokens_b[name])
      end
      result
    end

    # Fork: snapshot → execute block → rollback on failure.
    # Returns [success, result] tuple.
    def fork(label: nil)
      snap_id = snapshot!(label: label || "fork")
      begin
        result = yield
        [true, result]
      rescue => e
        rollback!(snap_id)
        record_event(action: "fork_rollback", target: "runtime", detail: "#{e.class}: #{e.message}")
        [false, e]
      end
    end

    # Append an event to the log.
    def record_event(action:, target:, detail: nil)
      @events << {
        timestamp: Time.now.iso8601,
        action: action,
        target: target,
        detail: detail
      }
    end

    # Fork a child agent that runs in a separate thread with isolated resources.
    # The child can later be merged back via child.merge!
    #
    # @param prompt [String] the task for the child to execute
    # @param vars [Hash] variables to inject into the child's binding
    # @param role [String, nil] optional role name for the child
    # @param model [String, nil] optional model override
    # @return [ChildRuntime]
    def fork_async(prompt:, vars: {}, role: nil, model: nil)
      child = ChildRuntime.new(
        parent: self,
        prompt: prompt,
        vars: vars,
        role: role,
        model: model
      )
      @children[child.id] = child
      child.start!
      record_event(action: "fork_async", target: child.id, detail: prompt[0..80])
      child
    end

    # Render runtime state as Markdown.
    def to_md
      lines = ["# Runtime State\n"]

      lines << "## Status"
      lines << "- state: #{@state}"
      if @current_step
        lines << "- step: ##{@current_step.number} #{@current_step.tool_name} (#{@current_step.target})"
      end
      lines << ""

      lines << "## Resources"
      @resources.each do |name, resource|
        lines << "### #{name}"
        lines << resource.to_md
        lines << ""
      end

      lines << "## Snapshots"
      if @snapshots.empty?
        lines << "(none)"
      else
        @snapshots.each do |snap|
          lines << "- **##{snap.id}** #{snap.label || '(unlabeled)'} — #{snap.timestamp}"
        end
      end
      lines << ""

      lines << "## Events (last 20)"
      @events.last(20).each do |ev|
        lines << "- `#{ev[:timestamp]}` #{ev[:action]} #{ev[:target]} #{ev[:detail]}"
      end

      lines.join("\n")
    end
  end
end
