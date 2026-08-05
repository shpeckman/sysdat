# examples/demo.cr
require "../src/sysdat"

os            = Sysdat.os
limits        = Sysdat.file_descriptors
thread_limits = Sysdat.thread_limits

puts "=== System Overview ==="
puts "Hostname: #{os.hostname}"
puts "OS:       #{os.sysname} #{os.release} (#{os.machine})"
puts "Uptime:   #{os.uptime}"
puts "Load Avg: #{os.load_average}"
puts "Tasks:    #{os.processes_running} running / #{os.processes_total} total"
puts "FDs:      #{limits.used} / #{limits.maximum}"
puts "Threads:  Max #{thread_limits.threads_max} (PID max: #{thread_limits.pid_max})"
puts ""

cpu = Sysdat.cpu
puts "=== CPU Information ==="
puts "Model:     #{cpu.model_name}"
puts "Cores:     #{cpu.physical_cores} Physical, #{cpu.logical_cores} Logical"
puts "Base MHz:  #{cpu.base_mhz.round(2)}"
puts "Governors: #{cpu.core_governors.uniq.join(", ")}"
puts ""

mem = Sysdat.memory
puts "=== Memory Information ==="
puts "Total:    #{mem.total // 1048576} MB"
puts "Used:     #{mem.used // 1048576} MB"
puts "Free:     #{mem.free // 1048576} MB"
puts ""

puts "=== Block Devices ==="
Sysdat.block_devices.each do |disk|
  type = disk.rotational ? "HDD" : "SSD"
  puts "#{disk.name.ljust(10)} | #{type.ljust(4)} | #{disk.size_bytes // 1048576} MB | #{disk.model}"
end
puts ""

puts "=== Mounts ==="
Sysdat.mounts.each do |mount|
  puts "#{mount.mount_point.ljust(20)} | #{mount.fs_type.ljust(8)} | #{mount.total_bytes // 1048576} MB total"
end
puts ""

puts "=== Network Overview ==="
Sysdat.interfaces.each do |iface|
  next if iface.rx_bytes == 0 && iface.tx_bytes == 0
  puts "#{iface.name.ljust(15)} | RX: #{(iface.rx_bytes // 1024).to_s.ljust(8)} KB | TX: #{(iface.tx_bytes // 1024).to_s.ljust(8)} KB"
end
default_gw = Sysdat.routes.find { |r| r.destination == "0.0.0.0" }
puts "Default GW:  #{default_gw.try(&.gateway) || "None"}"
puts "ARP Entries: #{Sysdat.arp_cache.size}"
puts ""

puts "=== Top 5 Processes (CPU) ==="
Sysdat.processes(Sysdat::ProcessSort::CPU, 5).each do |proc|
  puts "PID: #{proc.pid.to_s.ljust(8)} | User: #{proc.user.ljust(10)} | RAM: #{proc.memory_percent.round(2).to_s.ljust(5)}% | Name: #{proc.name}"
end
puts ""

power = Sysdat.power_supplies
unless power.empty?
  puts "=== Power ==="
  power.each do |psu|
    health = psu.health_percent ? "#{psu.health_percent}% health" : "Unknown health"
    cycle  = psu.cycle_count ? " (#{psu.cycle_count} cycles)" : ""
    puts "#{psu.name} (#{psu.status}): #{psu.capacity_percent || "?"}% [#{health}]#{cycle}"
  end
  puts ""
end

host = Sysdat.host
puts "=== Environment ==="
puts "VM:        #{host.virtual_machine? ? host.virtual_machine : "None"}"
puts "Container: #{host.container? ? host.container : "None"}"
