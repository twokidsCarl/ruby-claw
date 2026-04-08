# frozen_string_literal: true

module Claw
  module TUI
    # Object exploration commands (pry-style): /cd, /source, /doc, /find.
    module ObjectExplorer
      # @param binding [Binding]
      # @return [Hash] { type:, data: }
      def self.ls(binding)
        receiver = binding.eval("self")
        sections = {}

        # Local variables
        locals = binding.local_variables.map do |sym|
          val = binding.local_variable_get(sym)
          "  #{sym}: #{val.class} = #{safe_inspect(val)}"
        end
        sections["Local Variables"] = locals unless locals.empty?

        # Instance variables
        ivars = receiver.instance_variables.map do |ivar|
          val = receiver.instance_variable_get(ivar)
          "  #{ivar}: #{val.class} = #{safe_inspect(val)}"
        end
        sections["Instance Variables"] = ivars unless ivars.empty?

        # Public methods (own, not inherited from Object)
        own_methods = (receiver.methods - Object.instance_methods).sort
        sections["Methods"] = own_methods.map { |m| "  #{m}" } unless own_methods.empty?

        { type: :data, data: sections }
      end

      # Navigate into an object's context.
      # Returns [new_binding, prompt_label] or error.
      def self.cd(expression, binding, nav_stack)
        if expression == ".."
          if nav_stack.empty?
            return { type: :error, message: "Already at top level" }
          end
          prev = nav_stack.pop
          return { type: :success, data: { binding: prev[:binding], label: prev[:label] } }
        end

        begin
          obj = binding.eval(expression)
          nav_stack.push({ binding: binding, label: binding.eval("self").class.name })
          # Create a new binding inside the object's context
          new_binding = obj.instance_eval { binding }
          label = "#{obj.class.name}(#{safe_inspect_short(obj)})"
          { type: :success, data: { binding: new_binding, label: label } }
        rescue => e
          { type: :error, message: "#{e.class}: #{e.message}" }
        end
      end

      # Show source code of a method.
      def self.source(method_name, binding)
        receiver = binding.eval("self")
        meth = if receiver.respond_to?(method_name.to_sym)
                 receiver.method(method_name.to_sym)
               elsif receiver.class.method_defined?(method_name.to_sym)
                 receiver.class.instance_method(method_name.to_sym)
               else
                 return { type: :error, message: "Method '#{method_name}' not found" }
               end

        file, line = meth.source_location
        unless file && File.exist?(file)
          return { type: :error, message: "Source not available (native method or no source location)" }
        end

        lines = File.readlines(file)
        # Show context: method line +/- 10
        start = [line - 1, 0].max
        finish = [line + 19, lines.size - 1].min
        source_lines = lines[start..finish].each_with_index.map do |l, i|
          num = start + i + 1
          marker = num == line ? "→ " : "  "
          "#{marker}#{num.to_s.rjust(4)}: #{l.rstrip}"
        end

        { type: :data, data: { file: file, line: line, source: source_lines.join("\n") } }
      end

      # Query documentation via Mana Knowledge.
      def self.doc(method_name, binding)
        receiver = binding.eval("self")
        klass = receiver.is_a?(Class) ? receiver.name : receiver.class.name
        query = "#{klass}##{method_name}"

        result = Claw::Knowledge.query(query)
        { type: :data, data: { topic: query, doc: result } }
      end

      # Find methods matching a pattern.
      def self.find(pattern, binding)
        receiver = binding.eval("self")
        regex = begin
          Regexp.new(pattern, Regexp::IGNORECASE)
        rescue RegexpError
          return { type: :error, message: "Invalid pattern: #{pattern}" }
        end
        matches = receiver.methods.select { |m| m.to_s.match?(regex) }.sort

        if matches.empty?
          { type: :info, message: "No methods matching '#{pattern}'" }
        else
          { type: :data, data: { pattern: pattern, matches: matches.map(&:to_s) } }
        end
      end

      # Show current source location.
      def self.whereami(binding)
        file = binding.eval("__FILE__") rescue "(unknown)"
        line = binding.eval("__LINE__") rescue 0
        receiver = binding.eval("self")
        { type: :data, data: { file: file, line: line, receiver: receiver.class.name } }
      end

      # --- Helpers ---

      def self.safe_inspect(val)
        str = val.inspect
        str.length > 60 ? "#{str[0, 57]}..." : str
      end

      def self.safe_inspect_short(val)
        str = val.inspect
        str.length > 20 ? "#{str[0, 17]}..." : str
      end

      private_class_method :safe_inspect, :safe_inspect_short
    end
  end
end
