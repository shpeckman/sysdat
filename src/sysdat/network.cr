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

  record NetworkRate,
    rx_bytes_per_sec   : Float64,
    tx_bytes_per_sec   : Float64,
    rx_packets_per_sec : Float64,
    tx_packets_per_sec : Float64

  record NetworkInterface,
    name       : String,
    rx_bytes   : UInt64,
    rx_packets : UInt64,
    rx_errors  : UInt64,
    rx_dropped : UInt64,
    tx_bytes   : UInt64,
    tx_packets : UInt64,
    tx_errors  : UInt64,
    tx_dropped : UInt64 do
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
    noise_dbm    : Float64

  record Socket,
    protocol    : String,
    local_ip    : String,
    local_port  : Int32,
    remote_ip   : String,
    remote_port : Int32,
    state       : String

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
