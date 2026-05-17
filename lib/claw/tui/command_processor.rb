# frozen_string_literal: true

module Claw
  module TUI
    # Dispatches slash commands (/help, /snapshot, /cd, /source, etc.).
    #
    # Previously the entire ~110-line `handle_slash` method lived inline in
    # Model.rb. Pulling it here:
    #   1. Drops the model down toward "state-only" territory
    #   2. Groups all slash-command logic in one file — new commands have an
    #      obvious home
    #   3. Keeps coupling (model state mutation) but contained behind a single
    #      `dispatch(model, text)` entry point
    #
    # All commands return the MVU tuple `[model, command]`.
    module CommandProcessor
      # Built-in commands handled directly here (not via Claw::Commands).
      # Each maps to a private `process_<name>` method below.
      DIRECT_COMMANDS = %w[help new plan cd source doc find].freeze

      # Entry point. Text looks like "/cmd arg arg arg".
      def self.dispatch(model, text)
        cmd, *args = text.sub(%r{\A/}, "").split(" ", 2)
        arg = args.first

        if DIRECT_COMMANDS.include?(cmd)
          send("process_#{cmd}", model, arg)
        else
          # Delegate to the testable Claw::Commands module for the remaining
          # snapshot/rollback/diff/history/status/evolve/role/forge family.
          result = Claw::Commands.dispatch(cmd, arg, runtime: model.runtime)
          model.send(:handle_command_result, CommandResultMsg.new(result: result, cmd: cmd))
          [model, Bubbletea.none]
        end
      end

      # --- Direct commands ---

      def self.process_help(model, _arg)
        cmds = [
          ["/help",         "show this help"],
          ["/new",          "new session"],
          ["/status",       "runtime status"],
          ["/snapshot [l]", "create snapshot"],
          ["/rollback <id>","restore snapshot"],
          ["/diff [a] [b]", "diff snapshots"],
          ["/history",      "list snapshots"],
          ["/plan",         "toggle plan mode"],
          ["/cd <obj>",     "navigate into object"],
          ["/source <m>",   "show method source"],
          ["/doc <m>",      "show method docs"],
          ["/find <pat>",   "search methods"],
          ["/role [name]",  "switch role"],
          ["/evolve",       "run evolution"],
          ["/forge <m>",    "promote method"],
        ]
        max_cmd = cmds.map { |c, _| c.length }.max
        help = cmds.map { |c, d| "  %-#{max_cmd}s — %s" % [c, d] }
        help << ""
        help << "  Ruby expressions are evaluated directly."
        help << "  Natural language is sent to AI automatically."
        help << "  exit/quit — quit (or ctrl+d)"
        help << "  ↑↓ history | tab completion | pgup/pgdn scroll"
        model.chat_history << { role: :system, content: help.join("\n") }
        [model, Bubbletea.none]
      end

      def self.process_new(model, _arg)
        model.chat_history.clear
        model.chat_history << { role: :system, content: "New session." }
        Mana::Context.current.reset! if Mana::Context.current.respond_to?(:reset!)
        model.chat_viewport.content = ""
        model.instance_variable_set(:@scrolled_up, false)
        [model, Bubbletea.none]
      end

      def self.process_plan(model, _arg)
        new_mode = model.mode == :plan ? :normal : :plan
        model.instance_variable_set(:@mode, new_mode)
        model.chat_history << { role: :system, content: "mode: #{new_mode}" }
        [model, Bubbletea.none]
      end

      def self.process_cd(model, arg)
        nav_stack = model.instance_variable_get(:@nav_stack) || []
        model.instance_variable_set(:@nav_stack, nav_stack)
        bind = model.instance_variable_get(:@caller_binding)
        result = ObjectExplorer.cd(arg || "..", bind, nav_stack)
        if result[:type] == :success
          model.instance_variable_set(:@caller_binding, result[:data][:binding])
          model.chat_history << { role: :system, content: "cd → #{result[:data][:label]}" }
        else
          model.chat_history << { role: :error, content: result[:message] }
        end
        [model, Bubbletea.none]
      end

      def self.process_source(model, arg)
        bind = model.instance_variable_get(:@caller_binding)
        result = ObjectExplorer.source(arg.to_s, bind)
        if result[:type] == :data
          model.chat_history << { role: :system,
                                  content: "#{result[:data][:file]}:#{result[:data][:line]}\n#{result[:data][:source]}" }
        elsif result[:type] == :error
          handle_source_fallback(model, arg, bind, result)
        else
          model.chat_history << { role: :error, content: result[:message] }
        end
        [model, Bubbletea.none]
      end

      def self.process_doc(model, arg)
        bind = model.instance_variable_get(:@caller_binding)
        result = ObjectExplorer.doc(arg.to_s, bind)
        model.chat_history << { role: :system, content: result[:data][:doc].to_s }
        [model, Bubbletea.none]
      end

      def self.process_find(model, arg)
        bind = model.instance_variable_get(:@caller_binding)
        result = ObjectExplorer.find(arg.to_s, bind)
        if result[:type] == :data
          model.chat_history << { role: :system, content: result[:data][:matches].join(", ") }
        else
          model.chat_history << { role: :system, content: result[:message] }
        end
        [model, Bubbletea.none]
      end

      # --- Helpers ---

      # /source needs to fall back to REPL-defined methods (which have no
      # source_location, or :location is "(eval)"). Pulled out to keep
      # process_source readable.
      def self.handle_source_fallback(model, arg, bind, result)
        receiver = bind.eval("self")
        defs = receiver.instance_variable_defined?(:@__claw_definitions__) ?
          receiver.instance_variable_get(:@__claw_definitions__) : {}
        if defs[arg.to_s]
          model.chat_history << { role: :system, content: "(defined in REPL)\n#{defs[arg.to_s]}" }
          return
        end
        # Method exists but source is "(eval)"
        meth = bind.eval("method(:#{arg})")
        loc = meth.source_location
        if loc && loc[0] == "(eval)"
          model.chat_history << { role: :system,
                                  content: "Method '#{arg}' defined in REPL session (source not available)" }
        else
          model.chat_history << { role: :error, content: result[:message] }
        end
      rescue
        model.chat_history << { role: :error, content: result[:message] }
      end
    end
  end
end
