# src/sysdat/collectors/sensors.cr
module Sysdat::Sensors
  enum Kind
    Temperature
    Fan
    Voltage
  end

  HWMON_SENSORS = {
    {Kind::Temperature, "temp", "Temp",    1000.0},
    {Kind::Fan,         "fan",  "Fan",     1.0},
    {Kind::Voltage,     "in",   "Voltage", 1000.0},
  }

  HWMON_SENSOR_LIMIT = 10
  HWMON_PROBE_FLOOR  =  5

  record Sensor,
    label : String,
    kind  : Kind,
    value : Float64 do
    include JSON::Serializable
  end

  record Chip,
    name    : String,
    sensors : Array(Sensor) do
    include JSON::Serializable
  end

  class Collector
    include Sysdat::Collector(Array(Chip))

    def collect : Array(Chip)
      SysFS.children("/sys/class/hwmon").compact_map do |entry|
        next unless entry.starts_with?("hwmon")

        base    = "/sys/class/hwmon/#{entry}"
        sensors = Sensors.read_hwmon_sensors(base)
        next if sensors.empty?

        Chip.new(name: SysFS.read_line("#{base}/name") || entry, sensors: sensors)
      end
    end
  end

  protected def self.read_hwmon_sensors(base : String) : Array(Sensor)
    sensors = [] of Sensor

    (1..HWMON_SENSOR_LIMIT).each do |index|
      found = false

      HWMON_SENSORS.each do |(kind, prefix, label_prefix, scale)|
        value = SysFS.read_int("#{base}/#{prefix}#{index}_input")
        next unless value

        sensors << Sensor.new(
          label: SysFS.read_line("#{base}/#{prefix}#{index}_label") || "#{label_prefix} #{index}",
          kind: kind,
          value: value / scale,
        )
        found = true
      end

      break if !found && index > HWMON_PROBE_FLOOR
    end

    sensors
  end

  class Facade
    def initialize(@system : Sysdat::System)
    end

    def hwmon : Array(Chip)
      Collector.new.collect
    end
  end
end
