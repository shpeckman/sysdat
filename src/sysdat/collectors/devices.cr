# src/sysdat/collectors/devices.cr
module Sysdat::Devices
  record USB,
    vendor_id    : String,
    product_id   : String,
    manufacturer : String,
    product      : String do
    include JSON::Serializable
  end

  record PCI,
    address   : String,
    vendor_id : String,
    device_id : String,
    class_id  : String do
    include JSON::Serializable
  end

  record KernelModule,
    name       : String,
    size_bytes : UInt64,
    ref_count  : UInt32 do
    include JSON::Serializable
  end

  class USBCollector
    include Sysdat::Collector(Array(USB))

    def collect : Array(USB)
      SysFS.children("/sys/bus/usb/devices").compact_map do |entry|
        base      = "/sys/bus/usb/devices/#{entry}"
        vendor_id = SysFS.read_line("#{base}/idVendor")
        next unless vendor_id

        USB.new(
          vendor_id: vendor_id,
          product_id: SysFS.read_line("#{base}/idProduct") || "Unknown",
          manufacturer: SysFS.read_line("#{base}/manufacturer") || "",
          product: SysFS.read_line("#{base}/product") || "Unknown Device",
        )
      end
    end
  end

  class PCICollector
    include Sysdat::Collector(Array(PCI))

    def collect : Array(PCI)
      SysFS.children("/sys/bus/pci/devices").map do |entry|
        base = "/sys/bus/pci/devices/#{entry}"

        PCI.new(
          address: entry,
          vendor_id: Devices.hex_id("#{base}/vendor"),
          device_id: Devices.hex_id("#{base}/device"),
          class_id: Devices.hex_id("#{base}/class"),
        )
      end
    end
  end

  class KernelModulesCollector
    include Sysdat::Collector(Array(KernelModule))

    def collect : Array(KernelModule)
      modules = [] of KernelModule

      SysFS.read_lines("/proc/modules") do |line|
        fields = line.split
        next if fields.size < 3

        modules << KernelModule.new(
          name: fields[0],
          size_bytes: fields[1].to_u64? || 0_u64,
          ref_count: fields[2].to_u32? || 0_u32,
        )
      end

      modules
    end
  end

  protected def self.hex_id(path : String) : String
    (SysFS.read_line(path) || "").strip.lchop("0x")
  end

  class Facade
    def initialize(@system : Sysdat::System)
    end

    def usb_devices : Array(USB)
      USBCollector.new.collect
    end

    def pci_devices : Array(PCI)
      PCICollector.new.collect
    end

    def kernel_modules : Array(KernelModule)
      KernelModulesCollector.new.collect
    end
  end
end
