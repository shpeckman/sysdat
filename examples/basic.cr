# examples/basic.cr
require "colorize"
require "../src/sysdat"

module Report
  extend self

  LABEL_WIDTH = 22

  def header(title : String) : Nil
    puts
    puts title.upcase.colorize.light_cyan.bold
    puts ("─" * 60).colorize.dark_gray
  end

  def sub(title : String) : Nil
    puts "  #{title}".colorize.cyan
  end

  def field(label : String, value : String, indent : Int32 = 2) : Nil
    padding = " " * indent
    key     = "#{label}:".ljust(LABEL_WIDTH).colorize.light_gray
    puts "#{padding}#{key}#{value}"
  end

  def pad(value : String, width : Int32) : String
    "#{value.ljust(width)} "
  end

  def yes_no(value : Bool) : String
    value ? "yes".colorize.green.to_s : "no".colorize.red.to_s
  end

  def bytes(value : Int) : String
    Sysdat::Format.bytes(value).colorize.white.to_s
  end

  def hertz(mhz : Float64) : String
    Sysdat::Format.hertz(mhz).colorize.white.to_s
  end

  def span(value : Time::Span) : String
    total = value.total_seconds.to_i64
    days  = total // 86_400
    hours = (total % 86_400) // 3_600
    mins  = (total % 3_600) // 60
    secs  = total % 60
    parts = [] of String
    parts << "#{days}d" if days > 0
    parts << "#{hours}h" if hours > 0 || days > 0
    parts << "#{mins}m" if mins > 0 || hours > 0 || days > 0
    parts << "#{secs}s"
    parts.join(' ')
  end

  def percent(value : Float64) : String
    color = case value
            when .>= 90.0 then :red
            when .>= 70.0 then :yellow
            else               :green
            end
    "#{value.round(1)}%".colorize(color).to_s
  end
end

system = Sysdat.open

os = system.os.info
Report.header("operating system")
Report.field("hostname", os.hostname.colorize.white.bold.to_s)
Report.field("kernel", "#{os.sysname} #{os.release}")
Report.field("architecture", os.machine)
Report.field("distribution", os.distro.pretty_name.empty? ? os.distro.name : os.distro.pretty_name)
Report.field("distro id", os.distro.id_like.empty? ? os.distro.id : "#{os.distro.id} (like #{os.distro.id_like.join(", ")})")
Report.field("version", os.distro.version.presence || os.distro.version_id)
Report.field("uptime", Report.span(os.uptime))
Report.field("load average", os.load_average.map(&.round(2)).join("  "))
Report.field("processes", "#{os.processes_running} running / #{os.processes_total} total")

kernel = system.kernel.info
kstats = system.kernel.stats
Report.header("kernel")
Report.field("command line", kernel.command_line)
Report.field("entropy avail", kernel.entropy_avail.to_s)
Report.field("pid max", kernel.pid_max.to_s)
Report.field("threads max", kernel.threads_max.to_s)
Report.field("overcommit", kernel.overcommit.to_s)
Report.field("swappiness", kernel.swappiness.to_s)
Report.field("boot time", kstats.boot_time.to_local.to_s("%Y-%m-%d %H:%M:%S"))
Report.field("context switches", kstats.context_switches.to_s)
Report.field("forks", kstats.processes_forked.to_s)
if kernel.taint.tainted?
  Report.field("taint", "#{kernel.taint.value} [#{kernel.taint.letters}]".colorize.yellow.to_s)
  kernel.taint.flags.each do |flag|
    puts "    #{flag.letter} bit #{flag.bit}: #{flag.description}".colorize.dark_gray
  end
else
  Report.field("taint", "clean".colorize.green.to_s)
end

cpu = system.cpu.info
Report.header("cpu")
Report.field("model", cpu.model_name.colorize.white.bold.to_s)
Report.field("microcode", cpu.microcode.presence || "unknown")
Report.field("cores", "#{cpu.physical_cores} physical / #{cpu.logical_cores} logical")
Report.field("base clock", Report.hertz(cpu.base_mhz))
Report.field("cache", "#{cpu.cache_kb} KB")
governors = cpu.core_governors.tally
Report.field("governors", governors.map { |name, count| "#{name} ×#{count}" }.join(", "))
cpu.thermal_zones.each do |zone|
  next if zone.kind.empty?
  Report.field("thermal #{zone.kind}", "#{zone.celsius.round(1)} °C")
end

Report.sub("topology")
system.cpu.topology.each do |package|
  location = String.build do |io|
    io << "package #{package.physical_package_id}"
    package.die_id.try { |id| io << " die #{id}" }
    package.cluster_id.try { |id| io << " cluster #{id}" }
    io << " — #{package.cores.size} cores, #{package.thread_count} threads"
  end
  puts "    #{location}".colorize.white
  package.cores.each do |core|
    smt  = core.smt? ? " (SMT)".colorize.magenta.to_s : ""
    cpus = core.threads.map { |thread| "cpu#{thread.processor} @ #{thread.core_mhz.round.to_i} MHz" }
    puts "      core #{core.core_id}#{smt}: #{cpus.join(", ")}".colorize.dark_gray
  end
end

vulnerabilities = system.cpu.vulnerabilities
unless vulnerabilities.empty?
  Report.sub("vulnerabilities")
  vulnerabilities.each do |vuln|
    color = vuln.vulnerable? ? :red : (vuln.mitigated? ? :green : :yellow)
    puts "    #{Report.pad(vuln.name, 26)}#{vuln.status.colorize(color)}"
  end
end

frequency_stats = system.cpu.frequency_stats
unless frequency_stats.empty?
  Report.sub("frequency residency (cpu0)")
  if first = frequency_stats.first?
    total = first.total
    first.buckets.sort_by { |bucket| -bucket.time_ticks.to_i64 }.first(6).each do |bucket|
      share = total.total_seconds > 0 ? 100.0 * bucket.time.total_seconds / total.total_seconds : 0.0
      label = Report.pad(Sysdat::Format.hertz(bucket.khz / 1000.0), 10)
      puts "    #{label}#{Report.percent(share)}".colorize.dark_gray
    end
    Report.field("transitions", first.transitions.to_s, indent: 4)
  end
end

mem = system.memory.read
Report.header("memory")
Report.field("total", Report.bytes(mem.total))
Report.field("used", "#{Report.bytes(mem.used)}  (#{Report.percent(mem.total > 0 ? 100.0 * mem.used / mem.total : 0.0)})")
Report.field("available", Report.bytes(mem.available))
Report.field("cached", Report.bytes(mem.cached))
Report.field("buffers", Report.bytes(mem.buffers))
Report.field("swap", "#{Report.bytes(mem.swap_used)} / #{Report.bytes(mem.swap_total)}")
Report.field("committed", "#{Report.bytes(mem.committed_as)} / #{Report.bytes(mem.commit_limit)}")

if pressure = system.pressure.read
  Report.header("pressure stall")
  {"cpu some" => pressure.cpu_some, "memory some" => pressure.memory_some,
   "memory full" => pressure.memory_full, "io some" => pressure.io_some,
   "io full" => pressure.io_full}.each do |label, metric|
    next unless metric
    Report.field(label, "avg10 #{metric.avg10}  avg60 #{metric.avg60}  avg300 #{metric.avg300}")
  end
end

Report.header("storage")
Report.sub("mounts")
system.storage.mounts.each do |mount|
  used  = mount.total_bytes - mount.free_bytes
  share = mount.total_bytes > 0 ? 100.0 * used / mount.total_bytes : 0.0
  ro    = mount.read_only? ? " ro".colorize.yellow.to_s : ""
  puts "    #{Report.pad(mount.mount_point, 40)}#{Report.pad(mount.fs_type, 8)}#{Report.bytes(used)} / #{Report.bytes(mount.total_bytes)}  (#{Report.percent(share)})#{ro}"
end

block_devices = system.storage.block_devices
unless block_devices.empty?
  Report.sub("block devices")
  block_devices.each do |device|
    kind = device.rotational ? "HDD" : "SSD"
    puts "    #{Report.pad(device.name, 10)}#{Report.pad(Sysdat::Format.bytes(device.size_bytes), 12)}#{kind}  #{device.model}".colorize.white
    device.partitions.each do |partition|
      puts "      #{Report.pad(partition.name, 12)}#{Report.bytes(partition.size_bytes)}".colorize.dark_gray
    end
  end
end

swaps = system.storage.swaps
unless swaps.empty?
  Report.sub("swap")
  swaps.each do |swap|
    puts "    #{Report.pad(swap.path, 24)}#{Report.bytes(swap.used_bytes)} / #{Report.bytes(swap.size_bytes)}  prio #{swap.priority}"
  end
end

Report.header("network")
Report.sub("interfaces")
system.network.interfaces.each do |iface|
  state = iface.up? ? iface.operstate.colorize.green.to_s : iface.operstate.colorize.red.to_s
  puts "    #{Report.pad(iface.name, 12)}#{state}  #{iface.mac_address}"
  iface.addresses.each do |address|
    puts "      #{Report.pad(address.family, 6)}#{address.address}".colorize.dark_gray
  end
  puts "      rx #{Report.bytes(iface.rx_bytes)}  tx #{Report.bytes(iface.tx_bytes)}".colorize.dark_gray
end

wifi = system.network.wifi
unless wifi.empty?
  Report.sub("wifi")
  wifi.each do |device|
    Report.field(device.name, "quality #{device.link_quality}  signal #{device.signal_dbm} dBm", indent: 4)
  end
end

routes = system.network.routes
unless routes.empty?
  Report.sub("routes")
  routes.first(8).each do |route|
    puts "    #{Report.pad(route.destination, 18)}via #{Report.pad(route.gateway, 16)}#{route.interface}  metric #{route.metric}".colorize.dark_gray
  end
end

gpus = system.graphics.gpus
unless gpus.empty?
  Report.header("graphics")
  gpus.each do |gpu|
    Report.field(gpu.name, "#{gpu.vendor}  #{Report.hertz(gpu.core_mhz)}")
    if gpu.vram_total_mb > 0
      Report.field("  vram", "#{gpu.vram_used_mb} / #{gpu.vram_total_mb} MB", indent: 4)
    end
    gpu.busy_percent.try { |busy| Report.field("  busy", Report.percent(busy.to_f), indent: 4) }
  end
  system.graphics.displays.select(&.connected).each do |display|
    Report.field(display.name, display.resolution.presence || "connected", indent: 4)
  end
end

sensors = system.sensors.hwmon
unless sensors.empty?
  Report.header("sensors")
  sensors.each do |chip|
    Report.sub(chip.name)
    chip.sensors.each do |sensor|
      unit = case sensor.kind
             in Sysdat::Sensors::Kind::Temperature then "°C"
             in Sysdat::Sensors::Kind::Fan         then "rpm"
             in Sysdat::Sensors::Kind::Voltage     then "V"
             end
      puts "    #{Report.pad(sensor.label, 20)}#{sensor.value.round(2)} #{unit}".colorize.dark_gray
    end
  end
end

supplies = system.power.supplies
unless supplies.empty?
  Report.header("power")
  supplies.each do |supply|
    Report.sub("#{supply.name} (#{supply.kind})")
    Report.field("status", supply.status, indent: 4)
    supply.capacity_percent.try { |capacity| Report.field("capacity", Report.percent(capacity.to_f), indent: 4) }
    supply.health_percent.try { |health| Report.field("health", "#{health}%", indent: 4) }
    supply.cycle_count.try { |cycles| Report.field("cycles", cycles.to_s, indent: 4) }
    supply.time_remaining.try { |remaining| Report.field("time remaining", Report.span(remaining), indent: 4) }
  end
end

host = system.host.info
Report.header("host")
Report.field("virtual machine", host.virtual_machine? ? host.virtual_machine.to_s : Report.yes_no(false))
Report.field("container", host.container? ? host.container.to_s : Report.yes_no(false))
users = system.host.users
unless users.empty?
  Report.sub("logged in")
  users.each do |user|
    puts "    #{Report.pad(user.name, 16)}#{Report.pad(user.tty, 12)}#{user.login_time.to_local.to_s("%Y-%m-%d %H:%M")}".colorize.dark_gray
  end
end

fds     = system.limits.file_descriptors
threads = system.limits.threads
Report.header("limits")
Report.field("open fds", "#{fds.allocated} / #{fds.maximum}")
Report.field("pid max", threads.pid_max.to_s)
Report.field("threads max", threads.threads_max.to_s)

config = system.kernel.config
unless config.empty?
  Report.header("kernel config")
  Report.field("entries", config.size.to_s)
  {"CONFIG_PREEMPT" => nil, "CONFIG_HZ" => nil, "CONFIG_SMP" => nil,
   "CONFIG_MODULES" => nil, "CONFIG_CGROUPS" => nil}.each_key do |key|
    config[key]?.try { |value| Report.field(key.lchop("CONFIG_"), value) }
  end
end

puts
