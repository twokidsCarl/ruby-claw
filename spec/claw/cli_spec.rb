# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Claw::CLI do
  include AnthropicHelper

  describe ".run" do
    it "exits with error for unknown command" do
      expect { Claw::CLI.run(:unknown) }.to raise_error(SystemExit)
    end

    describe ":status" do
      it "outputs status" do
        stub_anthropic_done("ok")
        expect { Claw::CLI.run(:status) }.to output(/runtime/i).to_stdout
      end
    end

    describe ":history" do
      it "outputs snapshot history" do
        expect { Claw::CLI.run(:history) }.to output(/session_start|cli_start/i).to_stdout
      end
    end

    describe ":trace" do
      it "exits with error when no traces directory" do
        expect { Claw::CLI.run(:trace) }.to raise_error(SystemExit)
      end
    end

    describe ":benchmark" do
      it "shows usage for unknown subcommand" do
        expect { Claw::CLI.run(:benchmark, "unknown") }.to output(/Usage/).to_stdout
      end
    end

    describe ":rollback" do
      it "runs rollback command" do
        stub_anthropic_done("ok")
        # rollback without id will output error
        expect { Claw::CLI.run(:rollback) }.to raise_error(SystemExit)
      end
    end

    describe ":evolve" do
      it "runs evolve command" do
        stub_anthropic_done("ok")
        # evolve either errors (no .ruby-claw) or outputs a result
        expect {
          begin
            Claw::CLI.run(:evolve)
          rescue SystemExit
            # expected if no .ruby-claw dir
          end
        }.to output.to_stdout.or output.to_stderr
      end
    end

    describe ":trace with task_id" do
      it "lists recent traces when no task_id" do
        claw_dir = File.join(Dir.pwd, ".ruby-claw")
        traces_dir = File.join(claw_dir, "traces")
        FileUtils.mkdir_p(traces_dir)
        File.write(File.join(traces_dir, "test_trace.md"), "# Trace")
        begin
          expect { Claw::CLI.run(:trace) }.to output(/test_trace/).to_stdout
        ensure
          FileUtils.rm_rf(claw_dir)
        end
      end
    end

    describe ":console" do
      it "exits if no .ruby-claw directory" do
        Dir.mktmpdir do |tmpdir|
          Dir.chdir(tmpdir) do
            expect { Claw::CLI.run(:console) }.to raise_error(SystemExit)
          end
        end
      end
    end
  end
end
