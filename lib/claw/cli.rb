# frozen_string_literal: true

module Claw
  # Headless CLI execution for non-interactive subcommands.
  # Shares command logic with TUI via Claw::Commands.
  module CLI
    # Run a CLI subcommand without entering TUI.
    #
    # @param cmd [Symbol] command name
    # @param args [Array<String>] arguments
    def self.run(cmd, *args)
      case cmd
      when :status
        runtime = init_headless_runtime
        result = Commands.dispatch("status", nil, runtime: runtime)
        render(result, "status")

      when :history
        runtime = init_headless_runtime
        result = Commands.dispatch("history", nil, runtime: runtime)
        render(result, "history")

      when :rollback
        runtime = init_headless_runtime
        result = Commands.dispatch("rollback", args.first, runtime: runtime)
        render(result, "rollback")

      when :trace
        render_trace(args.first)

      when :evolve
        runtime = init_headless_runtime
        result = Commands.dispatch("evolve", nil, runtime: runtime)
        render(result, "evolve")

      when :benchmark
        run_benchmark(args)

      when :console
        run_console(args)

      else
        $stderr.puts "Unknown command: #{cmd}"
        exit 1
      end
    end

    # --- Headless runtime ---

    def self.init_headless_runtime
      binding_obj = Object.new.instance_eval { binding }
      runtime = Claw::Runtime.new

      context = Mana::Context.current
      runtime.register("context", Claw::Resources::ContextResource.new(context))

      memory = Claw.memory
      runtime.register("memory", Claw::Resources::MemoryResource.new(memory)) if memory

      runtime.register("binding", Claw::Resources::BindingResource.new(binding_obj))

      claw_dir = File.join(Dir.pwd, ".ruby-claw")
      if File.directory?(claw_dir)
        runtime.register("filesystem", Claw::Resources::FilesystemResource.new(claw_dir))
      end

      runtime.snapshot!(label: "cli_start")
      runtime
    end
    private_class_method :init_headless_runtime

    # --- Output rendering ---

    def self.render(result, cmd)
      case result[:type]
      when :success
        puts "✓ #{result[:message]}"
      when :error
        $stderr.puts "error: #{result[:message]}"
        exit 1
      when :info
        puts result[:message]
      when :data
        case cmd
        when "status"
          render_markdown(result[:data][:markdown])
        when "history"
          result[:data][:snapshots].each do |s|
            puts "  ##{s[:id]} #{s[:label] || '(unlabeled)'} — #{s[:timestamp]}"
          end
        when "evolve"
          evo = result[:data]
          case evo[:status]
          when :accept then puts "✓ accepted: #{evo[:proposal]}"
          when :reject then puts "✗ rejected: #{evo[:proposal] || 'n/a'}"
          when :skip then puts "· skipped: #{evo[:reason]}"
          end
        else
          puts result[:message]
        end
      end
    end
    private_class_method :render

    def self.render_trace(task_id)
      claw_dir = File.join(Dir.pwd, ".ruby-claw")
      traces_dir = File.join(claw_dir, "traces")
      unless Dir.exist?(traces_dir)
        $stderr.puts "No traces directory"
        exit 1
      end

      files = Dir.glob(File.join(traces_dir, "*.md")).sort
      if task_id
        file = files.find { |f| File.basename(f).include?(task_id) }
        unless file
          $stderr.puts "Trace not found: #{task_id}"
          exit 1
        end
        render_markdown(File.read(file))
      else
        files.last(10).each { |f| puts File.basename(f) }
      end
    end
    private_class_method :render_trace

    def self.render_markdown(text)
      begin
        require "glamour"
        puts Glamour.render(text)
      rescue LoadError
        puts text
      end
    end
    private_class_method :render_markdown

    def self.run_benchmark(args)
      subcmd = args.first
      case subcmd
      when "run"
        require_relative "benchmark/benchmark"
        Claw::Benchmark.run!
      when "diff"
        require_relative "benchmark/benchmark"
        Claw::Benchmark.diff!(args[1], args[2])
      else
        puts "Usage: claw benchmark run | claw benchmark diff <a> <b>"
      end
    end
    private_class_method :run_benchmark

    def self.run_console(args)
      claw_dir = File.join(Dir.pwd, ".ruby-claw")
      unless File.directory?(claw_dir)
        $stderr.puts "No .ruby-claw/ directory — run `claw init` first"
        exit 1
      end

      port = Claw.config.console_port
      args.each_with_index { |a, i| port = args[i + 1].to_i if a == "--port" && args[i + 1] }

      runtime = init_headless_runtime
      FileUtils.mkdir_p(File.join(claw_dir, "log"))

      Console::Server.setup(
        claw_dir: claw_dir,
        runtime: runtime,
        memory: Claw.memory,
        port: port
      )

      puts "Claw Console starting on http://127.0.0.1:#{port}"
      Console::Server.run!
    end
    private_class_method :run_console
  end
end
