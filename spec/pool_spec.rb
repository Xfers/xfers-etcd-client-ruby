require "spec_helper"

describe Xfers::Etcd::Pool do # rubocop:disable RSpec/FilePath
  let(:pool) do
    described_class.new(
      pool_size: 8,
      pool_timeout: 2,
      endpoints: "http://127.0.0.1:2379",
      allow_reconnect: true
    )
  end

  before do
    pool.del_all
  end

  it "#version" do
    expect(pool.version).to be_a(String)
  end

  it "#put with TTL" do
    pool.put("key1", "value1", ttl: 1)
    sleep(3)
    expect(pool.exist?("key1")).to eq(false)
  end

  it "#get" do
    pool.put("key1", "value1")
    expect(pool.get("key1").value).to eq("value1")
    expect(pool.get("nonexist")).to eq(nil)
  end

  it "#get_all" do
    pool.put("key1", "value1")
    pool.put("key2", "value2")
    info = pool.get_all
    expect(info[0].value).to eq("value1")
    expect(info[1].value).to eq("value2")
  end

  it "#get_prefix" do
    pool.put("config/key1", "value1")
    pool.put("config/key2", "value2")
    pool.put("Config/key1", "value3")

    expect(pool.get_prefix("config/").map(&:value)).to eq(%w[value1 value2])
    expect(pool.get_prefix("config/", sort_order: :descend).map(&:value)).to eq(%w[value2 value1])
  end

  it "#get_range" do
    pool.put("config1", "value1")
    pool.put("config2", "value2")
    pool.put("config3", "value3")
    pool.put("config4", "value4")

    expect(pool.get_range("config1", "config4").map(&:value)).to eq(%w[value1 value2 value3])
    expect(pool.get_range("config1", "config4", sort_order: :descend).map(&:value)).to eq(%w[value3 value2 value1])
  end

  it "#del" do
    pool.put("key", "value")
    expect(pool.del("key")).to eq(1)
  end

  it "#del_all" do
    10.times do |i|
      pool.put("key#{i}", "value#{i}")
    end
    expect(pool.del_all).to eq(10)
  end

  it "#del_prefix" do
    pool.put("another_key", "value")
    10.times do |i|
      pool.put("key#{i}", "value#{i}")
    end
    expect(pool.del_prefix("key")).to eq(10)
  end

  it "#del_range" do
    pool.put("another_key", "value")
    5.times do |i|
      pool.put("key#{i}", "value#{i}")
    end
    expect(pool.del_range("key0", "key5")).to eq(5)
  end

  it "#watch" do
    Thread.new do
      sleep(0.5)
      pool.with do |conn|
        10.times do
          sleep(0.1)
          conn.put("watch_key", "test")
        end
      end
    end
    recv_count = 0
    pool.watch("watch_key", timeout: 10) do |events|
      events.each do |event|
        expect(event.kv.value).to eq("test")
      end
      recv_count += events.length
      break if recv_count >= 10
    end

    # pool.with do |conn|
    #   conn.watch("watch_key", timeout: 10) do |events|
    #     puts "test"
    #     events.each do |event|
    #       expect(event.kv.value).to eq("test")
    #     end
    #     recv_count += events.length
    #     puts recv_count
    #     break if recv_count >= 10
    #   end
    # end

    # should timeout after 1 second
    pool.with do |conn|
      events = conn.watch("watch_key", timeout: 0.2)
      puts events
      # expect(events).to eq(nil)
    end
  end

  it "#watch_forever" do
    Thread.new do
      sleep(0.5)
      10.times do
        sleep(0.1)
        pool.put("watch_key", "test")
      end
    end
    recv_count = 0
    pool.watch_forever("watch_key") do |events|
      events.each do |event|
        expect(event.kv.value).to eq("test")
      end
      recv_count += events.length
      break if recv_count >= 10
    end

    # should timeout after 1 second
    events = pool.watch("watch_key", timeout: 0.2)
    expect(events).to eq(nil)
  end

  it "#transaction" do
    pool.transaction do |txn|
      txn.compare = [
        txn.create_revision("key2", :less, 1)
      ]
      txn.success = [
        txn.put("key2", "new_value")
      ]
      txn.failure = [
        txn.put("key2", "fail_value")
      ]
    end

    expect(pool.get("key2").value).to eq("new_value")
  end
end
