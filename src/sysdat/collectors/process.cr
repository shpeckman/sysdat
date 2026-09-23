# src/sysdat/collectors/process.cr
module Sysdat::Process
  enum Sort
    CPU
    Memory
    PID
  end

  enum Seccomp
    Disabled
    Strict
    Filter
    Unknown

    def self.from_value(value : Int32) : Seccomp
      case value
      when 0 then Disabled
      when 1 then Strict
      when 2 then Filter
      else        Unknown
      end
    end
  end

  CAPABILITIES = {
    {0,  "CAP_CHOWN"},
    {1,  "CAP_DAC_OVERRIDE"},
    {2,  "CAP_DAC_READ_SEARCH"},
    {3,  "CAP_FOWNER"},
    {4,  "CAP_FSETID"},
    {5,  "CAP_KILL"},
    {6,  "CAP_SETGID"},
    {7,  "CAP_SETUID"},
    {8,  "CAP_SETPCAP"},
    {9,  "CAP_LINUX_IMMUTABLE"},
    {10, "CAP_NET_BIND_SERVICE"},
    {11, "CAP_NET_BROADCAST"},
    {12, "CAP_NET_ADMIN"},
    {13, "CAP_NET_RAW"},
    {14, "CAP_IPC_LOCK"},
    {15, "CAP_IPC_OWNER"},
    {16, "CAP_SYS_MODULE"},
    {17, "CAP_SYS_RAWIO"},
    {18, "CAP_SYS_CHROOT"},
    {19, "CAP_SYS_PTRACE"},
    {20, "CAP_SYS_PACCT"},
    {21, "CAP_SYS_ADMIN"},
    {22, "CAP_SYS_BOOT"},
    {23, "CAP_SYS_NICE"},
    {24, "CAP_SYS_RESOURCE"},
    {25, "CAP_SYS_TIME"},
    {26, "CAP_SYS_TTY_CONFIG"},
    {27, "CAP_MKNOD"},
    {28, "CAP_LEASE"},
    {29, "CAP_AUDIT_WRITE"},
    {30, "CAP_AUDIT_CONTROL"},
    {31, "CAP_SETFCAP"},
    {32, "CAP_MAC_OVERRIDE"},
    {33, "CAP_MAC_ADMIN"},
    {34, "CAP_SYSLOG"},
    {35, "CAP_WAKE_ALARM"},
    {36, "CAP_BLOCK_SUSPEND"},
    {37, "CAP_AUDIT_READ"},
    {38, "CAP_PERFMON"},
    {39, "CAP_BPF"},
    {40, "CAP_CHECKPOINT_RESTORE"},
  }

  record IO,
    read_chars  : UInt64,
    write_chars : UInt64,
    read_bytes  : UInt64,
    write_bytes : UInt64 do
    include JSON::Serializable
  end

  record Info,
    pid                        : Int32,
    ppid                       : Int32,
    uid                        : UInt32,
    user                       : String,
    name                       : String,
    cmdline                    : Array(String),
    state                      : Char,
    utime                      : UInt64,
    stime                      : UInt64,
    start_ticks                : UInt64,
    threads                    : Int32,
    fd_count                   : UInt32,
    rss_bytes                  : UInt64,
    vsize_bytes                : UInt64,
    memory_percent             : Float64,
    seccomp                    : Seccomp,
    no_new_privs               : Bool,
    voluntary_ctxt_switches    : UInt64,
    nonvoluntary_ctxt_switches : UInt64,
    io                         : IO?,
    exe                        : String?,
    cwd                        : String? do
    include JSON::Serializable

    def cpu_ticks : UInt64
      utime + stime
    end
  end

  record Stat,
    pid         : Int32,
    ppid        : Int32,
    uid         : UInt32,
    name        : String,
    state       : Char,
    utime       : UInt64,
    stime       : UInt64,
    start_ticks : UInt64,
    rss_bytes   : UInt64 do
    include JSON::Serializable

    def cpu_ticks : UInt64
      utime + stime
    end
  end

  record CapabilitySet,
    mask         : UInt64,
    capabilities : Array(String) do
    include JSON::Serializable

    def includes?(name : String) : Bool
      capabilities.includes?(name)
    end

    def full? : Bool
      Process::CAPABILITIES.all? { |(bit, _)| mask.bit(bit) == 1 }
    end

    def empty? : Bool
      mask == 0_u64
    end
  end

  record Capabilities,
    inheritable : CapabilitySet,
    permitted   : CapabilitySet,
    effective   : CapabilitySet,
    bounding    : CapabilitySet,
    ambient     : CapabilitySet do
    include JSON::Serializable
  end

  record Namespace,
    kind  : String,
    inode : UInt64 do
    include JSON::Serializable
  end

  record CGroup,
    hierarchy_id : Int32,
    controllers  : Array(String),
    path         : String do
    include JSON::Serializable

    def unified? : Bool
      hierarchy_id == 0 && controllers.empty?
    end
  end

  enum FDKind
    File
    Directory
    Socket
    Pipe
    AnonInode
    CharDevice
    Other
  end

  record FDGroup,
    kind   : FDKind,
    count  : UInt32,
    inodes : Array(UInt64) do
    include JSON::Serializable
  end

  record FDSummary,
    total  : UInt32,
    groups : Array(FDGroup) do
    include JSON::Serializable

    def sockets : Array(UInt64)
      groups.find(&.kind.socket?).try(&.inodes) || [] of UInt64
    end
  end

  record Details,
    pid          : Int32,
    cgroups      : Array(CGroup),
    unified_path : String?,
    namespaces   : Array(Namespace),
    capabilities : Capabilities,
    fds          : FDSummary do
    include JSON::Serializable
  end

  class Collector
    include Sysdat::Collector(Array(Info))

    def initialize(@sort : Sort = Sort::CPU, @limit : Int32? = nil, @io : Bool = false)
    end

    def collect : Array(Info)
      page_size = Process.page_size
      total_memory = begin
        Memory::Collector.new.collect.total
      rescue Error
        0_u64
      end

      user_cache = Process.build_user_cache
      processes  = [] of Info

      begin
        Dir.each_child("/proc") do |entry|
          pid = entry.to_i?
          next unless pid && pid > 0

          begin
            if process = Process.read_process(pid, page_size, total_memory, user_cache, @io)
              processes << process
            end
          rescue ::IO::Error
          end
        end
      rescue ::IO::Error
        raise Error.new("/proc is unavailable")
      end

      case @sort
      in Sort::CPU
        processes.sort! { |a, b| b.cpu_ticks <=> a.cpu_ticks }
      in Sort::Memory
        processes.sort! { |a, b| b.rss_bytes <=> a.rss_bytes }
      in Sort::PID
        processes.sort_by!(&.pid)
      end

      @limit ? processes.first(@limit.not_nil!) : processes
    end
  end

  class StatsCollector
    include Sysdat::Collector(Array(Stat))

    def collect : Array(Stat)
      page_size = Process.page_size
      stats     = [] of Stat

      begin
        Dir.each_child("/proc") do |entry|
          pid = entry.to_i?
          next unless pid && pid > 0

          begin
            if stat = Process.read_stat(pid, page_size)
              stats << stat
            end
          rescue ::IO::Error
          end
        end
      rescue ::IO::Error
        raise Error.new("/proc is unavailable")
      end

      stats
    end
  end

  private record ProcStatus,
    uid                        : UInt32,
    seccomp                    : Seccomp,
    no_new_privs               : Bool,
    voluntary_ctxt_switches    : UInt64,
    nonvoluntary_ctxt_switches : UInt64,
    cap_inheritable            : UInt64,
    cap_permitted              : UInt64,
    cap_effective              : UInt64,
    cap_bounding               : UInt64,
    cap_ambient                : UInt64

  private record StatLine,
    name   : String,
    fields : Array(String)

  protected def self.page_size : UInt64
    value = LibSys.sysconf(LibSys::SC_PAGESIZE)
    value > 0 ? value.to_u64 : 4096_u64
  end

  protected def self.build_user_cache : Hash(UInt32, String)
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

  protected def self.read_stat_line(pid : Int32) : StatLine?
    content = SysFS.read_all("/proc/#{pid}/stat")
    return nil unless content

    open_paren  = content.index('(')
    close_paren = content.rindex(')')
    return nil unless open_paren && close_paren && close_paren > open_paren

    fields = content[(close_paren + 1)..].split
    return nil if fields.size < 22

    StatLine.new(content[open_paren + 1...close_paren], fields)
  end

  protected def self.page_bytes(field : String, page_size : UInt64) : UInt64
    pages = field.to_i64? || 0_i64
    (pages > 0 ? pages.to_u64 : 0_u64) * page_size
  end

  protected def self.read_stat(pid : Int32, page_size : UInt64) : Stat?
    line = read_stat_line(pid)
    return nil unless line

    info = File.info?("/proc/#{pid}")
    return nil unless info

    fields = line.fields
    Stat.new(
      pid: pid,
      ppid: fields[1].to_i? || 0,
      uid: info.owner_id.to_u32? || 0_u32,
      name: line.name,
      state: fields[0][0]? || '?',
      utime: fields[11].to_u64? || 0_u64,
      stime: fields[12].to_u64? || 0_u64,
      start_ticks: fields[19].to_u64? || 0_u64,
      rss_bytes: page_bytes(fields[21], page_size),
    )
  end

  protected def self.read_status(pid : Int32) : ProcStatus
    uid                        = 0_u32
    seccomp                    = Seccomp::Unknown
    no_new_privs               = false
    voluntary_ctxt_switches    = 0_u64
    nonvoluntary_ctxt_switches = 0_u64
    cap_inheritable            = 0_u64
    cap_permitted              = 0_u64
    cap_effective              = 0_u64
    cap_bounding               = 0_u64
    cap_ambient                = 0_u64

    SysFS.read_lines("/proc/#{pid}/status") do |line|
      key, separator, rest = line.partition(':')
      next if separator.empty?
      rest = rest.strip

      case key
      when "Uid"
        uid = rest.split.first?.try(&.to_u32?(strict: false)) || 0_u32
      when "Seccomp"
        seccomp = Seccomp.from_value(rest.to_i? || -1)
      when "NoNewPrivs"
        no_new_privs = rest == "1"
      when "voluntary_ctxt_switches"
        voluntary_ctxt_switches = rest.to_u64? || 0_u64
      when "nonvoluntary_ctxt_switches"
        nonvoluntary_ctxt_switches = rest.to_u64? || 0_u64
      when "CapInh"
        cap_inheritable = rest.to_u64?(16) || 0_u64
      when "CapPrm"
        cap_permitted = rest.to_u64?(16) || 0_u64
      when "CapEff"
        cap_effective = rest.to_u64?(16) || 0_u64
      when "CapBnd"
        cap_bounding = rest.to_u64?(16) || 0_u64
      when "CapAmb"
        cap_ambient = rest.to_u64?(16) || 0_u64
      end
    end

    ProcStatus.new(
      uid: uid,
      seccomp: seccomp,
      no_new_privs: no_new_privs,
      voluntary_ctxt_switches: voluntary_ctxt_switches,
      nonvoluntary_ctxt_switches: nonvoluntary_ctxt_switches,
      cap_inheritable: cap_inheritable,
      cap_permitted: cap_permitted,
      cap_effective: cap_effective,
      cap_bounding: cap_bounding,
      cap_ambient: cap_ambient,
    )
  end

  protected def self.read_process(pid : Int32, page_size : UInt64, total_memory : UInt64, user_cache : Hash(UInt32, String), want_io : Bool) : Info?
    line = read_stat_line(pid)
    return nil unless line

    fields    = line.fields
    rss_bytes = page_bytes(fields[21], page_size)
    status    = read_status(pid)

    cmdline_raw = SysFS.read_all("/proc/#{pid}/cmdline") || ""
    cmdline     = cmdline_raw.split('\0', remove_empty: true)

    Info.new(
      pid: pid,
      ppid: fields[1].to_i? || 0,
      uid: status.uid,
      user: user_cache[status.uid]? || status.uid.to_s,
      name: line.name,
      cmdline: cmdline,
      state: fields[0][0]? || '?',
      utime: fields[11].to_u64? || 0_u64,
      stime: fields[12].to_u64? || 0_u64,
      start_ticks: fields[19].to_u64? || 0_u64,
      threads: fields[17].to_i? || 0,
      fd_count: SysFS.count_children("/proc/#{pid}/fd"),
      rss_bytes: rss_bytes,
      vsize_bytes: fields[20].to_u64? || 0_u64,
      memory_percent: total_memory > 0 ? 100.0 * rss_bytes / total_memory : 0.0,
      seccomp: status.seccomp,
      no_new_privs: status.no_new_privs,
      voluntary_ctxt_switches: status.voluntary_ctxt_switches,
      nonvoluntary_ctxt_switches: status.nonvoluntary_ctxt_switches,
      io: want_io ? read_process_io(pid) : nil,
      exe: SysFS.readlink("/proc/#{pid}/exe"),
      cwd: SysFS.readlink("/proc/#{pid}/cwd"),
    )
  end

  protected def self.read_process_io(pid : Int32) : IO?
    values = Hash(String, UInt64).new(0_u64)
    found = SysFS.read_lines("/proc/#{pid}/io") do |line|
      key, separator, rest = line.partition(':')
      next if separator.empty?
      values[key] = rest.strip.to_u64? || 0_u64
    end
    return nil unless found

    IO.new(
      read_chars: values["rchar"],
      write_chars: values["wchar"],
      read_bytes: values["read_bytes"],
      write_bytes: values["write_bytes"],
    )
  end

  def self.stat(pid : Int32) : Stat?
    read_stat(pid, page_size)
  rescue ::IO::Error
    nil
  end

  def self.details(pid : Int32) : Details?
    return nil unless File.exists?("/proc/#{pid}")

    status  = read_status(pid)
    cgroups = read_cgroups(pid)

    Details.new(
      pid: pid,
      cgroups: cgroups,
      unified_path: cgroups.find(&.unified?).try(&.path),
      namespaces: read_namespaces(pid),
      capabilities: build_capabilities(status),
      fds: read_fd_summary(pid),
    )
  end

  protected def self.decode_capabilities(mask : UInt64) : Array(String)
    CAPABILITIES.compact_map do |(bit, name)|
      name if mask.bit(bit) == 1
    end
  end

  protected def self.build_capabilities(status : ProcStatus) : Capabilities
    Capabilities.new(
      inheritable: CapabilitySet.new(status.cap_inheritable, decode_capabilities(status.cap_inheritable)),
      permitted: CapabilitySet.new(status.cap_permitted, decode_capabilities(status.cap_permitted)),
      effective: CapabilitySet.new(status.cap_effective, decode_capabilities(status.cap_effective)),
      bounding: CapabilitySet.new(status.cap_bounding, decode_capabilities(status.cap_bounding)),
      ambient: CapabilitySet.new(status.cap_ambient, decode_capabilities(status.cap_ambient)),
    )
  end

  protected def self.read_cgroups(pid : Int32) : Array(CGroup)
    cgroups = [] of CGroup

    SysFS.read_lines("/proc/#{pid}/cgroup") do |line|
      hierarchy, separator, rest = line.partition(':')
      next if separator.empty?

      controllers_field, controller_separator, path = rest.partition(':')
      next if controller_separator.empty?

      hierarchy_id = hierarchy.to_i? || 0
      controllers  = controllers_field.split(',', remove_empty: true)

      cgroups << CGroup.new(
        hierarchy_id: hierarchy_id,
        controllers: controllers,
        path: path,
      )
    end

    cgroups
  end

  protected def self.read_namespaces(pid : Int32) : Array(Namespace)
    namespaces = [] of Namespace

    SysFS.children("/proc/#{pid}/ns").each do |entry|
      target = SysFS.readlink("/proc/#{pid}/ns/#{entry}")
      next unless target

      open_bracket  = target.index('[')
      close_bracket = target.rindex(']')
      next unless open_bracket && close_bracket && close_bracket > open_bracket

      inode = target[(open_bracket + 1)...close_bracket].to_u64?
      next unless inode

      namespaces << Namespace.new(kind: entry, inode: inode)
    end

    namespaces
  end

  protected def self.read_fd_summary(pid : Int32) : FDSummary
    counts = Hash(FDKind, UInt32).new(0_u32)
    inodes = Hash(FDKind, Array(UInt64)).new { |hash, key| hash[key] = [] of UInt64 }
    total  = 0_u32

    begin
      Dir.each_child("/proc/#{pid}/fd") do |entry|
        target = SysFS.readlink("/proc/#{pid}/fd/#{entry}")
        next unless target

        total += 1
        kind, inode = classify_fd(target)
        counts[kind] += 1
        inode.try { |value| inodes[kind] << value }
      end
    rescue ::IO::Error
    end

    groups = counts.map do |kind, count|
      FDGroup.new(kind: kind, count: count, inodes: inodes[kind]? || [] of UInt64)
    end
    groups.sort_by!(&.kind.value)

    FDSummary.new(total: total, groups: groups)
  end

  protected def self.classify_fd(target : String) : Tuple(FDKind, UInt64?)
    if inode = anon_inode_number(target, "socket:[")
      {FDKind::Socket, inode}
    elsif inode = anon_inode_number(target, "pipe:[")
      {FDKind::Pipe, inode}
    elsif target.starts_with?("anon_inode:")
      {FDKind::AnonInode, nil}
    elsif target.starts_with?('/')
      classify_path(target)
    else
      {FDKind::Other, nil}
    end
  end

  protected def self.anon_inode_number(target : String, prefix : String) : UInt64?
    return nil unless target.starts_with?(prefix) && target.ends_with?(']')
    target[prefix.size...-1].to_u64?
  end

  protected def self.classify_path(target : String) : Tuple(FDKind, UInt64?)
    info = File.info?(target, follow_symlinks: false)
    return {FDKind::File, nil} unless info

    case info.type
    when .directory?        then {FDKind::Directory, nil}
    when .character_device? then {FDKind::CharDevice, nil}
    else                         {FDKind::File, nil}
    end
  end

  class Facade
    def initialize(@system : Sysdat::System)
    end

    def list(sort : Sort = Sort::CPU, limit : Int32? = nil, io : Bool = false) : Array(Info)
      Collector.new(sort, limit, io).collect
    end

    def stats : Array(Stat)
      StatsCollector.new.collect
    end

    def stat(pid : Int32) : Stat?
      Process.stat(pid)
    end

    def details(pid : Int32) : Details?
      Process.details(pid)
    end
  end
end
