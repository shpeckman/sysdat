# src/sysdat/cpu.cr
module Sysdat
  record ThermalZone,
    kind    : String,
    celsius : Float64

  record CPU,
    model_name     : String,
    flags          : Array(String),
    logical_cores  : Int32,
    physical_cores : Int32,
    base_mhz       : Float64,
    cache_kb       : Int32,
    core_mhz       : Array(Float64),
    core_governors : Array(String),
    thermal_zones  : Array(ThermalZone)

  record CPUTimes,
    user    : UInt64,
    nice    : UInt64,
    system  : UInt64,
    idle    : UInt64,
    iowait  : UInt64,
    irq     : UInt64,
    softirq : UInt64,
    steal   : UInt64 do
    def idle_total : UInt64
      idle + iowait
    end

    def total : UInt64
      user + nice + system + idle_total + irq + softirq + steal
    end

    def usage_since(previous : CPUTimes) : Float64
      total_delta = total.to_i64! - previous.total.to_i64!
      return 0.0 if total_delta <= 0
      idle_delta = idle_total.to_i64! - previous.idle_total.to_i64!
      100.0 * (total_delta - idle_delta) / total_delta
    end
  end

  record CPUStats,
    total : CPUTimes,
    cores : Array(CPUTimes)

  def self.cpu : CPU
    model_name       = ""
    flags            = [] of String
    logical_cores    = 0
    cache_kb         = 0
    cpuinfo_mhz      = 0.0
    cores_per_socket = 0
    sockets          = Set(Int32).new

    available = SysFS.read_lines("/proc/cpuinfo") do |line|
      key, separator, value = line.partition(':')
      next if separator.empty?
      key   = key.strip
      value = value.strip

      case key
      when "processor"
        logical_cores += 1
      when "model name"
        model_name = value if model_name.empty?
      when "cpu MHz"
        cpuinfo_mhz = value.to_f?(strict: false) || 0.0 if cpuinfo_mhz.zero?
      when "cache size"
        cache_kb = value.to_i?(strict: false) || 0 if cache_kb.zero?
      when "flags"
        flags = value.split if flags.empty?
      when "physical id"
        value.to_i?.try { |id| sockets << id }
      when "cpu cores"
        value.to_i?.try { |count| cores_per_socket = count if count > cores_per_socket }
      end
    end
    raise Error.new("/proc/cpuinfo is unavailable") unless available

    physical_cores = cores_per_socket * sockets.size
    physical_cores = logical_cores if physical_cores.zero?

    base_mhz = SysFS.read_int("/sys/devices/system/cpu/cpu0/cpufreq/base_frequency")
      .try { |khz| khz / 1000.0 } || cpuinfo_mhz

    core_mhz = Array(Float64).new(logical_cores) do |index|
      khz = SysFS.read_int("/sys/devices/system/cpu/cpu#{index}/cpufreq/scaling_cur_freq")
      khz ? khz / 1000.0 : 0.0
    end

    core_governors = Array(String).new(logical_cores) do |index|
      SysFS.read_line("/sys/devices/system/cpu/cpu#{index}/cpufreq/scaling_governor") || "unknown"
    end

    CPU.new(
      model_name: model_name,
      flags: flags,
      logical_cores: logical_cores,
      physical_cores: physical_cores,
      base_mhz: base_mhz,
      cache_kb: cache_kb,
      core_mhz: core_mhz,
      core_governors: core_governors,
      thermal_zones: thermal_zones,
    )
  end

  def self.thermal_zones : Array(ThermalZone)
    zones = [] of ThermalZone
    index = 0

    loop do
      base = "/sys/class/thermal/thermal_zone#{index}"
      break unless File.exists?("#{base}/temp")
      if millidegrees = SysFS.read_int("#{base}/temp")
        zones << ThermalZone.new(
          kind: SysFS.read_line("#{base}/type") || "",
          celsius: millidegrees / 1000.0,
        )
      end
      index += 1
    end

    zones
  end

  def self.cpu_stats : CPUStats
    total = CPUTimes.new(0_u64, 0_u64, 0_u64, 0_u64, 0_u64, 0_u64, 0_u64, 0_u64)
    cores = [] of CPUTimes

    available = SysFS.read_lines("/proc/stat") do |line|
      next unless line.starts_with?("cpu")
      fields = line.split
      label  = fields[0]
      if label == "cpu"
        total = parse_cpu_times(fields)
      elsif label.size > 3 && label[3].ascii_number?
        cores << parse_cpu_times(fields)
      end
    end
    raise Error.new("/proc/stat is unavailable") unless available

    CPUStats.new(total, cores)
  end

  private def self.parse_cpu_times(fields : Array(String)) : CPUTimes
    values = StaticArray(UInt64, 8).new(0_u64)
    fields.each_with_index do |field, index|
      break if index > 8
      next if index.zero?
      values[index - 1] = field.to_u64? || 0_u64
    end

    CPUTimes.new(values[0], values[1], values[2], values[3],
      values[4], values[5], values[6], values[7])
  end
end
