# examples/live_demo.cr
require "../src/sysdat"

print "\e[?25l"
at_exit { print "\e[?25h" }

previous_cpu = Sysdat.cpu_stats
previous_net = Sysdat.interfaces
last_time    = Time.monotonic

loop do
  sleep 1

  current_time = Time.monotonic
  interval     = current_time - last_time

  current_cpu = Sysdat.cpu_stats
  current_net = Sysdat.interfaces

  print "\e[2J\e[H"

  os = Sysdat.os
  puts "=== System Overview ==="
  puts "OS:       #{os.sysname} #{os.release}"
  puts "Uptime:   #{os.uptime}"
  puts "Load Avg: #{os.load_average}"
  puts ""

  cpu_usage = current_cpu.total.usage_since(previous_cpu.total)
  puts "=== CPU Usage ==="
  puts "Total:    #{cpu_usage.round(2)}%"

  current_cpu.cores.each_with_index do |core, index|
    previous_core = previous_cpu.cores[index]?
    next unless previous_core
    core_usage = core.usage_since(previous_core)
    print "Core #{index.to_s.ljust(2)}: #{core_usage.round(1).to_s.rjust(5)}%   "
    puts "" if index % 4 == 3
  end
  puts "" unless current_cpu.cores.size % 4 == 0
  puts ""

  mem         = Sysdat.memory
  mem_percent = mem.total > 0 ? (mem.used.to_f / mem.total * 100).round(2) : 0.0
  puts "=== Memory ==="
  puts "Used:     #{mem.used // 1048576} MB / #{mem.total // 1048576} MB (#{mem_percent}%)"
  puts "Swap:     #{(mem.swap_total - mem.swap_free) // 1048576} MB / #{mem.swap_total // 1048576} MB"
  puts ""

  puts "=== Network (Rates) ==="
  current_net.each do |iface|
    previous_iface = previous_net.find { |i| i.name == iface.name }
    next unless previous_iface

    rate  = iface.rate_since(previous_iface, interval)
    rx_mb = (rate.rx_bytes_per_sec / 1_048_576).round(2)
    tx_mb = (rate.tx_bytes_per_sec / 1_048_576).round(2)

    puts "#{iface.name.ljust(15)} | RX: #{rx_mb.to_s.rjust(6)} MB/s | TX: #{tx_mb.to_s.rjust(6)} MB/s"
  end
  puts ""

  puts "=== Top 5 Processes (CPU) ==="
  Sysdat.processes(Sysdat::ProcessSort::CPU, 5).each do |proc|
    puts "PID: #{proc.pid.to_s.ljust(8)} | Threads: #{proc.threads.to_s.ljust(3)} | Name: #{proc.name}"
  end
  puts ""

  sensors = Sysdat.hwmon
  unless sensors.empty?
    puts "=== Temperatures ==="
    sensors.each do |chip|
      chip.sensors.each do |sensor|
        if sensor.kind == Sysdat::SensorKind::Temperature
          puts "#{chip.name} - #{sensor.label}: #{sensor.value.round(1)} °C"
        end
      end
    end
    puts ""
  end

  power = Sysdat.power_supplies
  unless power.empty?
    puts "=== Power Supplies ==="
    power.each do |psu|
      cap = psu.capacity_percent ? "#{psu.capacity_percent}%" : "Unknown"
      puts "#{psu.name} (#{psu.status}): #{cap}"
    end
    puts ""
  end

  previous_cpu = current_cpu
  previous_net = current_net
  last_time    = current_time
end
