# src/sysdat/system.cr
module Sysdat
  class System
    getter os       : OS::Facade { OS::Facade.new(self) }
    getter cpu      : CPU::Facade { CPU::Facade.new(self) }
    getter kernel   : Kernel::Facade { Kernel::Facade.new(self) }
    getter memory   : Memory::Facade { Memory::Facade.new(self) }
    getter storage  : Storage::Facade { Storage::Facade.new(self) }
    getter network  : Network::Facade { Network::Facade.new(self) }
    getter process  : Process::Facade { Process::Facade.new(self) }
    getter power    : Power::Facade { Power::Facade.new(self) }
    getter pressure : Pressure::Facade { Pressure::Facade.new(self) }
    getter graphics : Graphics::Facade { Graphics::Facade.new(self) }
    getter sensors  : Sensors::Facade { Sensors::Facade.new(self) }
    getter devices  : Devices::Facade { Devices::Facade.new(self) }
    getter host     : Host::Facade { Host::Facade.new(self) }
    getter limits   : Limits::Facade { Limits::Facade.new(self) }

    def snapshot : Snapshot
      Snapshot.new(
        os: os.info,
        kernel: kernel.info,
        kernel_stats: kernel.stats,
        cpu: cpu.info,
        cpu_stats: cpu.stats,
        memory: memory.read,
        pressure: pressure.read,
        mounts: storage.mounts,
        block_devices: storage.block_devices,
        disk_io: storage.disk_io,
        swaps: storage.swaps,
        interfaces: network.interfaces,
        wifi: network.wifi,
        routes: network.routes,
        gpus: graphics.gpus,
        displays: graphics.displays,
        hwmon: sensors.hwmon,
        power_supplies: power.supplies,
        host: host.info,
        file_descriptors: limits.file_descriptors,
        thread_limits: limits.threads,
        captured_at: Time.utc,
      )
    end
  end

  def self.open : System
    System.new
  end
end
