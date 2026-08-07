# examples/live_demo.cr
require "../src/sysdat"

print "\e[?25l"
at_exit { print "\e[?25h" }

system = Sysdat.open

cpu_sampler     = system.cpu.sampler
core_sampler    = system.cpu.core_sampler
network_sampler = system.network.sampler
start_time      = Time.instant

# Run for 20 seconds
while (Time.instant - start_time).total_seconds < 20
  sleep 1.second

  print "\e[2J\e[H"

  os     = system.os.info
  limits = system.limits.file_descriptors
  puts "=== System Overview ==="
  puts "OS:       #{os.sysname} #{os.release}"
  puts "Uptime:   #{os.uptime}"
  puts "Load Avg: #{os.load_average}"
  puts "FDs:      #{limits.used} / #{limits.maximum}"
  puts ""

  cpu_usage  = cpu_sampler.sample
  core_usage = core_sampler.sample
  cpu_info   = system.cpu.info
  puts "=== CPU Usage ==="
  puts "Total:    #{cpu_usage.round(2)}%"

  core_usage.each_with_index do |usage, index|
    gov = cpu_info.core_governors[index]? || "unk"
    print "Core #{index.to_s.ljust(2)} (#{gov.chars.first(3).join}): #{usage.round(1).to_s.rjust(5)}%   "
    puts "" if index % 3 == 2
  end
  puts "" unless core_usage.size % 3 == 0
  puts ""

  mem         = system.memory.read
  mem_percent = mem.total > 0 ? (mem.used.to_f / mem.total * 100).round(2) : 0.0
  puts "=== Memory ==="
  puts "Used:     #{mem.used // 1048576} MB / #{mem.total // 1048576} MB (#{mem_percent}%)"

  swaps = system.storage.swaps
  if swaps.empty?
    puts "Swap:     #{mem.swap_total > 0 ? ((mem.swap_total - mem.swap_free) // 1048576) : 0} MB / #{mem.swap_total // 1048576} MB"
  else
    swaps.each do |swap|
      puts "Swap [#{swap.path}]: #{swap.used_bytes // 1048576} MB / #{swap.size_bytes // 1048576} MB"
    end
  end
  puts ""

  puts "=== Network (Rates) ==="
  rates = network_sampler.sample
  rates.each do |name, rate|
    rx_mb = (rate.rx_bytes_per_sec / 1_048_576).round(2)
    tx_mb = (rate.tx_bytes_per_sec / 1_048_576).round(2)

    next if rx_mb == 0 && tx_mb == 0 && name != "eth0" && name != "wlan0" && name != "lo"

    puts "#{name.ljust(15)} | RX: #{rx_mb.to_s.rjust(6)} MB/s | TX: #{tx_mb.to_s.rjust(6)} MB/s"
  end
  puts ""

  puts "=== Top 5 Processes (CPU) ==="
  system.process.list(Sysdat::Process::Sort::CPU, 5).each do |proc|
    puts "PID: #{proc.pid.to_s.ljust(8)} | User: #{proc.user.ljust(8)} | Threads: #{proc.threads.to_s.ljust(3)} | #{proc.name}"
  end
  puts ""

  sensors = system.sensors.hwmon
  unless sensors.empty?
    puts "=== Temperatures ==="
    sensors.each do |chip|
      chip.sensors.each do |sensor|
        if sensor.kind == Sysdat::Sensors::Kind::Temperature
          puts "#{chip.name} - #{sensor.label}: #{sensor.value.round(1)} °C"
        end
      end
    end
    puts ""
  end

  power = system.power.supplies
  unless power.empty?
    puts "=== Power Supplies ==="
    power.each do |psu|
      cap    = psu.capacity_percent ? "#{psu.capacity_percent}%" : "Unknown"
      health = psu.health_percent ? " (Health: #{psu.health_percent}%)" : ""
      puts "#{psu.name} (#{psu.status}): #{cap}#{health}"
    end
    puts ""
  end
end
