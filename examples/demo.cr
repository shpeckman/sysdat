# examples/demo.cr
require "../src/sysdat"

os = Sysdat.os
puts "=== OS Information ==="
puts "Hostname: #{os.hostname}"
puts "OS:       #{os.sysname} #{os.release} (#{os.machine})"
puts "Uptime:   #{os.uptime}"
puts "Load Avg: #{os.load_average}"
puts "Tasks:    #{os.processes_running} running / #{os.processes_total} total"
puts ""

cpu = Sysdat.cpu
puts "=== CPU Information ==="
puts "Model:    #{cpu.model_name}"
puts "Cores:    #{cpu.physical_cores} Physical, #{cpu.logical_cores} Logical"
puts "Base MHz: #{cpu.base_mhz.round(2)}"
puts ""

mem = Sysdat.memory
puts "=== Memory Information ==="
puts "Total:    #{mem.total // 1048576} MB"
puts "Used:     #{mem.used // 1048576} MB"
puts "Free:     #{mem.free // 1048576} MB"
puts ""

puts "=== Top 5 Processes (CPU) ==="
Sysdat.processes(Sysdat::ProcessSort::CPU, 5).each do |proc|
  puts "PID: #{proc.pid.to_s.ljust(8)} | RAM: #{proc.memory_percent.round(2).to_s.ljust(5)}% | Name: #{proc.name}"
end
puts ""

puts "=== Network Interfaces ==="
Sysdat.interfaces.each do |iface|
  puts "#{iface.name.ljust(15)} | RX: #{(iface.rx_bytes // 1024).to_s.ljust(8)} KB | TX: #{(iface.tx_bytes // 1024).to_s.ljust(8)} KB"
end
puts ""

puts "=== Mounts ==="
Sysdat.mounts.each do |mount|
  puts "#{mount.mount_point.ljust(20)} | #{mount.fs_type.ljust(8)} | #{mount.total_bytes // 1048576} MB total"
end
puts ""

host = Sysdat.host
puts "=== Environment ==="
puts "VM:        #{host.virtual_machine? ? host.virtual_machine : "None"}"
puts "Container: #{host.container? ? host.container : "None"}"