require "benchmark/ips"
require "redlock"
require_relative "../lib/xfers-etcd-client"

etcd = Xfers::Etcd::Client.new(endpoints: "http://127.0.0.1:2379")
mutex = etcd.mutex_new("/benchmark/lock1")

redlock = Redlock::Client.new([ "redis://127.0.0.1:6379" ])

Benchmark.ips do |x|
  x.config(time: 2, warmup: 0)

  x.report("etcd lock/unlock") do
    mutex.lock
    mutex.unlock
  end

  x.report("etcd lock block") do
    mutex.lock do; end
  end

  x.report("redlock lock/unlock") do
    lock_info = redlock.lock("/benchmark/lock1", 1000)
    redlock.unlock(lock_info)
  end
end
