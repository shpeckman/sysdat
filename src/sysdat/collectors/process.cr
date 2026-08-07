# src/sysdat/collectors/process.cr
module Sysdat
  enum ProcessSort
    CPU
    Memory
    PID
  end

  record ProcessIO,
    read_chars  : UInt64,
    write_chars : UInt64,
    read_bytes  : UInt64,
    write_bytes : UInt64 do
    include JSON::Serializable
  end

  record Process,
    pid            : Int32,
    ppid           : Int32,
    uid            : UInt32,
    user           : String,
    name           : String,
    cmdline        : Array(String),
    state          : Char,
    utime          : UInt64,
    stime          : UInt64,
    threads        : Int32,
    fd_count       : UInt32,
    rss_bytes      : UInt64,
    vsize_bytes    : UInt64,
    memory_percent : Float64,
    io             : ProcessIO?,
    exe            : String?,
    cwd            : String? do
    include JSON::Serializable

    def cpu_ticks : UInt64
      utime + stime
    end
  end

  def self.processes(sort : ProcessSort = ProcessSort::CPU, limit : Int32? = nil, io : Bool = false) : Array(Process)
    page_size = self.page_size
    total_memory = begin
      memory.total
    rescue Error
      0_u64
    end

    user_cache = build_user_cache
    processes  = [] of Process

    begin
      Dir.each_child("/proc") do |entry|
        pid = entry.to_i?
        next unless pid && pid > 0

        begin
          if process = read_process(pid, page_size, total_memory, user_cache, io)
            processes << process
          end
        rescue IO::Error
          # Ignore failures for individual processes (e.g., vanished mid-read or permission denied)
        end
      end
    rescue IO::Error
      raise Error.new("/proc is unavailable")
    end

    case sort
    in ProcessSort::CPU
      processes.sort! { |a, b| b.cpu_ticks <=> a.cpu_ticks }
    in ProcessSort::Memory
      processes.sort! { |a, b| b.rss_bytes <=> a.rss_bytes }
    in ProcessSort::PID
      processes.sort_by!(&.pid)
    end

    limit ? processes.first(limit) : processes
  end

  private def self.page_size : UInt64
    value = LibSys.sysconf(LibSys::SC_PAGESIZE)
    value > 0 ? value.to_u64 : 4096_u64
  end

  private def self.build_user_cache : Hash(UInt32, String)
    cache = {} of UInt32 => String
    SysFS.read_lines("/etc/passwd") do |line|
      fields = line.split(':')
      if fields.size >= 3
        uid = fields[2].to_u32?(strict: false)
        cache[uid] = fields[0] if uid
      end
    end
    cache
  end

  private def self.read_process(pid : Int32, page_size : UInt64, total_memory : UInt64, user_cache : Hash(UInt32, String), want_io : Bool) : Process?
    content = SysFS.read_all("/proc/#{pid}/stat")
    return nil unless content

    open_paren  = content.index('(')
    close_paren = content.rindex(')')
    return nil unless open_paren && close_paren && close_paren > open_paren

    name   = content[open_paren + 1...close_paren]
    fields = content[(close_paren + 1)..].split
    return nil if fields.size < 22

    rss_pages = fields[21].to_i64? || 0_i64
    rss_bytes = (rss_pages > 0 ? rss_pages.to_u64 : 0_u64) * page_size

    uid = 0_u32
    SysFS.read_lines("/proc/#{pid}/status") do |line|
      if line.starts_with?("Uid:")
        uid_fields = line.split
        uid        = uid_fields[1]?.try(&.to_u32?(strict: false)) || 0_u32
        break
      end
    end

    cmdline_raw = SysFS.read_all("/proc/#{pid}/cmdline") || ""
    cmdline     = cmdline_raw.split('\0', remove_empty: true)

    Process.new(
      pid: pid,
      ppid: fields[1].to_i? || 0,
      uid: uid,
      user: user_cache[uid]? || uid.to_s,
      name: name,
      cmdline: cmdline,
      state: fields[0][0]? || '?',
      utime: fields[11].to_u64? || 0_u64,
      stime: fields[12].to_u64? || 0_u64,
      threads: fields[17].to_i? || 0,
      fd_count: SysFS.count_children("/proc/#{pid}/fd"),
      rss_bytes: rss_bytes,
      vsize_bytes: fields[20].to_u64? || 0_u64,
      memory_percent: total_memory > 0 ? 100.0 * rss_bytes / total_memory : 0.0,
      io: want_io ? read_process_io(pid) : nil,
      exe: SysFS.readlink("/proc/#{pid}/exe"),
      cwd: SysFS.readlink("/proc/#{pid}/cwd"),
    )
  end

  private def self.read_process_io(pid : Int32) : ProcessIO?
    values = Hash(String, UInt64).new(0_u64)
    found = SysFS.read_lines("/proc/#{pid}/io") do |line|
      key, separator, rest = line.partition(':')
      next if separator.empty?
      values[key] = rest.strip.to_u64? || 0_u64
    end
    return nil unless found

    ProcessIO.new(
      read_chars: values["rchar"],
      write_chars: values["wchar"],
      read_bytes: values["read_bytes"],
      write_bytes: values["write_bytes"],
    )
  end
end
