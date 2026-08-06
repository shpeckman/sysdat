# spec/parsers_spec.cr
require "./spec_helper"

describe Sysdat::Parsers do
  describe ".decode_ipv4_hex" do
    it "decodes little-endian hex into dotted quad" do
      Sysdat::Parsers.decode_ipv4_hex("0100007F").should eq("127.0.0.1")
    end

    it "decodes the wildcard address" do
      Sysdat::Parsers.decode_ipv4_hex("00000000").should eq("0.0.0.0")
    end

    it "returns the zero address for invalid input" do
      Sysdat::Parsers.decode_ipv4_hex("nothex").should eq("0.0.0.0")
    end
  end

  describe ".decode_endpoint" do
    it "decodes an IPv4 endpoint with hex port" do
      Sysdat::Parsers.decode_endpoint("0100007F:0050", false).should eq({"127.0.0.1", 80})
    end

    it "decodes a wildcard IPv4 endpoint" do
      Sysdat::Parsers.decode_endpoint("00000000:1F90", false).should eq({"0.0.0.0", 8080})
    end

    it "leaves IPv6 addresses raw and decodes the port" do
      address = "00000000000000000000000000000000"
      Sysdat::Parsers.decode_endpoint("#{address}:0050", true).should eq({address, 80})
    end

    it "returns a sentinel when no separator is present" do
      Sysdat::Parsers.decode_endpoint("garbage", false).should eq({"unknown", 0})
    end
  end

  describe ".format_ipv4" do
    it "formats four bytes as a dotted quad" do
      bytes = StaticArray(UInt8, 4).new(0_u8)
      bytes[0] = 192_u8
      bytes[1] = 168_u8
      bytes[2] = 1_u8
      bytes[3] = 10_u8
      Sysdat::Parsers.format_ipv4(bytes).should eq("192.168.1.10")
    end
  end

  describe ".format_ipv6" do
    it "collapses the longest zero run into ::" do
      bytes = StaticArray(UInt8, 16).new(0_u8)
      bytes[15] = 1_u8
      Sysdat::Parsers.format_ipv6(bytes).should eq("::1")
    end

    it "formats a mixed address with a documentation prefix" do
      bytes = StaticArray(UInt8, 16).new(0_u8)
      bytes[0] = 0x20_u8
      bytes[1] = 0x01_u8
      bytes[2] = 0x0d_u8
      bytes[3] = 0xb8_u8
      bytes[15] = 1_u8
      Sysdat::Parsers.format_ipv6(bytes).should eq("2001:db8::1")
    end

    it "formats the all-zero address" do
      bytes = StaticArray(UInt8, 16).new(0_u8)
      Sysdat::Parsers.format_ipv6(bytes).should eq("::")
    end
  end

  describe ".parse_cpu_times" do
    it "maps the eight time fields after the label" do
      times = Sysdat::Parsers.parse_cpu_times(
        ["cpu", "100", "20", "30", "400", "5", "6", "7", "8"]
      )
      times.user.should eq(100_u64)
      times.nice.should eq(20_u64)
      times.system.should eq(30_u64)
      times.idle.should eq(400_u64)
      times.iowait.should eq(5_u64)
      times.irq.should eq(6_u64)
      times.softirq.should eq(7_u64)
      times.steal.should eq(8_u64)
    end

    it "tolerates missing trailing fields" do
      times = Sysdat::Parsers.parse_cpu_times(["cpu", "1", "2"])
      times.user.should eq(1_u64)
      times.nice.should eq(2_u64)
      times.system.should eq(0_u64)
      times.steal.should eq(0_u64)
    end
  end

  describe ".parse_scheduler" do
    it "returns the bracketed active scheduler" do
      Sysdat::Parsers.parse_scheduler("noop [mq-deadline] kyber").should eq("mq-deadline")
    end

    it "returns the first token when nothing is bracketed" do
      Sysdat::Parsers.parse_scheduler("none").should eq("none")
    end

    it "returns an empty string for nil input" do
      Sysdat::Parsers.parse_scheduler(nil).should eq("")
    end
  end
end
