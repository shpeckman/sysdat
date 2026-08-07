# src/sysdat/collectors/os.cr
module Sysdat::OS
  OS_RELEASE_PATHS = {"/etc/os-release", "/usr/lib/os-release"}

  record Release,
    id               : String,
    id_like          : Array(String),
    name             : String,
    pretty_name      : String,
    version          : String,
    version_id       : String,
    version_codename : String,
    build_id         : String,
    fields           : Hash(String, String) do
    include JSON::Serializable
  end

  record Info,
    sysname           : String,
    release           : String,
    version           : String,
    machine           : String,
    hostname          : String,
    distro            : Release,
    uptime            : Time::Span,
    load_average      : Tuple(Float64, Float64, Float64),
    processes_total   : Int32,
    processes_running : Int32 do
    include JSON::Serializable

    @[JSON::Field(converter: Sysdat::SpanConverter)]
    @uptime : Time::Span

    @[JSON::Field(converter: Sysdat::LoadAverageConverter)]
    @load_average : Tuple(Float64, Float64, Float64)
  end

  class Collector
    include Sysdat::Collector(Info)

    def collect : Info
      uts = uninitialized LibSys::UtsName
      raise Error.new("uname failed") unless LibSys.uname(pointerof(uts)) == 0

      load_average      = {0.0, 0.0, 0.0}
      processes_total   = 0
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
          processes_total   = total.to_i? || 0
        end
      end

      uptime_seconds = SysFS.read_line("/proc/uptime").try(&.split.first?).try(&.to_f?) || 0.0

      hostname = begin
        ::System.hostname
      rescue
        SysFS.string_from(uts.nodename)
      end

      Info.new(
        sysname: SysFS.string_from(uts.sysname),
        release: SysFS.string_from(uts.release),
        version: SysFS.string_from(uts.version),
        machine: SysFS.string_from(uts.machine),
        hostname: hostname,
        distro: OS.read_release,
        uptime: Sysdat.span_from_nanoseconds((uptime_seconds * 1_000_000_000.0).to_i64),
        load_average: load_average,
        processes_total: processes_total,
        processes_running: processes_running,
      )
    end
  end

  def self.read_release : Release
    fields = {} of String => String

    OS_RELEASE_PATHS.each do |path|
      found = SysFS.read_lines(path) do |line|
        line = line.strip
        next if line.empty? || line.starts_with?('#')
        key, separator, value = line.partition('=')
        next if separator.empty?
        fields[key] = unquote(value)
      end
      break if found && !fields.empty?
    end

    Release.new(
      id: fields["ID"]? || "",
      id_like: (fields["ID_LIKE"]? || "").split(' ', remove_empty: true),
      name: fields["NAME"]? || "",
      pretty_name: fields["PRETTY_NAME"]? || "",
      version: fields["VERSION"]? || "",
      version_id: fields["VERSION_ID"]? || "",
      version_codename: fields["VERSION_CODENAME"]? || "",
      build_id: fields["BUILD_ID"]? || "",
      fields: fields,
    )
  end

  protected def self.unquote(value : String) : String
    value = value.strip
    if value.size >= 2 && (value.starts_with?('"') && value.ends_with?('"') ||
       value.starts_with?('\'') && value.ends_with?('\''))
      value = value[1...-1]
    end
    value.gsub(/\\(.)/) { $1 }
  end

  class Facade
    def initialize(@system : Sysdat::System)
    end

    def info : Info
      Collector.new.collect
    end

    def release : Release
      OS.read_release
    end
  end
end
