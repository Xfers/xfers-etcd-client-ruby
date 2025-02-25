require "spec_helper"

describe Xfers::Etcd::Mutex do
  let(:endpoints) do
    ENV["ETCD_ENDPOINTS"] || "http://127.0.0.1:2379"
  end

  let(:main_connection) do
    Xfers::Etcd::Client.new(endpoints: endpoints, allow_reconnect: true)
  end
  let(:secondary_connection) do
    Xfers::Etcd::Client.new(endpoints: endpoints, allow_reconnect: true)
  end

  before do
    main_connection.del("/etcd_mutex/lock1")
    main_connection.del("/etcd_mutex/lock2")
  end

  it "lock and unlock" do
    mutex1 = main_connection.mutex_new("lock1", ttl: 60)
    mutex2 = main_connection.mutex_new("lock2", ttl: 10)
    expect(mutex1.lock(2)).to be(true)
    expect(mutex2.lock(2)).to be(true)
    expect(mutex2.unlock).to be(true)
    expect(mutex1.unlock).to be(true)
  end

  it "#try_lock" do
    mutex = main_connection.mutex_new("lock1", ttl: 60)
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

  it "#try_lock!" do
    mutex = main_connection.mutex_new("lock1", ttl: 60)
    lock_time = Time.now
    mutex.lock
    expect do
      mutex.try_lock!
    end.to raise_error(Xfers::Etcd::LockError)
    expect(Time.now - lock_time).to be < 1

    mutex.unlock

    execute_count = 0
    lock_time = Time.now
    expect do
      mutex.try_lock! do
        execute_count += 1
      end
    end.to change { execute_count }.by(1)
    expect(Time.now - lock_time).to be < 1
  end

  it "#lock with same name in single thread" do
    mutex1 = main_connection.mutex_new("lock1", ttl: 2)
    mutex2 = main_connection.mutex_new("lock1", ttl: 10)

    first_lock_time = Time.now
    mutex1.lock(10)
    mutex2.lock(10) do
      expect(Time.now - first_lock_time).to be_between(2, 3)
    end
  end

  it "#lock with same name in multiple threads" do
    mutex1 = main_connection.mutex_new("lock1", ttl: 2)

    first_lock_time = Time.now
    mutex1.lock

    threads = []
    5.times do
      threads << Thread.new do
        mutex = secondary_connection.mutex_new("lock1", ttl: 10)
        sleep(rand(15) / 10.0)
        mutex.lock(10) do
          locked_elasped = Time.now - first_lock_time
          expect(locked_elasped).to be_between(2, 5)
        end
      end
    end
    threads.each(&:join)
  end

  it "#lock timed out" do
    mutex1 = main_connection.mutex_new("lock1")
    mutex1.lock
    expect(mutex1.lock(0.1)).to be(false)
    mutex1.unlock
  end

  it "#lock! timed out" do
    mutex1 = main_connection.mutex_new("lock1")
    mutex1.lock!
    expect do
      mutex1.lock!(0.1)
    end.to raise_error(Xfers::Etcd::LockError)
    mutex1.unlock
  end

  it "mutex refresh" do
    mutex1 = main_connection.mutex_new("lock1", ttl: 2)
    lock_time = Time.now
    mutex1.lock(7) do |mutex|
      5.times do
        sleep(1)
        mutex.refresh
      end
    end
    expect(Time.now - lock_time).to be > 1
  end

  it "conncurrent access" do
    2.times do
      conn_access_test
    end
  end
end

def conn_access_test(num_iters: 10, num_workers: 100)
  conn1.put("balance", (num_iters * num_workers).to_s)
  conn1.mutex_new("balance_lock", ttl: 10).destroy!

  expect(conn1.mutex_new("balance_lock", ttl: 10).lock_exist?).to be(false)

  conn_pool = Xfers::Etcd::Pool.new(endpoints: endpoints, allow_reconnect: true)
  threads = num_iters.times.map do
    Thread.new do
      num_workers.times do
        conn_pool.with(timeout: 20) do |conn|
          loop do
            mutex = conn.mutex_new("balance_lock", ttl: 10)
            lock_result = mutex.lock(1) do
              balance = conn.get("balance").value.to_i
              break if balance < 1

              conn.put("balance", (balance - 1).to_s)
            end
            break if lock_result
          end
        end
      end
    end
  end

  threads.each(&:join)

  expect(conn_pool.get("balance").value.to_i).to be 0
end
