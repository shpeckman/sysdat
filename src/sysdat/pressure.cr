# src/sysdat/pressure.cr
module Sysdat
  struct PressureMetric
    getter avg10 : Float64
    getter avg60 : Float64
    getter avg300 : Float64
    getter total : Time::Span

    def initialize(@avg10, @avg60, @avg300, @total)
    end
  end

  struct Pressure
    getter cpu_some : PressureMetric?
    getter memory_some : PressureMetric?
    getter memory_full : PressureMetric?
    getter io_some : PressureMetric?
    getter io_full : PressureMetric?

    def initialize(@cpu_some, @memory_some, @memory_full, @io_some, @io_full)
    end
  end

  def self.pressure : Pressure?
    cpu = read_pressure("/proc/pressure/cpu")
    memory = read_pressure("/proc/pressure/memory")
    io = read_pressure("/proc/pressure/io")
    return nil if cpu.empty? && memory.empty? && io.empty?

    Pressure.new(
      cpu_some: cpu["some"]?,
      memory_some: memory["some"]?,
      memory_full: memory["full"]?,
      io_some: io["some"]?,
      io_full: io["full"]?,
    )
  end

  private def self.read_pressure(path : String) : Hash(String, PressureMetric)
    metrics = {} of String => PressureMetric

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

      metrics[scope] = PressureMetric.new(
        avg10: values["avg10"],
        avg60: values["avg60"],
        avg300: values["avg300"],
        total: span_from_nanoseconds((values["total"] * 1_000.0).to_i64),
      )
    end

    metrics
  end
end
