# frozen_string_literal: true

module Claw
  module Benchmark
    # Executes benchmark tasks. Each task runs 3 times with a clean environment.
    class Runner
      RUNS_PER_TASK = 3

      # Run the entire benchmark suite.
      #
      # @param tasks [Array<Task>] tasks to run
      # @param on_progress [Proc, nil] called with (task_id, run_index, total)
      # @return [SuiteResult]
      def run_all(tasks, &on_progress)
        total = tasks.size * RUNS_PER_TASK
        completed = 0

        results = tasks.map do |task|
          runs = RUNS_PER_TASK.times.map do |i|
            result = run_once(task)
            completed += 1
            on_progress&.call(task.id, i + 1, total, completed)
            result
          end
          TaskResult.new(task: task, runs: runs)
        end

        SuiteResult.new(results: results, timestamp: Time.now)
      end

      # Execute a single task run with a clean environment.
      #
      # @param task [Task]
      # @return [RunResult]
      def run_once(task)
        # Create isolated binding
        isolated_binding = Object.new.instance_eval { binding }

        # Setup: inject variables
        vars = task.setup.call
        vars.each { |k, v| isolated_binding.local_variable_set(k, v) }

        # Create minimal runtime
        runtime = Claw::Runtime.new
        runtime.register("binding", Claw::Resources::BindingResource.new(isolated_binding))
        runtime.snapshot!(label: "bench_start")

        # Execute
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        engine = Mana::Engine.new(isolated_binding)
        engine.execute(task.prompt)
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

        # Collect results
        trace = engine.trace_data || {}
        steps = trace[:steps] || []
        tool_path = steps.flat_map { |s| (s[:tool_calls] || []).map { |tc| tc[:name] } }
        total_tokens = steps.sum { |s|
          u = s[:usage] || {}
          (u[:input_tokens] || u["input_tokens"] || 0).to_i +
            (u[:output_tokens] || u["output_tokens"] || 0).to_i
        }
        rounds = trace[:total_iterations] || steps.size

        correct = begin
          task.expect.call(isolated_binding)
        rescue => e
          false
        end

        RunResult.new(
          correct: correct,
          rounds: rounds,
          tokens: total_tokens,
          tool_path: tool_path,
          elapsed_ms: elapsed_ms,
          error: nil
        )
      rescue => e
        RunResult.new(
          correct: false,
          rounds: 0,
          tokens: 0,
          tool_path: [],
          elapsed_ms: 0,
          error: "#{e.class}: #{e.message}"
        )
      end
    end
  end
end
