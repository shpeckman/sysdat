# src/sysdat/collectors/network.cr
module Sysdat
  TCP_STATES = %w[
    UNKNOWN ESTABLISHED SYN_SENT SYN_RECV FIN_WAIT1
    FIN_WAIT2 TIME_WAIT CLOSE CLOSE_WAIT LAST_ACK
    LISTEN CLOSING
  ]

  SOCKET_SOURCES = {
    {"/proc/net/tcp",  "tcp4", false},
    {"/proc/net/udp",  "udp4", false},
    {"/proc/net/tcp6", "tcp6", true},
    {"/proc/net/udp6", "udp6", true},
  }

  record NetworkRate,
    rx_bytes_per_sec   : Float64,
    tx_bytes_per_sec   : Float64,
    rx_packets_per_sec : Float64,
    tx_packets_per_sec : Float64 do
    include JSON::Serializable
  end

  record InterfaceAddress,
    family  : String,
    address : String do
    include JSON::Serializable
  end

  record NetworkInterface,
    name        : String,
    mac_address : String,
    operstate   : String,
    mtu         : Int32,
    speed_mbps  : Int32,
    addresses   : Array(InterfaceAddress),
    rx_bytes    : UInt64,
    rx_packets  : UInt64,
    rx_errors   : UInt64,
    rx_dropped  : UInt64,
    tx_bytes    : UInt64,
    tx_packets  : UInt64,
    tx_errors   : UInt64,
    tx_dropped  : UInt64 do
    include JSON::Serializable

    def up? : Bool
      operstate == "up"
    end

    def rate_since(previous : NetworkInterface, interval : Time::Span) : NetworkRate
      seconds = interval.total_seconds
      raise Error.new("interval must be positive") unless seconds > 0.0

      NetworkRate.new(
        rx_bytes_per_sec: delta(rx_bytes, previous.rx_bytes) / seconds,
        tx_bytes_per_sec: delta(tx_bytes, previous.tx_bytes) / seconds,
        rx_packets_per_sec: delta(rx_packets, previous.rx_packets) / seconds,
        tx_packets_per_sec: delta(tx_packets, previous.tx_packets) / seconds,
      )
    end

    private def delta(current : UInt64, previous : UInt64) : Float64
      current > previous ? (current - previous).to_f : 0.0
    end
  end

  record WiFi,
    name         : String,
    link_quality : Float64,
    signal_dbm   : Float64,
    noise_dbm    : Float64 do
    include JSON::Serializable
  end

  record Socket,
    protocol    : String,
    local_ip    : String,
    local_port  : Int32,
    remote_ip   : String,
    remote_port : Int32,
    state       : String,
    inode       : UInt64,
    pid         : Int32?,
    process     : String? do
    include JSON::Serializable
  end

  record Route,
    destination : String,
    gateway     : String,
    flags       : Int32,
    ref_count   : Int32,
    use         : Int32,
    metric      : Int32,
    mask        : String,
    mtu         : Int32,
    window      : Int32,
    irtt        : Int32,
    interface   : String do
    include JSON::Serializable
  end

  record ArpEntry,
    ip         : String,
    hw_type    : String,
    flags      : String,
    hw_address : String,
    mask       : String,
    device     : String do
    include JSON::Serializable
  end

  class NetworkSampler
    @previous : Hash(String, NetworkInterface)
    @last     : Time::Span

    def initialize
      @previous = index_interfaces(Sysdat.interfaces)
      @last     = Time.instant
    end

    def sample : Hash(String, NetworkRate)
      now      = Time.instant
      interval = now - @last
      current  = Sysdat.interfaces
      rates    = {} of String => NetworkRate

      if interval.total_seconds > 0.0
        current.each do |iface|
          if previous = @previous[iface.name]?
            rates[iface.name] = iface.rate_since(previous, interval)
          end
        end
      end

      @previous = index_interfaces(current)
      @last     = now
      rates
    end

    private def index_interfaces(interfaces : Array(NetworkInterface)) : Hash(String, NetworkInterface)
      indexed = {} of String => NetworkInterface
      interfaces.each { |iface| indexed[iface.name] = iface }
      indexed
    end
  end

  def self.interfaces : Array(NetworkInterface)
    interfaces = [] of NetworkInterface
    addresses  = interface_addresses

    SysFS.read_lines("/proc/net/dev") do |line|
      name, separator, rest = line.partition(':')
      next if separator.empty?

      name   = name.strip
      fields = rest.split
      next if fields.size < 16

      values = fields.first(16).map { |field| field.to_u64? || 0_u64 }
      base   = "/sys/class/net/#{name}"

      interfaces << NetworkInterface.new(
        name: name,
        mac_address: SysFS.read_line("#{base}/address") || "",
        operstate: SysFS.read_line("#{base}/operstate") || "unknown",
        mtu: (SysFS.read_int("#{base}/mtu") || 0_i64).to_i32,
        speed_mbps: (SysFS.read_int("#{base}/speed") || -1_i64).to_i32,
        addresses: addresses[name]? || [] of InterfaceAddress,
        rx_bytes: values[0],
        rx_packets: values[1],
        rx_errors: values[2],
        rx_dropped: values[3],
        tx_bytes: values[8],
        tx_packets: values[9],
        tx_errors: values[10],
        tx_dropped: values[11],
      )
    end

    interfaces
  end

  def self.wifi : Array(WiFi)
    devices = [] of WiFi

    SysFS.read_lines("/proc/net/wireless") do |line|
      name, separator, rest = line.partition(':')
      next if separator.empty?

      fields = rest.split
      next if fields.size < 4

      devices << WiFi.new(
        name: name.strip,
        link_quality: parse_wireless(fields[1]),
        signal_dbm: parse_wireless(fields[2]),
        noise_dbm: parse_wireless(fields[3]),
      )
    end

    devices
  end

  def self.sockets(resolve_process : Bool = false) : Array(Socket)
    sockets   = [] of Socket
    inode_map = resolve_process ? build_socket_inode_map : nil

    SOCKET_SOURCES.each do |(path, protocol, ipv6)|
      SysFS.read_lines(path) do |line|
        fields = line.split
        next if fields.size < 10
        next unless fields[0].ends_with?(':')

        local_ip, local_port = Parsers.decode_endpoint(fields[1], ipv6)
        remote_ip, remote_port = Parsers.decode_endpoint(fields[2], ipv6)
        state_value = fields[3].to_i?(16) || 0
        inode       = fields[9].to_u64? || 0_u64

        pid     = nil
        process = nil
        if inode_map && (owner = inode_map[inode]?)
          pid     = owner[0]
          process = owner[1]
        end

        sockets << Socket.new(
          protocol: protocol,
          local_ip: local_ip,
          local_port: local_port,
          remote_ip: remote_ip,
          remote_port: remote_port,
          state: protocol.starts_with?("tcp") ? tcp_state(state_value) : udp_state(state_value),
          inode: inode,
          pid: pid,
          process: process,
        )
      end
    end

    sockets
  end

  def self.routes : Array(Route)
    routes = [] of Route

    SysFS.read_lines("/proc/net/route") do |line|
      next if line.starts_with?("Iface")
      fields = line.split
      next if fields.size < 11

      routes << Route.new(
        interface: fields[0],
        destination: Parsers.decode_ipv4_hex(fields[1]),
        gateway: Parsers.decode_ipv4_hex(fields[2]),
        flags: fields[3].to_i?(16) || 0,
        ref_count: fields[4].to_i? || 0,
        use: fields[5].to_i? || 0,
        metric: fields[6].to_i? || 0,
        mask: Parsers.decode_ipv4_hex(fields[7]),
        mtu: fields[8].to_i? || 0,
        window: fields[9].to_i? || 0,
        irtt: fields[10].to_i? || 0
      )
    end

    routes
  end

  def self.arp_cache : Array(ArpEntry)
    entries = [] of ArpEntry

    SysFS.read_lines("/proc/net/arp") do |line|
      next if line.starts_with?("IP")
      fields = line.split
      next if fields.size < 6

      entries << ArpEntry.new(
        ip: fields[0],
        hw_type: fields[1],
        flags: fields[2],
        hw_address: fields[3],
        mask: fields[4],
        device: fields[5]
      )
    end

    entries
  end

  private def self.interface_addresses : Hash(String, Array(InterfaceAddress))
    result = Hash(String, Array(InterfaceAddress)).new

    list = uninitialized LibSys::Ifaddrs*
    return result unless LibSys.getifaddrs(pointerof(list)) == 0

    begin
      current = list
      until current.null?
        entry   = current.value
        current = entry.ifa_next

        addr = entry.ifa_addr
        next if addr.null?

        name   = String.new(entry.ifa_name)
        family = addr.value.sa_family

        case family
        when LibSys::AF_INET
          sockaddr = addr.as(LibSys::SockaddrIn*).value
          text     = Parsers.format_ipv4(sockaddr.sin_addr)
          (result[name] ||= [] of InterfaceAddress) << InterfaceAddress.new("inet", text)
        when LibSys::AF_INET6
          sockaddr = addr.as(LibSys::SockaddrIn6*).value
          text     = Parsers.format_ipv6(sockaddr.sin6_addr)
          (result[name] ||= [] of InterfaceAddress) << InterfaceAddress.new("inet6", text)
        end
      end
    ensure
      LibSys.freeifaddrs(list)
    end

    result
  end

  private def self.build_socket_inode_map : Hash(UInt64, Tuple(Int32, String))
    map = Hash(UInt64, Tuple(Int32, String)).new

    begin
      Dir.each_child("/proc") do |entry|
        pid = entry.to_i?
        next unless pid && pid > 0

        name = nil
        begin
          Dir.each_child("/proc/#{pid}/fd") do |fd|
            target = SysFS.readlink("/proc/#{pid}/fd/#{fd}")
            next unless target && target.starts_with?("socket:[")

            inode = target["socket:[".size...-1].to_u64?
            next unless inode

            name ||= read_process_name(pid)
            map[inode] = {pid, name}
          end
        rescue IO::Error
        end
      end
    rescue IO::Error
    end

    map
  end

  private def self.read_process_name(pid : Int32) : String
    if content = SysFS.read_all("/proc/#{pid}/stat")
      open_paren  = content.index('(')
      close_paren = content.rindex(')')
      if open_paren && close_paren && close_paren > open_paren
        return content[open_paren + 1...close_paren]
      end
    end
    pid.to_s
  end

  private def self.parse_wireless(field : String) : Float64
    field.to_f?(strict: false) || 0.0
  end

  private def self.tcp_state(value : Int32) : String
    TCP_STATES[value]? || TCP_STATES[0]
  end

  private def self.udp_state(value : Int32) : String
    value == 7 ? "CLOSE" : "ACTIVE"
  end
end
