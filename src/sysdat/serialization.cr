# src/sysdat/serialization.cr
require "json"

module Sysdat
  module SpanConverter
    def self.to_json(value : Time::Span, builder : JSON::Builder) : Nil
      builder.number(value.total_nanoseconds.to_i64)
    end

    def self.from_json(pull : JSON::PullParser) : Time::Span
      Time::Span.new(nanoseconds: pull.read_int)
    end
  end

  module NilableSpanConverter
    def self.to_json(value : Time::Span?, builder : JSON::Builder) : Nil
      if value
        builder.number(value.total_nanoseconds.to_i64)
      else
        builder.null
      end
    end

    def self.from_json(pull : JSON::PullParser) : Time::Span?
      return pull.read_null if pull.kind.null?
      Time::Span.new(nanoseconds: pull.read_int)
    end
  end

  module LoadAverageConverter
    def self.to_json(value : Tuple(Float64, Float64, Float64), builder : JSON::Builder) : Nil
      builder.array do
        builder.number(value[0])
        builder.number(value[1])
        builder.number(value[2])
      end
    end

    def self.from_json(pull : JSON::PullParser) : Tuple(Float64, Float64, Float64)
      values = StaticArray(Float64, 3).new(0.0)
      index  = 0
      pull.read_array do
        values[index] = pull.read_float if index < 3
        index += 1
      end
      {values[0], values[1], values[2]}
    end
  end
end
