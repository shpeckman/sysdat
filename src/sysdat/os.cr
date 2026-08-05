# src/sysdat/os.cr
module Sysdat
  struct OS
    getter sysname : String
    getter release : String
    getter version : String
    getter machine : String
    getter hostname : String
    getter uptime : Time::Span
    getter load_average : Tuple(Float64, Float64, Float64)
    getter processes_total : Int32
    getter processes_running : Int32

    def initialize(@sysname, @release, @version, @machine, @hostname, @uptime,
                   @load_average, @processes_total, @processes_running)
    end
  end

  def self.os : OS
    uts = uninitialized LibSys::UtsName
    raise Error.new("uname failed") unless LibSys.uname(pointerof(uts)) == 0

    load_average = {0.0, 0.0, 0.0}
    processes_total = 0
    processes_running = 0

    if line = SysFS.read_line("/proc/loadavg")
      fields = line.split
      load_average = {
        fields[0]?.try(&.to_f?) || 0.0,
        fields[1]?.try(&.to_f?) || 0.0,
        fields[2]?.try(&.to_f?) || 0.0,
      }
      if entities = fields[3]?
        running, _, total = entities.partition('/')
        processes_running = running.to_i? || 0
        processes_total = total.to_i? || 0
      end
    end

    uptime_seconds = SysFS.read_line("/proc/uptime").try(&.split.first?).try(&.to_f?) || 0.0

    hostname = begin
      System.hostname
    rescue
      SysFS.string_from(uts.nodename)
    end

    OS.new(
      sysname: SysFS.string_from(uts.sysname),
      release: SysFS.string_from(uts.release),
      version: SysFS.string_from(uts.version),
      machine: SysFS.string_from(uts.machine),
      hostname: hostname,
      uptime: span_from_nanoseconds((uptime_seconds * 1_000_000_000.0).to_i64),
      load_average: load_average,
      processes_total: processes_total,
      processes_running: processes_running,
    )
  end
end
