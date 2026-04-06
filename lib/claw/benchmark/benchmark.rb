# frozen_string_literal: true

require_relative "task"
require_relative "scorer"
require_relative "runner"
require_relative "report"
require_relative "diff"
require_relative "trigger"

module Claw
  module Benchmark
    # Run the full benchmark suite with progress output.
    #
    # @param claw_dir [String] path to .ruby-claw directory
    # @return [SuiteResult]
    def self.run!(claw_dir: ".ruby-claw")
      tasks = load_builtin_tasks
      if tasks.empty?
        $stderr.puts "No benchmark tasks found."
        return
      end

      puts "Running #{tasks.size} benchmark tasks (#{Runner::RUNS_PER_TASK} runs each)...\n\n"

      runner = Runner.new
      suite = runner.run_all(tasks) do |task_id, run_idx, total, completed|
        pct = (completed.to_f / total * 100).round(0)
        print "\r  [#{pct}%] #{task_id} run #{run_idx}/#{Runner::RUNS_PER_TASK}"
      end
      puts "\n\n"

      report_text = Report.generate(suite)
      path = Report.save(report_text, claw_dir)
      puts report_text
      puts "\nReport saved to #{path}"

      suite
    end

    # Compare two benchmark reports.
    #
    # @param path_a [String]
    # @param path_b [String]
    def self.diff!(path_a, path_b)
      unless path_a && path_b
        $stderr.puts "Usage: claw benchmark diff <report_a> <report_b>"
        return
      end

      puts Diff.compare(path_a, path_b)
    end

    # Load all built-in task definitions.
    #
    # @return [Array<Task>]
    def self.load_builtin_tasks
      tasks_dir = File.join(__dir__, "tasks")
      return [] unless Dir.exist?(tasks_dir)

      Dir.glob(File.join(tasks_dir, "*.rb")).sort.each { |f| require f }

      Tasks.all
    end
    private_class_method :load_builtin_tasks

    # Registry for built-in tasks.
    module Tasks
      @registry = []

      def self.register(task)
        @registry << task
      end

      def self.all
        @registry.dup
      end
    end
  end
end
