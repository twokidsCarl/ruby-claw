# frozen_string_literal: true

require "securerandom"

module Claw
  # A child agent that runs in isolation and can merge results back to parent.
  #
  # Lifecycle: created → running → completed/failed/cancelled
  # Isolation: separate binding (deep-copied vars), separate memory (copied facts),
  # optional git worktree for filesystem.
  class ChildRuntime
    STATES = %i[created running completed failed cancelled].freeze

    CancelledError = Class.new(StandardError)

    attr_reader :id, :state, :result, :error, :runtime, :prompt

    def initialize(parent:, prompt:, vars: {}, role: nil, model: nil)
      @id = SecureRandom.hex(4)
      @parent = parent
      @prompt = prompt
      @vars = vars
      @role = role
      @model = model
      @state = :created
      @result = nil
      @error = nil
      @thread = nil
      @cancelled = false
      @mutex = Mutex.new
    end

    # Start execution in a background thread.
    def start!
      raise "Already started" unless @state == :created

      @state = :running
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @thread = Thread.new { execute }
      self
    end

    # Block until the child completes (or timeout).
    #
    # @param timeout [Numeric, nil] seconds to wait
    # @return [ChildRuntime] self
    def join(timeout: nil)
      @thread&.join(timeout)
      self
    end

    # Request cancellation. The child checks this flag between iterations.
    def cancel!
      @mutex.synchronize do
        @cancelled = true
        @state = :cancelled
      end
    end

    # Elapsed time in milliseconds since start.
    def elapsed_ms
      return 0 unless @started_at

      t = @finished_at || Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ((t - @started_at) * 1000).round
    end

    # Compare child's current state against its initial snapshot.
    # Only callable after the child has completed.
    #
    # @return [Hash] resource diffs
    def diff
      raise "Cannot diff while child is running" if @state == :running
      return {} unless @runtime

      initial = @runtime.snapshots.first&.id
      return {} unless initial

      current_id = @runtime.snapshot!(label: "diff_check")
      @runtime.diff(initial, current_id)
    end

    # Merge child resource changes back to parent.
    #
    # @param only [Array<Symbol>, nil] resource names to merge (nil = all)
    def merge!(only: nil)
      raise "Child not completed" unless @state == :completed
      raise "No child runtime" unless @runtime

      targets = if only
        @runtime.resources.select { |n, _| only.include?(n.to_sym) }
      else
        @runtime.resources
      end

      targets.each do |name, child_res|
        parent_res = @parent.resources[name]
        next unless parent_res

        parent_res.merge_from!(child_res)
      end

      @parent.record_event(
        action: "child_merged",
        target: @id,
        detail: "merged #{targets.keys.join(', ')}"
      )
    end

    # Is the child still running?
    def running?
      @state == :running
    end

    # Is the child done (completed, failed, or cancelled)?
    def done?
      %i[completed failed cancelled].include?(@state)
    end

    private

    def execute
      # 1. Create isolated binding with deep-copied variables
      child_binding = Object.new.instance_eval { binding }
      @vars.each do |k, v|
        copied = begin
          Marshal.load(Marshal.dump(v))
        rescue TypeError
          v # fallback for non-marshalable objects (procs, etc.)
        end
        child_binding.local_variable_set(k, copied)
      end

      # 2. Create child runtime with isolated resources
      @runtime = Claw::Runtime.new

      # Binding resource
      @runtime.register("binding", Resources::BindingResource.new(child_binding))

      # Context resource (fresh for child thread)
      context = Mana::Context.new
      @runtime.register("context", Resources::ContextResource.new(context))

      # Memory resource (copy parent's long-term facts)
      parent_memory_res = @parent.resources["memory"]
      if parent_memory_res
        child_memory = Claw::Memory.new
        parent_mem = parent_memory_res.instance_variable_get(:@memory)
        if parent_mem
          parent_mem.long_term.each do |fact|
            child_memory.remember(fact[:content])
          end
        end
        @runtime.register("memory", Resources::MemoryResource.new(child_memory))
      end

      # Filesystem resource (worktree if parent has filesystem)
      parent_fs = @parent.resources["filesystem"]
      if parent_fs && parent_fs.is_a?(Resources::FilesystemResource)
        worktree = Resources::WorktreeResource.new(
          parent_path: parent_fs.path,
          branch_name: "child-#{@id}"
        )
        @runtime.register("filesystem", worktree)
      end

      @runtime.snapshot!(label: "child_start")

      # 3. Configure role
      if @role
        Claw::Roles.switch!(@role)
      end

      # 4. Execute via Mana engine
      engine = Mana::Engine.new(child_binding)
      raise CancelledError if @cancelled

      raw = engine.execute(@prompt) do |_type, *_args|
        raise CancelledError if @cancelled
      end

      @result = raw
      @mutex.synchronize { @state = :completed unless @cancelled }
    rescue CancelledError
      @mutex.synchronize { @state = :cancelled }
    rescue => e
      @error = e
      @mutex.synchronize { @state = :failed unless @cancelled }
    ensure
      @finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # Cleanup worktree if created
      fs = @runtime&.resources&.dig("filesystem")
      fs.cleanup! if fs.respond_to?(:cleanup!)
    end
  end
end
