require "benchmark"
require "redis"
require_relative "../lib/xfers_etcd_client"

etcd = Xfers::Etcd::Client.new(endpoints: "http://127.0.0.1:2379")
etcd_pool = Xfers::Etcd::Pool.new(endpoints: "http://127.0.0.1:2379")

redis = Redis.new(host: "127.0.0.1", port: 6379)
redis_pool = ConnectionPool.new(size: 4) { Redis.new(host: "127.0.0.1", port: 6379) }

BYTE_SIZE = 128
value = (0...BYTE_SIZE).map { ("a".."z").to_a[rand(26)] }.join
etcd.put("test_key", value)
redis.set("test_key", value)

TIMES = 20_000

Benchmark.bm(20) do |x|
  x.report("redis get") do
    TIMES.times do
      redis.get("test_key")
    end
  end

  x.report("redis threaded get") do
    threads = []
    thread_count = 4
    thread_count.times do
      threads << Thread.new do
        redis_pool.with do |client|
          (TIMES / thread_count).times do
            client.get("test_key")
          end
        end
      end
    end
    threads.each(&:join)
  end

  x.report("etcd pool get") do
    TIMES.times do
      etcd_pool.get("test_key")
    end
  end

  x.report("etcd threaded get") do
    threads = []
    thread_count = 4
    thread_count.times do
      threads << Thread.new do
        etcd_pool.with do |client|
          (TIMES / thread_count).times do
            client.get("test_key")
          end
        end
      end
    end
    threads.each(&:join)
  end

  etcd_pool.with do |client|
    x.report("etcd pool block get") do
      TIMES.times do
        client.get("test_key")
      end
    end
  end

  x.report("etcd direct get") do
    TIMES.times do
      etcd.get("test_key")
    end
  end
end
