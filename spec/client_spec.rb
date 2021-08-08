require "spec_helper"

describe Xfers::Etcd::Client do # rubocop:disable RSpec/FilePath
  let(:conn) do
    described_class.new(endpoints: "http://127.0.0.1:2379", allow_reconnect: true)
  end
  let(:conn2) do
    described_class.new(endpoints: "http://127.0.0.1:2379", allow_reconnect: true)
  end

  before do
    conn.del_all
  end

  it "invalid arguments" do
    expect { conn.exist?("") }.to raise_error(ArgumentError)
    expect { conn.get("") }.to raise_error(ArgumentError)
    expect { conn.get_prefix("") }.to raise_error(ArgumentError)
    expect { conn.get_range("", "a") }.to raise_error(ArgumentError)
    expect { conn.get_range("a", nil) }.to raise_error(ArgumentError)
    expect { conn.put("", nil) }.to raise_error(ArgumentError)
    expect { conn.del(nil) }.to raise_error(ArgumentError)
    expect { conn.del_prefix(nil) }.to raise_error(ArgumentError)
    expect { conn.del_prefix(nil) }.to raise_error(ArgumentError)
    expect { conn.del_range(nil) }.to raise_error(ArgumentError)
    expect { conn.del_range("", "a") }.to raise_error(ArgumentError)
    expect { conn.del_range("a", nil) }.to raise_error(ArgumentError)
  end

  it "#version" do
    expect(conn.version).to be_a(String)
  end

  it "#db_size" do
    expect(conn.db_size).to be_a(Integer)
  end

  it "#put with TTL" do
    conn.put("key1", "value1", ttl: 1)
    sleep(3)
    expect(conn.exist?("key1")).to eq(false)
  end

  it "#get" do
    conn.put("key1", "value1")
    expect(conn.get("key1").value).to eq("value1")
    expect(conn.get("nonexist")).to eq(nil)
  end

  it "#get_all" do
    conn.put("key1", "value1")
    conn.put("key2", "value2")
    info = conn.get_all
    expect(info[0].value).to eq("value1")
    expect(info[1].value).to eq("value2")
  end

  it "#get_prefix" do
    conn.put("config/key1", "value1")
    conn.put("config/key2", "value2")
    conn.put("Config/key1", "value3")

    expect(conn.get_prefix("config/").map(&:value)).to eq(%w[value1 value2])
    expect(conn.get_prefix("config/", sort_order: :descend).map(&:value)).to eq(%w[value2 value1])
  end

  it "#get_range" do
    conn.put("config1", "value1")
    conn.put("config2", "value2")
    conn.put("config3", "value3")
    conn.put("config4", "value4")

    expect(conn.get_range("config1", "config4").map(&:value)).to eq(%w[value1 value2 value3])
    expect(conn.get_range("config1", "config4", sort_order: :descend).map(&:value)).to eq(%w[value3 value2 value1])
  end

  it "#del" do
    conn.put("key", "value")
    expect(conn.del("key")).to eq(1)
  end

  it "#del_all" do
    10.times do |i|
      conn.put("key#{i}", "value#{i}")
    end
    expect(conn.del_all).to eq(10)
  end

  it "#del_prefix" do
    conn.put("another_key", "value")
    10.times do |i|
      conn.put("key#{i}", "value#{i}")
    end
    expect(conn.del_prefix("key")).to eq(10)
  end

  it "#del_range" do
    conn.put("another_key", "value")
    5.times do |i|
      conn.put("key#{i}", "value#{i}")
    end
    expect(conn.del_range("key0", "key5")).to eq(5)
  end

  it "#watch" do
    Thread.new do
      sleep(0.2)
      10.times do
        sleep(0.1)
        conn2.put("watch_key", "test")
      end
    end
    recv_count = 0
    conn.watch("watch_key", timeout: 10) do |events|
      events.each do |event|
        expect(event.kv.value).to eq("test")
      end
      recv_count += events.length
      break if recv_count >= 10
    end

    # should timeout after 1 second
    events = conn.watch("watch_key", timeout: 0.2)
    expect(events).to eq(nil)
  end

  it "#watch_forever" do
    Thread.new do
      sleep(0.5)
      10.times do
        sleep(0.1)
        conn2.put("watch_key", "test")
      end
    end
    recv_count = 0
    conn.watch_forever("watch_key") do |events|
      events.each do |event|
        expect(event.kv.value).to eq("test")
      end
      recv_count += events.length
      break if recv_count >= 10
    end

    # should timeout after 1 second
    events = conn.watch("watch_key", timeout: 0.2)
    expect(events).to eq(nil)
  end

  it "#watch_prefix" do
    Thread.new do
      sleep(0.2)
      10.times do |i|
        sleep(0.1)
        conn2.put("records/key#{i}", "test")
      end
    end
    recv_count = 0
    conn.watch_prefix("records/", timeout: 10) do |events|
      events.each do |event|
        puts event.kv.key
        expect(event.kv.value).to eq("test")
      end
      recv_count += events.length
      break if recv_count >= 10
    end

    events = conn.watch_prefix("records/", timeout: 0.2)
    expect(events).to eq(nil)
  end

  it "#watch_prefix_forever" do
    Thread.new do
      sleep(0.2)
      50.times do |i|
        conn2.put("records/key#{i}", "test")
      end
    end
    recv_count = 0
    conn.watch_prefix_forever("records/") do |events|
      events.each do |event|
        expect(event.kv.value).to eq("test")
      end
      recv_count += events.length
      break if recv_count >= 50
    end

    events = conn.watch_prefix("records/", timeout: 0.2)
    expect(events).to eq(nil)
  end

  it "#transaction" do
    conn.transaction do |txn|
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

    expect(conn.get("key2").value).to eq("new_value")
  end
end
