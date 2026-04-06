# frozen_string_literal: true

module Claw
  # Mixin for defining project tools as classes with a declarative DSL.
  #
  # Usage:
  #   class FormatReport
  #     include Claw::Tool
  #     tool_name   "format_report"
  #     description "Format raw data into a readable report"
  #     parameter   :data,  type: "Hash",   required: true,  desc: "Raw data"
  #     parameter   :style, type: "String", required: false, desc: "brief or detailed"
  #
  #     def call(data:, style: "brief")
  #       # ...
  #     end
  #   end
  module Tool
    @tool_classes = []

    def self.tool_classes
      @tool_classes
    end

    def self.included(base)
      base.extend(ClassMethods)
      base.instance_variable_set(:@tool_parameters, [])
      @tool_classes << base unless @tool_classes.include?(base)
    end

    module ClassMethods
      def tool_name(name = nil)
        if name
          @tool_name = name
        else
          @tool_name || self.name&.split("::")&.last&.gsub(/([a-z])([A-Z])/, '\1_\2')&.downcase
        end
      end

      def description(desc = nil)
        if desc
          @tool_description = desc
        else
          @tool_description || ""
        end
      end

      def parameter(name, type: "String", required: false, desc: "")
        @tool_parameters ||= []
        @tool_parameters << { name: name, type: type, required: required, desc: desc }
      end

      def tool_parameters
        @tool_parameters || []
      end

      # Generate a Mana-compatible tool definition hash.
      def to_tool_definition
        props = {}
        required = []

        tool_parameters.each do |p|
          json_type = ruby_type_to_json(p[:type])
          props[p[:name].to_s] = { type: json_type, description: p[:desc] }
          required << p[:name].to_s if p[:required]
        end

        {
          name: tool_name,
          description: description,
          input_schema: {
            type: "object",
            properties: props,
            required: required
          }
        }
      end

      private

      def ruby_type_to_json(type)
        case type.to_s
        when "String"  then "string"
        when "Integer", "Fixnum", "Bignum" then "integer"
        when "Float", "Numeric" then "number"
        when "Hash"    then "object"
        when "Array"   then "array"
        when "Boolean", "TrueClass", "FalseClass" then "boolean"
        else "string"
        end
      end
    end

    # Subclasses must implement #call with keyword args matching parameters.
    def call(**kwargs)
      raise NotImplementedError, "#{self.class}#call not implemented"
    end
  end
end
