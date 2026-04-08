# frozen_string_literal: true

module Claw
  module TUI
    # Right panel: Binding, Snapshots, Memory, Tokens, Status sections.
    module StatusPanel
      def self.render(model, width, height)
        sections = []

        sections << render_binding(model, width - 2)
        sections << render_snapshots(model, width - 2)
        sections << render_memory(model, width - 2)
        sections << render_tokens(model, width - 2)
        sections << render_status(model, width - 2)

        # Truncate content to fit within available height
        all_lines = sections.join("\n").split("\n")
        content = all_lines.first(height).join("\n")
        Styles::PANEL_BORDER.width(width).height(height).render(content)
      end

      def self.render_binding(model, width)
        header = Styles::SECTION_HEADER.render("Binding")
        return "#{header}\n  (no runtime)" unless model.runtime

        binding_res = model.runtime.resources["binding"]
        return "#{header}\n  (not tracked)" unless binding_res

        lines = [header]
        baseline = model.baseline_vars || []
        user_vars = binding_res.tracked.reject { |name, _| baseline.include?(name) }
        user_vars.each do |name, blob|
          val = begin
            v = MarshalMd.load(blob)
            "#{v.class} (#{summary_value(v)})"
          rescue
            "?"
          end
          line = "  #{name}: #{val}"
          lines << truncate(line, width)
        end
        lines << "  (empty)" if user_vars.empty?

        # Show user-defined methods (only those added during session)
        begin
          b = binding_res.instance_variable_get(:@binding)
          receiver = b.eval("self")
          current_methods = b.eval("methods")
          user_methods = (current_methods - (model.baseline_methods || [])).sort
          unless user_methods.empty?
            lines << Styles::SECTION_HEADER.render("Methods")
            user_methods.each do |m|
              lines << truncate("  def #{m}", width)
            end
          end
        rescue
          # ignore if binding is not accessible
        end

        lines.join("\n")
      end

      def self.render_snapshots(model, width)
        header = Styles::SECTION_HEADER.render("Snapshots")
        return "#{header}\n  (none)" unless model.runtime

        snaps = model.runtime.snapshots.last(5)
        lines = [header]
        snaps.reverse_each do |s|
          lines << "  [#{s.id}] #{s.label || '(unlabeled)'}"
        end
        lines << "  (none)" if snaps.empty?
        lines.join("\n")
      end

      def self.render_memory(model, width)
        header = Styles::SECTION_HEADER.render("Memory")
        memory = Claw.memory
        unless memory
          return "#{header}\n  (disabled)"
        end

        count = memory.long_term.size
        lines = [header, "  #{count} facts"]
        memory.long_term.last(3).each do |m|
          lines << "  · #{truncate(m[:content].to_s, width - 2)}"
        end
        lines.join("\n")
      end

      def self.render_tokens(model, width)
        header = Styles::SECTION_HEADER.render("Tokens")
        ctx = Mana::Context.current
        used = ctx.token_count
        limit = Mana.config.context_window
        pct = limit > 0 ? (used.to_f / limit * 100).round(1) : 0

        bar_width = [width - 12, 10].max
        filled = (bar_width * pct / 100.0).round
        bar = "▓" * filled + "░" * (bar_width - filled)

        lines = [header]
        lines << "  session: #{format_tokens(used)}/#{format_tokens(limit)}"
        lines << "  #{bar} #{pct}%"
        lines.join("\n")
      end

      def self.render_status(model, width)
        header = Styles::SECTION_HEADER.render("Status")
        return "#{header}\n  (no runtime)" unless model.runtime

        state = model.runtime.state
        icon = case state
               when :idle then "●"
               when :thinking then "◉"
               when :executing_tool then "⚡"
               when :failed then "✗"
               else "?"
               end

        lines = [header, "  #{icon} #{state}"]
        if model.runtime.current_step
          step = model.runtime.current_step
          lines << "  #{step.tool_name}(#{step.target})"
        end
        lines.join("\n")
      end

      # --- Helpers ---

      def self.summary_value(v)
        case v
        when NilClass then "nil"
        when TrueClass, FalseClass then v.to_s
        when Numeric then v.to_s
        when Symbol then v.inspect
        when Array then v.size.to_s
        when Hash then "#{v.size} keys"
        when String then v.length > 20 ? "#{v.length} chars" : v.inspect
        else v.inspect[0, 20]
        end
      end

      def self.format_tokens(n)
        return "#{n}" if n < 1000
        "#{(n / 1000.0).round(1)}k"
      end

      def self.truncate(str, max)
        str.length > max ? "#{str[0, max - 3]}..." : str
      end

      private_class_method :render_binding, :render_snapshots, :render_memory,
                           :render_tokens, :render_status,
                           :summary_value, :format_tokens, :truncate
    end
  end
end
