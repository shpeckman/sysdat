# src/sysdat/collectors/cpu.cr
module Sysdat::CPU
  record ThermalZone,
    kind    : String,
    celsius : Float64 do
    include JSON::Serializable
  end

  record Thread,
    processor : Int32,
    core_mhz  : Float64,
    governor  : String do
    include JSON::Serializable
  end

  record Core,
    core_id : Int32,
    threads : Array(Thread) do
    include JSON::Serializable

    def smt? : Bool
      threads.size > 1
    end
  end

  record Package,
    physical_package_id : Int32,
    die_id              : Int32?,
    cluster_id          : Int32?,
    cores               : Array(Core) do
    include JSON::Serializable

    def thread_count : Int32
      cores.sum(&.threads.size)
    end
  end

  record Vulnerability,
    name   : String,
    status : String do
    include JSON::Serializable

    def mitigated? : Bool
      status.starts_with?("Mitigation") || status.starts_with?("Not affected")
    end

    def vulnerable? : Bool
      status.starts_with?("Vulnerable")
    end
  end

  record FrequencyBucket,
    khz        : Int64,
    time_ticks : UInt64,
    time       : Time::Span do
    include JSON::Serializable

    @[JSON::Field(converter: Sysdat::SpanConverter)]
    @time : Time::Span
  end

  record FrequencyStats,
    processor   : Int32,
    transitions : UInt64,
    buckets     : Array(FrequencyBucket) do
    include JSON::Serializable

    def total : Time::Span
      buckets.reduce(Time::Span.zero) { |sum, bucket| sum + bucket.time }
    end
  end

  record Info,
    model_name     : String,
    flags          : Array(String),
    logical_cores  : Int32,
    physical_cores : Int32,
    base_mhz       : Float64,
    cache_kb       : Int32,
    microcode      : String,
    core_mhz       : Array(Float64),
    core_governors : Array(String),
    thermal_zones  : Array(ThermalZone) do
    include JSON::Serializable
  end

  record Times,
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

    def usage_since(previous : Times) : Float64
      total_delta = total.to_i64! - previous.total.to_i64!
      return 0.0 if total_delta <= 0
      idle_delta = idle_total.to_i64! - previous.idle_total.to_i64!
      100.0 * (total_delta - idle_delta) / total_delta
    end
  end

  record Stats,
    total : Times,
    cores : Array(Times) do
    include JSON::Serializable
  end

  class InfoCollector
    include Sysdat::Collector(Info)

    def collect : Info
      model_name       = ""
      flags            = [] of String
      logical_cores    = 0
      cache_kb         = 0
      cpuinfo_mhz      = 0.0
      microcode        = ""
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
        when "microcode"
          microcode = value if microcode.empty?
        when "flags"
          flags = value.split if flags.empty?
        when "physical id"
          value.to_i?.try { |id| sockets << id }
        when "cpu cores"
          value.to_i?.try { |count| cores_per_socket = count if count > cores_per_socket }
        end
      end
      raise Error.new("/proc/cpuinfo is unavailable") unless available

      if microcode.empty?
        microcode = SysFS.read_line("/sys/devices/system/cpu/cpu0/microcode/version") || ""
      end

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

      Info.new(
        model_name: model_name,
        flags: flags,
        logical_cores: logical_cores,
        physical_cores: physical_cores,
        base_mhz: base_mhz,
        cache_kb: cache_kb,
        microcode: microcode,
        core_mhz: core_mhz,
        core_governors: core_governors,
        thermal_zones: CPU.thermal_zones,
      )
    end
  end

  class StatsCollector
    include Sysdat::Collector(Stats)

    def collect : Stats
      total = Times.new(0_u64, 0_u64, 0_u64, 0_u64, 0_u64, 0_u64, 0_u64, 0_u64)
      cores = [] of Times

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

      Stats.new(total, cores)
    end
  end

  class TopologyCollector
    include Sysdat::Collector(Array(Package))

    private record ProbedThread,
      processor           : Int32,
      physical_package_id : Int32,
      die_id              : Int32?,
      cluster_id          : Int32?,
      core_id             : Int32,
      core_mhz            : Float64,
      governor            : String

    def collect : Array(Package)
      probed = [] of ProbedThread

      SysFS.children("/sys/devices/system/cpu").each do |entry|
        next unless entry.starts_with?("cpu")
        processor = entry.lchop("cpu").to_i?
        next unless processor

        base = "/sys/devices/system/cpu/#{entry}/topology"
        next unless File.exists?("#{base}/core_id")

        cpufreq = "/sys/devices/system/cpu/#{entry}/cpufreq"
        probed << ProbedThread.new(
          processor: processor,
          physical_package_id: (SysFS.read_int("#{base}/physical_package_id") || -1_i64).to_i32,
          die_id: SysFS.read_int("#{base}/die_id").try(&.to_i32),
          cluster_id: SysFS.read_int("#{base}/cluster_id").try(&.to_i32),
          core_id: (SysFS.read_int("#{base}/core_id") || 0_i64).to_i32,
          core_mhz: SysFS.read_int("#{cpufreq}/scaling_cur_freq").try { |khz| khz / 1000.0 } || 0.0,
          governor: SysFS.read_line("#{cpufreq}/scaling_governor") || "unknown",
        )
      end

      build_tree(probed)
    end

    private def build_tree(probed : Array(ProbedThread)) : Array(Package)
      packages = [] of Package

      probed.group_by(&.physical_package_id).each do |package_id, package_threads|
        sample = package_threads.first
        cores  = [] of Core

        package_threads.group_by(&.core_id).each do |core_id, core_threads|
          threads = core_threads.sort_by(&.processor).map do |thread|
            Thread.new(
              processor: thread.processor,
              core_mhz: thread.core_mhz,
              governor: thread.governor,
            )
          end
          cores << Core.new(core_id: core_id, threads: threads)
        end

        cores.sort_by!(&.core_id)
        packages << Package.new(
          physical_package_id: package_id,
          die_id: sample.die_id,
          cluster_id: sample.cluster_id,
          cores: cores,
        )
      end

      packages.sort_by!(&.physical_package_id)
    end
  end

  class VulnerabilitiesCollector
    include Sysdat::Collector(Array(Vulnerability))

    def collect : Array(Vulnerability)
      base = "/sys/devices/system/cpu/vulnerabilities"

      SysFS.children(base).compact_map do |entry|
        status = SysFS.read_line("#{base}/#{entry}")
        next unless status
        Vulnerability.new(name: entry, status: status.strip)
      end
    end
  end

  class FrequencyStatsCollector
    include Sysdat::Collector(Array(FrequencyStats))

    def collect : Array(FrequencyStats)
      stats = [] of FrequencyStats

      SysFS.children("/sys/devices/system/cpu").each do |entry|
        next unless entry.starts_with?("cpu")
        processor = entry.lchop("cpu").to_i?
        next unless processor

        base = "/sys/devices/system/cpu/#{entry}/cpufreq/stats"
        next unless File.exists?("#{base}/time_in_state")

        buckets = [] of FrequencyBucket
        SysFS.read_lines("#{base}/time_in_state") do |line|
          fields = line.split
          next if fields.size < 2
          khz  = fields[0].to_i64?
          time = fields[1].to_u64?
          next unless khz && time
          buckets << FrequencyBucket.new(
            khz: khz,
            time_ticks: time,
            time: CPU.ticks_to_span(time),
          )
        end

        stats << FrequencyStats.new(
          processor: processor,
          transitions: SysFS.read_int("#{base}/total_trans").try(&.to_u64) || 0_u64,
          buckets: buckets,
        )
      end

      stats.sort_by!(&.processor)
    end
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

  protected def self.ticks_to_span(ticks : UInt64) : Time::Span
    Sysdat.span_from_nanoseconds((ticks * 10_000_000).to_i64!)
  end

  class Facade
    def initialize(@system : Sysdat::System)
    end

    def info : Info
      InfoCollector.new.collect
    end

    def stats : Stats
      StatsCollector.new.collect
    end

    def thermal_zones : Array(ThermalZone)
      CPU.thermal_zones
    end

    def topology : Array(Package)
      TopologyCollector.new.collect
    end

    def vulnerabilities : Array(Vulnerability)
      VulnerabilitiesCollector.new.collect
    end

    def frequency_stats : Array(FrequencyStats)
      FrequencyStatsCollector.new.collect
    end

    def sampler : Sysdat::Sampler(Stats, Float64)
      collector = StatsCollector.new
      Sysdat::Sampler(Stats, Float64).new(
        -> { collector.collect },
        ->(previous : Stats, current : Stats, _interval : Time::Span) {
          current.total.usage_since(previous.total)
        }
      )
    end

    def core_sampler : Sysdat::Sampler(Stats, Array(Float64))
      collector = StatsCollector.new
      Sysdat::Sampler(Stats, Array(Float64)).new(
        -> { collector.collect },
        ->(previous : Stats, current : Stats, _interval : Time::Span) {
          Array(Float64).new(current.cores.size) do |index|
            previous_core = previous.cores[index]?
            previous_core ? current.cores[index].usage_since(previous_core) : 0.0
          end
        }
      )
    end
  end
end
