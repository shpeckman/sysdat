# src/sysdat/collector.cr
module Sysdat
  module Collector(T)
    abstract def collect : T
  end
end
