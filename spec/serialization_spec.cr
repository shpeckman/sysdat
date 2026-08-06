# spec/serialization_spec.cr
require "./spec_helper"

private record SpanHolder, span : Time::Span do
  include JSON::Serializable

  @[JSON::Field(converter: Sysdat::SpanConverter)]
  @span : Time::Span
end

private record NilableSpanHolder, span : Time::Span? do
  include JSON::Serializable

  @[JSON::Field(converter: Sysdat::NilableSpanConverter)]
  @span : Time::Span?
end

private record LoadHolder, values : Tuple(Float64, Float64, Float64) do
  include JSON::Serializable

  @[JSON::Field(converter: Sysdat::LoadAverageConverter)]
  @values : Tuple(Float64, Float64, Float64)
end

describe "Sysdat serialization" do
  describe Sysdat::SpanConverter do
    it "serializes a span as integer nanoseconds and round-trips" do
      original = SpanHolder.new(Time::Span.new(seconds: 3, nanoseconds: 500_000_000))
      json     = original.to_json
      json.should eq(%({"span":3500000000}))
      SpanHolder.from_json(json).span.should eq(original.span)
    end
  end

  describe Sysdat::NilableSpanConverter do
    it "round-trips a present span" do
      original = NilableSpanHolder.new(Time::Span.new(seconds: 2))
      NilableSpanHolder.from_json(original.to_json).span.should eq(original.span)
    end

    it "round-trips a nil span" do
      NilableSpanHolder.from_json(%({"span":null})).span.should be_nil
    end
  end

  describe Sysdat::LoadAverageConverter do
    it "serializes a load average as an array and round-trips" do
      original = LoadHolder.new({0.5, 1.0, 1.5})
      json     = original.to_json
      json.should eq(%({"values":[0.5,1.0,1.5]}))
      LoadHolder.from_json(json).values.should eq(original.values)
    end
  end

  describe "Sysdat.snapshot" do
    it "produces JSON that deserializes back into an equivalent snapshot" do
      snapshot = Sysdat.snapshot
      json     = snapshot.to_json
      restored = Sysdat::Snapshot.from_json(json)

      restored.os.uptime.should eq(snapshot.os.uptime)
      restored.os.load_average.should eq(snapshot.os.load_average)
      restored.kernel_stats.boot_time.should eq(snapshot.kernel_stats.boot_time)
      restored.memory.total.should eq(snapshot.memory.total)
      restored.cpu.logical_cores.should eq(snapshot.cpu.logical_cores)
      restored.interfaces.size.should eq(snapshot.interfaces.size)
    end
  end
end
