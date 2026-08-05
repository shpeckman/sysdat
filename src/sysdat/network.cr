# src/sysdat/network.cr
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

  struct NetworkRate
    getter rx_bytes_per_sec   : Float64
    getter tx_bytes_per_sec   : Float64
    getter rx_packets_per_sec : Float64
    getter tx_packets_per_sec : Float64

    def initialize(@rx_bytes_per_sec, @tx_bytes_per_sec, @rx_packets_per_sec, @tx_packets_per_sec)
    end
  end

  struct NetworkInterface
    getter name       : String
    getter rx_bytes   : UInt64
    getter rx_packets : UInt64
    getter rx_errors  : UInt64
    getter rx_dropped : UInt64
    getter tx_bytes   : UInt64
    getter tx_packets : UInt64
    getter tx_errors  : UInt64
    getter tx_dropped : UInt64

    def initialize(@name, @rx_bytes, @rx_packets, @rx_errors, @rx_dropped,
                   @tx_bytes, @tx_packets, @tx_errors, @tx_dropped)
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

  struct WiFi
    getter name         : String
    getter link_quality : Float64
    getter signal_dbm   : Float64
    getter noise_dbm    : Float64

    def initialize(@name, @link_quality, @signal_dbm, @noise_dbm)
    end
  end

  struct Socket
    getter protocol    : String
    getter local_ip    : String
    getter local_port  : Int32
    getter remote_ip   : String
    getter remote_port : Int32
    getter state       : String

    def initialize(@protocol, @local_ip, @local_port, @remote_ip, @remote_port, @state)
    end
  end

  def self.interfaces : Array(NetworkInterface)
    interfaces = [] of NetworkInterface

    SysFS.read_lines("/proc/net/dev") do |line|
      name, separator, rest = line.partition(':')
      next if separator.empty?

      fields = rest.split
      next if fields.size < 16

      values = fields.first(16).map { |field| field.to_u64? || 0_u64 }
      interfaces << NetworkInterface.new(
        name: name.strip,
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

  def self.sockets : Array(Socket)
    sockets = [] of Socket

    SOCKET_SOURCES.each do |(path, protocol, ipv6)|
      SysFS.read_lines(path) do |line|
        fields = line.split
        next if fields.size < 4
        next unless fields[0].ends_with?(':')

        local_ip, local_port = decode_endpoint(fields[1], ipv6)
        remote_ip, remote_port = decode_endpoint(fields[2], ipv6)
        state_value = fields[3].to_i?(16) || 0

        sockets << Socket.new(
          protocol: protocol,
          local_ip: local_ip,
          local_port: local_port,
          remote_ip: remote_ip,
          remote_port: remote_port,
          state: protocol.starts_with?("tcp") ? tcp_state(state_value) : udp_state(state_value),
        )
      end
    end

    sockets
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

  private def self.decode_endpoint(field : String, ipv6 : Bool) : Tuple(String, Int32)
    address, separator, port = field.rpartition(':')
    return {"unknown", 0} if separator.empty?

    port_number = port.to_i?(16) || 0
    return {address, port_number} if ipv6 || address.size != 8

    packed = address.to_u32?(16)
    return {address, port_number} unless packed

    ip = String.build do |io|
      4.times do |index|
        io << '.' if index > 0
        io << ((packed >> (index * 8)) & 0xff)
      end
    end

    {ip, port_number}
  end
end
