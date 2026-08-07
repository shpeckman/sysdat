# src/sysdat/collectors/cpu.cr
module Sysdat
  record ThermalZone,
    kind    : String,
    celsius : Float64 do
    include JSON::Serializable
  end

  record CPU,
    model_name     : String,
    flags          : Array(String),
    logical_cores  : Int32,
    physical_cores : Int32,
    base_mhz       : Float64,
    cache_kb       : Int32,
    core_mhz       : Array(Float64),
    core_governors : Array(String),
    thermal_zones  : Array(ThermalZone) do
    include JSON::Serializable
  end

  record CPUTimes,
    user    : UInt64,
    nice    : UInt64,
    system  : UInt64,
    idle    : UInt64,
    iowait  : UInt64,
    irq     : UInt64,
    softirq : UInt64,
    steal   : UInt64 do
    include JSON::Serializable

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
    cores : Array(CPUTimes) do
    include JSON::Serializable
  end

  record KernelStats,
    boot_time        : Time,
    context_switches : UInt64,
    interrupts       : UInt64,
    processes_forked : UInt64,
    procs_running    : UInt64,
    procs_blocked    : UInt64 do
    include JSON::Serializable

    @[JSON::Field(converter: Time::EpochConverter)]
    @boot_time : Time
  end

  record Interrupt,
    irq    : String,
    counts : Array(UInt64),
    kind   : String,
    action : String do
    include JSON::Serializable

    def total : UInt64
      counts.reduce(0_u64) { |sum, value| sum + value }
    end
  end

  class CPUSampler
    @previous : CPUStats

    def initialize
      @previous = Sysdat.cpu_stats
    end

    def initialize(@previous : CPUStats)
    end

    def sample : Float64
      current   = Sysdat.cpu_stats
      usage     = current.total.usage_since(@previous.total)
      @previous = current
      usage
    end

    def sample_per_core : Array(Float64)
      current = Sysdat.cpu_stats
      usage = Array(Float64).new(current.cores.size) do |index|
        previous_core = @previous.cores[index]?
        previous_core ? current.cores[index].usage_since(previous_core) : 0.0
      end
      @previous = current
      usage
    end
  end

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
        total = Parsers.parse_cpu_times(fields)
      elsif label.size > 3 && label[3].ascii_number?
        cores << Parsers.parse_cpu_times(fields)
      end
    end
    raise Error.new("/proc/stat is unavailable") unless available

    CPUStats.new(total, cores)
  end

  def self.kernel_stats : KernelStats
    boot_time        = Time.unix(0)
    context_switches = 0_u64
    interrupts       = 0_u64
    processes_forked = 0_u64
    procs_running    = 0_u64
    procs_blocked    = 0_u64

    available = SysFS.read_lines("/proc/stat") do |line|
      key, separator, rest = line.partition(' ')
      next if separator.empty?
      rest = rest.strip

      case key
      when "btime"
        rest.to_i64?.try { |seconds| boot_time = Time.unix(seconds) }
      when "ctxt"
        context_switches = rest.to_u64? || 0_u64
      when "intr"
        interrupts = rest.partition(' ')[0].to_u64? || 0_u64
      when "processes"
        processes_forked = rest.to_u64? || 0_u64
      when "procs_running"
        procs_running = rest.to_u64? || 0_u64
      when "procs_blocked"
        procs_blocked = rest.to_u64? || 0_u64
      end
    end
    raise Error.new("/proc/stat is unavailable") unless available

    KernelStats.new(
      boot_time: boot_time,
      context_switches: context_switches,
      interrupts: interrupts,
      processes_forked: processes_forked,
      procs_running: procs_running,
      procs_blocked: procs_blocked,
    )
  end

  def self.interrupts : Array(Interrupt)
    interrupts = [] of Interrupt
    cpu_count  = 0

    SysFS.read_lines("/proc/interrupts") do |line|
      fields = line.split
      next if fields.empty?

      unless fields[0].ends_with?(':')
        cpu_count = fields.count(&.starts_with?("CPU"))
        next
      end

      irq    = fields[0].rchop(':')
      counts = [] of UInt64
      index  = 1
      while index <= cpu_count && index < fields.size
        counts << (fields[index].to_u64? || 0_u64)
        index += 1
      end

      kind   = fields[index]? || ""
      action = index + 1 < fields.size ? fields[(index + 1)..].join(' ') : ""

      interrupts << Interrupt.new(irq: irq, counts: counts, kind: kind, action: action)
    end

    interrupts
  end
end
