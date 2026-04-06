# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../lib/claw/benchmark/benchmark"

RSpec.describe Claw::Benchmark do
  describe Claw::Benchmark::Task do
    it "creates a task with all fields" do
      task = Claw::Benchmark::Task.new(
        id: "test_task",
        layer: :mana,
        setup: -> { { x: 1 } },
        prompt: "do something",
        expect: ->(b) { true },
        max_rounds: 3,
        max_tokens: 2000,
        ideal_path: %w[read_var write_var]
      )

      expect(task.id).to eq("test_task")
      expect(task.layer).to eq(:mana)
      expect(task.max_rounds).to eq(3)
      expect(task.ideal_path).to eq(%w[read_var write_var])
    end
  end

  describe Claw::Benchmark::RunResult do
    it "stores run data" do
      run = Claw::Benchmark::RunResult.new(
        correct: true, rounds: 2, tokens: 150,
        tool_path: %w[read_var write_var], elapsed_ms: 500, error: nil
      )

      expect(run.correct).to be true
      expect(run.rounds).to eq(2)
      expect(run.tokens).to eq(150)
    end
  end

  describe Claw::Benchmark::TaskResult do
    let(:task) do
      Claw::Benchmark::Task.new(
        id: "t1", layer: :mana, setup: -> { {} }, prompt: "p",
        expect: ->(b) { true }, max_rounds: 3, max_tokens: 2000, ideal_path: []
      )
    end

    it "calculates pass_rate" do
      runs = [
        Claw::Benchmark::RunResult.new(correct: true, rounds: 1, tokens: 100, tool_path: [], elapsed_ms: 100, error: nil),
        Claw::Benchmark::RunResult.new(correct: false, rounds: 2, tokens: 200, tool_path: [], elapsed_ms: 200, error: nil),
        Claw::Benchmark::RunResult.new(correct: true, rounds: 1, tokens: 100, tool_path: [], elapsed_ms: 100, error: nil)
      ]
      tr = Claw::Benchmark::TaskResult.new(task: task, runs: runs)

      expect(tr.pass_rate).to be_within(0.01).of(0.667)
    end

    it "returns 0 pass_rate for empty runs" do
      tr = Claw::Benchmark::TaskResult.new(task: task, runs: [])
      expect(tr.pass_rate).to eq(0.0)
    end
  end

  describe Claw::Benchmark::SuiteResult do
    it "calculates suite_score and pass_rate" do
      task = Claw::Benchmark::Task.new(
        id: "t1", layer: :mana, setup: -> { {} }, prompt: "p",
        expect: ->(b) { true }, max_rounds: 3, max_tokens: 2000, ideal_path: []
      )
      run_pass = Claw::Benchmark::RunResult.new(correct: true, rounds: 1, tokens: 100, tool_path: [], elapsed_ms: 100, error: nil)
      run_fail = Claw::Benchmark::RunResult.new(correct: false, rounds: 1, tokens: 100, tool_path: [], elapsed_ms: 100, error: nil)

      tr1 = Claw::Benchmark::TaskResult.new(task: task, runs: [run_pass, run_pass, run_pass])
      tr2 = Claw::Benchmark::TaskResult.new(task: task, runs: [run_fail, run_fail, run_fail])

      suite = Claw::Benchmark::SuiteResult.new(results: [tr1, tr2], timestamp: Time.now)

      expect(suite.pass_rate).to be_within(0.01).of(0.5)
      expect(suite.suite_score).to be > 0
    end

    it "returns 0 for empty results" do
      suite = Claw::Benchmark::SuiteResult.new(results: [], timestamp: Time.now)
      expect(suite.suite_score).to eq(0.0)
      expect(suite.pass_rate).to eq(0.0)
    end
  end

  describe Claw::Benchmark::Scorer do
    let(:task) do
      Claw::Benchmark::Task.new(
        id: "t1", layer: :mana, setup: -> { {} }, prompt: "p",
        expect: ->(b) { true }, max_rounds: 3, max_tokens: 2000,
        ideal_path: %w[read_var write_var]
      )
    end

    it "gives max score for perfect run" do
      run = Claw::Benchmark::RunResult.new(
        correct: true, rounds: 0, tokens: 0,
        tool_path: %w[read_var write_var], elapsed_ms: 100, error: nil
      )
      score = Claw::Benchmark::Scorer.score_run(run, task)
      expect(score).to eq(100.0)
    end

    it "gives 0 for incorrect run" do
      run = Claw::Benchmark::RunResult.new(
        correct: false, rounds: 1, tokens: 500,
        tool_path: %w[read_var], elapsed_ms: 100, error: nil
      )
      score = Claw::Benchmark::Scorer.score_run(run, task)
      expect(score).to eq(0.0)
    end

    it "applies rounds penalty" do
      run = Claw::Benchmark::RunResult.new(
        correct: true, rounds: 3, tokens: 0,
        tool_path: %w[read_var write_var], elapsed_ms: 100, error: nil
      )
      score = Claw::Benchmark::Scorer.score_run(run, task)
      expect(score).to eq(80.0)
    end

    it "applies tokens penalty" do
      run = Claw::Benchmark::RunResult.new(
        correct: true, rounds: 0, tokens: 1000,
        tool_path: %w[read_var write_var], elapsed_ms: 100, error: nil
      )
      score = Claw::Benchmark::Scorer.score_run(run, task)
      expect(score).to eq(90.0)
    end

    it "applies path penalty for different tool sequences" do
      run = Claw::Benchmark::RunResult.new(
        correct: true, rounds: 0, tokens: 0,
        tool_path: %w[eval_code], elapsed_ms: 100, error: nil
      )
      score = Claw::Benchmark::Scorer.score_run(run, task)
      expect(score).to be < 100.0
    end

    describe ".path_penalty" do
      it "returns 0 for matching paths" do
        expect(Claw::Benchmark::Scorer.path_penalty(%w[a b], %w[a b])).to eq(0.0)
      end

      it "returns 0 for empty ideal path" do
        expect(Claw::Benchmark::Scorer.path_penalty(%w[a b], [])).to eq(0.0)
      end

      it "caps at 20" do
        expect(Claw::Benchmark::Scorer.path_penalty(%w[a b c d e f], %w[z])).to eq(20.0)
      end
    end
  end

  describe Claw::Benchmark::Report do
    it "generates markdown report" do
      task = Claw::Benchmark::Task.new(
        id: "t1", layer: :mana, setup: -> { {} }, prompt: "p",
        expect: ->(b) { true }, max_rounds: 3, max_tokens: 2000, ideal_path: []
      )
      run = Claw::Benchmark::RunResult.new(
        correct: true, rounds: 1, tokens: 100,
        tool_path: %w[read_var], elapsed_ms: 250, error: nil
      )
      tr = Claw::Benchmark::TaskResult.new(task: task, runs: [run])
      suite = Claw::Benchmark::SuiteResult.new(results: [tr], timestamp: Time.new(2026, 1, 15, 10, 0, 0))

      report = Claw::Benchmark::Report.generate(suite)
      expect(report).to include("# Benchmark Report")
      expect(report).to include("2026-01-15")
      expect(report).to include("t1")
      expect(report).to include("Suite score")
      expect(report).to include("✓")
    end

    it "saves report to file" do
      Dir.mktmpdir do |dir|
        path = Claw::Benchmark::Report.save("# Test Report", dir)
        expect(File.exist?(path)).to be true
        expect(File.read(path)).to eq("# Test Report")
      end
    end
  end

  describe Claw::Benchmark::Diff do
    it "compares two report files" do
      Dir.mktmpdir do |dir|
        report_a = <<~MD
          # Benchmark Report
          ### task_a (mana)
          - **Score:** 80.0
          ### task_b (claw)
          - **Score:** 60.0
        MD
        report_b = <<~MD
          # Benchmark Report
          ### task_a (mana)
          - **Score:** 90.0
          ### task_b (claw)
          - **Score:** 50.0
        MD

        path_a = File.join(dir, "report_a.md")
        path_b = File.join(dir, "report_b.md")
        File.write(path_a, report_a)
        File.write(path_b, report_b)

        diff = Claw::Benchmark::Diff.compare(path_a, path_b)
        expect(diff).to include("Benchmark Diff")
        expect(diff).to include("task_a")
        expect(diff).to include("task_b")
        expect(diff).to include("report_a.md")
        expect(diff).to include("report_b.md")
      end
    end

    it "raises for missing files" do
      expect { Claw::Benchmark::Diff.compare("/nonexistent/a.md", "/nonexistent/b.md") }
        .to raise_error(RuntimeError, /Report not found/)
    end
  end

  describe Claw::Benchmark::Trigger do
    let(:runtime) { double("Runtime", record_event: nil) }
    let(:trigger) { Claw::Benchmark::Trigger.new(runtime: runtime, claw_dir: "/tmp/test-claw") }
    let(:mock_evo) { double("Evolution", evolve: nil) }

    before do
      allow(Claw::Evolution).to receive(:new).with(any_args).and_return(mock_evo)
    end

    describe "#check_after_benchmark!" do
      it "does nothing when no previous score" do
        expect(Claw::Evolution).not_to receive(:new)
        trigger.check_after_benchmark!(80.0, nil)
      end

      it "does nothing when score improved" do
        expect(Claw::Evolution).not_to receive(:new)
        trigger.check_after_benchmark!(85.0, 80.0)
      end

      it "triggers evolution on score regression" do
        expect(Claw::Evolution).to receive(:new).and_return(mock_evo)
        trigger.check_after_benchmark!(70.0, 80.0)
      end
    end

    describe "#check_after_trace!" do
      it "does nothing with fewer than 3 results" do
        expect(Claw::Evolution).not_to receive(:new)
        trigger.check_after_trace!("task1", [false, false])
      end

      it "does nothing when not all 3 failed" do
        expect(Claw::Evolution).not_to receive(:new)
        trigger.check_after_trace!("task1", [false, true, false])
      end

      it "triggers evolution on 3 consecutive failures" do
        expect(Claw::Evolution).to receive(:new).and_return(mock_evo)
        trigger.check_after_trace!("task1", [false, false, false])
      end
    end
  end

  describe Claw::Benchmark::Tasks do
    it "registers built-in tasks when loaded" do
      # Tasks are loaded via require in benchmark.rb
      # Force load tasks
      tasks_dir = File.join(File.dirname(__FILE__), "../../../lib/claw/benchmark/tasks")
      Dir.glob(File.join(tasks_dir, "*.rb")).sort.each { |f| load f }

      tasks = Claw::Benchmark::Tasks.all
      expect(tasks).to be_an(Array)
      expect(tasks.size).to be >= 9
      ids = tasks.map(&:id)
      expect(ids).to include("mana_var_readwrite", "mana_eval", "claw_remember")
    end
  end
end
