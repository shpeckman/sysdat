# src/sysdat/collectors/pressure.cr
module Sysdat::Pressure
  record Metric,
    avg10  : Float64,
    avg60  : Float64,
    avg300 : Float64,
    total  : Time::Span do
    include JSON::Serializable

    @[JSON::Field(converter: Sysdat::SpanConverter)]
    @total : Time::Span
  end

  record Info,
    cpu_some    : Metric?,
    memory_some : Metric?,
    memory_full : Metric?,
    io_some     : Metric?,
    io_full     : Metric? do
    include JSON::Serializable
  end

  class Collector
    include Sysdat::Collector(Info?)

    def collect : Info?
      cpu    = Pressure.read_pressure("/proc/pressure/cpu")
      memory = Pressure.read_pressure("/proc/pressure/memory")
      io     = Pressure.read_pressure("/proc/pressure/io")
      return nil if cpu.empty? && memory.empty? && io.empty?

      Info.new(
        cpu_some: cpu["some"]?,
        memory_some: memory["some"]?,
        memory_full: memory["full"]?,
        io_some: io["some"]?,
        io_full: io["full"]?,
      )
    end
  end

  protected def self.read_pressure(path : String) : Hash(String, Metric)
    metrics = {} of String => Metric

    SysFS.read_lines(path) do |line|
      fields = line.split
      next if fields.size < 2

      scope = fields[0]
      next unless scope == "some" || scope == "full"

      values = Hash(String, Float64).new(0.0)
      fields.skip(1).each do |field|
        key, separator, value = field.partition('=')
        next if separator.empty?
        values[key] = value.to_f?(strict: false) || 0.0
      end

      metrics[scope] = Metric.new(
        avg10: values["avg10"],
        avg60: values["avg60"],
        avg300: values["avg300"],
        total: Sysdat.span_from_nanoseconds((values["total"] * 1_000.0).to_i64),
      )
    end

    metrics
  end

  class Facade
    def initialize(@system : Sysdat::System)
    end

    def read : Info?
      Collector.new.collect
    end
  end
end
