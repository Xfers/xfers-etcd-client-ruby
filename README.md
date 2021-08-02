# Xfers etcd v3 client
The Etcd v3 client library, provide high level functions for Etcd v3.

# Features
* GET: `get`, `get_all`, `get_prefix`, `get_range`
* PUT: `put`, `put_all`, `put_prefix`, `put_range`
* DELETE: `del`, `del_all`, `del_prefix`, `del_range`
* LEASE: `lease_grant`, `lease_revoke`, `lease_ttl`, `lease_keep_alive_once`
* WATCH: `watch`, `watch_forever`
* TRANSACTION: `transaction`
* Distributed Lock: `Xfers::Etcd::Mutex`

# Examples

**Create a new etcd client**
```ruby
  conn = Xfers::Etcd::Client.new(endpoints: "http://127.0.0.2:2379")
```

**Simple get & put**

```ruby
conn.put("/config/token", "token_1")

# token.key == "/config/token", token.value == "token_1"
token = conn.get("/config/token")
```

**Put with TTL**
```ruby
# put a key which will expire after 10 seconds
conn.put("/connections/1/tx_start_at", Time.now, ttl: 10)
sleep(11)
# data == nil after 11 seconds
data = conn.get("/connections/1/tx_start_at")
```

**Watch a key**

```ruby
# watcher
# will print the following messages
# new value: test
# /models/bank_account/updated_at delete
# new value: test2
# /models/bank_account/updated_at delete
conn.watch_forever("/models/bank_account/updated_at") do |events|
  events.each do |event|
    case event.type
    when :PUT
      puts "new value: #{event.kv.value}"
    when :DELETE
      puts "#{event.kv.key} deleted"
    end
  end
end
```

```ruby
# notifier
conn.put("/models/bank_account/updated_at", "test")
conn.delete("/models/bank_account/updated_at")
conn.put("/models/bank_account/updated_at", "test2", ttl: 3)
```

**Mutex lock**

```ruby
# create a new mutex instance with 10 seconds TTL
mutex = conn.mutex_new("jobs/1", ttl: 10)
# try to lock this mutex, will fail if it can't acquire lock after 2 second
mutex.lock(2) do |mu|
  # critical code
  # ...

  # refresh TTL of lock to avoid expire
  mu.refresh

  # critical code
  # ...
end
# will unlock automatically when block finished

# can re-lock again
mutex.try_lock do |mu|
  # will be executed
end
```

```ruby
mutex = conn.mutex_new("jobs/1", ttl: 10)
mutex.lock

mutex.lock(2) do |mu|
  # will not be executed, because the TTL is 10 second, and the lock will
  # fail and return after 2 seconds
end

mutex.lock(10) do |mu|
  # will be executed, because the TTL is 10 second, and the lock wait 10
  # seconds, and the previous lock wait 2 seconds, so it can lock successfully
end
```
