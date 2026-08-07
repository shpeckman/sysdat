# src/sysdat/sampler.cr
module Sysdat
  class Sampler(Reading, Rate)
    @previous : Reading
    @last     : Time::Instant

    def initialize(@read : -> Reading, @rate : Reading, Reading, Time::Span -> Rate)
      @previous = @read.call
      @last     = Time.instant
    end

    def initialize(previous : Reading, @read : -> Reading, @rate : Reading, Reading, Time::Span -> Rate)
      @previous = previous
      @last     = Time.instant
    end

    def sample : Rate
      now       = Time.instant
      interval  = now - @last
      current   = @read.call
      rate      = @rate.call(@previous, current, interval)
      @previous = current
      @last     = now
      rate
    end
  end
end
