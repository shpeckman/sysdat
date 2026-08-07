# src/sysdat/collectors/kernel.cr
module Sysdat::Kernel
  record Stats,
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

  record Info,
    command_line  : String,
    entropy_avail : UInt64,
    pid_max       : UInt64,
    threads_max   : UInt64,
    overcommit    : Int32,
    swappiness    : Int32 do
    include JSON::Serializable
  end

  class StatsCollector
    include Sysdat::Collector(Stats)

    def collect : Stats
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

      Stats.new(
        boot_time: boot_time,
        context_switches: context_switches,
        interrupts: interrupts,
        processes_forked: processes_forked,
        procs_running: procs_running,
        procs_blocked: procs_blocked,
      )
    end
  end

  class InfoCollector
    include Sysdat::Collector(Info)

    def collect : Info
      Info.new(
        command_line: SysFS.read_line("/proc/cmdline") || "",
        entropy_avail: SysFS.read_int("/proc/sys/kernel/random/entropy_avail").try(&.to_u64) || 0_u64,
        pid_max: SysFS.read_int("/proc/sys/kernel/pid_max").try(&.to_u64) || 0_u64,
        threads_max: SysFS.read_int("/proc/sys/kernel/threads-max").try(&.to_u64) || 0_u64,
        overcommit: (SysFS.read_int("/proc/sys/vm/overcommit_memory") || 0_i64).to_i32,
        swappiness: (SysFS.read_int("/proc/sys/vm/swappiness") || 0_i64).to_i32,
      )
    end
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

  class Facade
    def initialize(@system : Sysdat::System)
    end

    def info : Info
      InfoCollector.new.collect
    end

    def stats : Stats
      StatsCollector.new.collect
    end

    def interrupts : Array(Interrupt)
      Kernel.interrupts
    end
  end
end
