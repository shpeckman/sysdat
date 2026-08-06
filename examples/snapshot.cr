# examples/snapshot.cr
require "../src/sysdat"

snapshot = Sysdat.snapshot

puts "=== Snapshot Overview ==="
puts "Captured:  #{snapshot.captured_at}"
puts "Host:      #{snapshot.os.hostname} (#{snapshot.os.sysname} #{snapshot.os.release})"
puts "Uptime:    #{snapshot.os.uptime}"
puts "Booted:    #{snapshot.kernel_stats.boot_time}"
puts "Memory:    #{Sysdat::Format.bytes(snapshot.memory.used)} / #{Sysdat::Format.bytes(snapshot.memory.total)}"
puts "CPU:       #{snapshot.cpu.model_name} @ #{Sysdat::Format.hertz(snapshot.cpu.base_mhz)}"
puts "Entropy:   #{snapshot.kernel.entropy_avail} bits"
puts ""

puts "=== Interfaces ==="
snapshot.interfaces.each do |iface|
  addresses = iface.addresses.map { |address| "#{address.family} #{address.address}" }.join(", ")
  puts "#{iface.name.ljust(10)} #{iface.operstate.ljust(8)} mtu=#{iface.mtu} #{iface.mac_address} [#{addresses}]"
end
puts ""

puts "=== CPU Sampler (1s window) ==="
sampler = Sysdat::CPUSampler.new
sleep 1.second
puts "Total usage: #{sampler.sample.round(2)}%"
puts ""

puts "=== JSON ==="
File.write("snapshot.json", snapshot.to_json)
puts "Wrote snapshot.json (#{File.size("snapshot.json")} bytes)"
