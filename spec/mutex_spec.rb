require "spec_helper"
require "client"

describe Xfers::Etcd::Mutex do # rubocop:disable RSpec/FilePath
  let(:conn) do
    Xfers::Etcd::Client.new(endpoints: "http://127.0.0.1:2379", allow_reconnect: true)
  end
  let(:conn2) do
    Xfers::Etcd::Client.new(endpoints: "http://127.0.0.1:2379", allow_reconnect: true)
  end

  before do
    conn.del("/etcd_mutex/lock1")
    conn.del("/etcd_mutex/lock2")
  end

  it "lock and unlock" do
    mutex1 = conn.mutex_new("lock1", ttl: 60)
    mutex2 = conn.mutex_new("lock2", ttl: 10)
    expect(mutex1.lock(2)).to eq(true)
    expect(mutex2.lock(2)).to eq(true)
    expect(mutex2.unlock).to eq(true)
    expect(mutex1.unlock).to eq(true)
  end

  it "try lock" do
    mutex = conn.mutex_new("lock1", ttl: 60)
    lock_time = Time.now
    mutex.lock
    result = mutex.try_lock
    expect(result).to be(false)
    expect(Time.now - lock_time).to be < 1

    mutex.unlock

    execute_count = 0
    lock_time = Time.now
    expect do
      mutex.try_lock do
        execute_count += 1
      end
    end.to change { execute_count }.by(1)
    expect(Time.now - lock_time).to be < 1
  end

  it "lock with same name in single process" do
    mutex1 = conn.mutex_new("lock1", ttl: 2)
    mutex2 = conn.mutex_new("lock1", ttl: 10)

    first_lock_time = Time.now
    mutex1.lock(10)
    mutex2.lock(10) do |mutex|
      expect(Time.now - first_lock_time).to be_between(2, 3)
    end
  end

  it "mutex with same name in multiple threads" do
    mutex1 = conn.mutex_new("lock1", ttl: 2)

    first_lock_time = Time.now
    mutex1.lock

    threads = []
    10.times do
      threads << Thread.new do
        mutex = conn.mutex_new("lock1", ttl: 10)
        sleep(rand(20) / 10.0)
        mutex.lock(10) do |t|
          expect(Time.now - first_lock_time).to be_between(2, 5)
        end
      end
    end
    threads.each do |thread|
      thread.join
    end
  end

  it "mutex lock timed out" do
    mutex1 = conn.mutex_new("lock1")
    mutex1.lock
    expect(mutex1.lock(1)).to eq(false)
  end

  it "mutex refresh" do
    mutex1 = conn.mutex_new("lock1", ttl: 2)
    lock_time = Time.now
    mutex1.lock(10) do |mutex|
      5.times do
        sleep(1)
        mutex.refresh
      end
    end
    expect(Time.now - lock_time).to be > 4
  end
end
