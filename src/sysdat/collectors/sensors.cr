# src/sysdat/collectors/sensors.cr
module Sysdat
  enum SensorKind
    Temperature
    Fan
    Voltage
  end

  HWMON_SENSORS = {
    {SensorKind::Temperature, "temp", "Temp",    1000.0},
    {SensorKind::Fan,         "fan",  "Fan",     1.0},
    {SensorKind::Voltage,     "in",   "Voltage", 1000.0},
  }

  HWMON_SENSOR_LIMIT = 10
  HWMON_PROBE_FLOOR  =  5

  record Sensor,
    label : String,
    kind  : SensorKind,
    value : Float64 do
    include JSON::Serializable
  end

  record HwmonChip,
    name    : String,
    sensors : Array(Sensor) do
    include JSON::Serializable
  end

  def self.hwmon : Array(HwmonChip)
    SysFS.children("/sys/class/hwmon").compact_map do |entry|
      next unless entry.starts_with?("hwmon")

      base    = "/sys/class/hwmon/#{entry}"
      sensors = read_hwmon_sensors(base)
      next if sensors.empty?

      HwmonChip.new(name: SysFS.read_line("#{base}/name") || entry, sensors: sensors)
    end
  end

  private def self.read_hwmon_sensors(base : String) : Array(Sensor)
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
end
