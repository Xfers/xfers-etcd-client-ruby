# Xfers etcd v3 client
The Etcd v3 client library, provide high level functions for Etcd v3.

# Features
* GET: `get`, `get_all`, `get_prefix`, `get_prefix_count`, `get_range`, `get_range_count`
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

token = conn.get("/config/token")
# token.key == "/config/token", token.value == "token_1"
```

**Get with prefix**
```ruby
conn.put("/personal_accounts/1", "value2")
conn.put("/personal_accounts/2", "value1")
conn.put("/personal_accounts/3", "value3")
conn.put("/biz_accounts/1", "biz_account1")

conn.get_prefix("/personal_accounts/", sort_target: :key, sort_order: :ascend).map { |kv| { key: kv.key, value: kv.value } }
# [
#   {key: "/personal_accounts/1", value: "value2"},
#   {key: "/personal_accounts/2", value: "value1"},
#   {key: "/personal_accounts/3", value: "value3"},
# ]

conn.get_prefix("/personal_accounts/", sort_target: :key, sort_order: :descend).map { |kv| { key: kv.key, value: kv.value } }
# [
#   {key: "/personal_accounts/3", value: "value3"},
#   {key: "/personal_accounts/2", value: "value1"},
#   {key: "/personal_accounts/1", value: "value2"},
# ]

conn.get_prefix("/personal_accounts/", sort_target: :value, sort_order: :ascend).map { |kv| { key: kv.key, value: kv.value } }
# [
#   {key: "/personal_accounts/3", value: "value3"},
#   {key: "/personal_accounts/1", value: "value2"},
#   {key: "/personal_accounts/2", value: "value1"},
# ]
```

**Get range**
```ruby
conn.put("/personal_accounts/1", "value2")
conn.put("/personal_accounts/2", "value1")
conn.put("/personal_accounts/3", "value3")
conn.put("/personal_accounts/4", "value4")

conn.get_range("/personal_accounts/1", "/personal_accounts/4", sort_order: :ascend).map { |kv| { key: kv.key, value: kv.value } }
# [
#   {key: "/personal_accounts/1", value: "value2"},
#   {key: "/personal_accounts/2", value: "value1"},
#   {key: "/personal_accounts/3", value: "value3"},
# ]

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
# Watcher
# will print the following messages:
#
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
# Notifier
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

**Transaction**

This sample code shows how to put the whole balance update procedures in transaction and makes the operation atomically.
```ruby
balanceKv = conn.get("balance")
remaining_balance = balanceKv.value.to_d - 1000

txn_result = conn.transaction do
  response = conn.transaction do |txn|
    # compare the last modification revision to make sure the balanceKv didn't modified by others
    txn.compare = [
      txn.mod_revision("balance", :equal, balanceKv.mod_revision),
    ]

    # set balance key to remaining_balance if compare success
    txn.success = [
      txn.put("balance", remaining_balance.to_s),
    ]

    # return current balance if compare fail
    txn.failure = [
      txn.get("balance"),
    ]
  end

  if txn_result.succeeded
    # the transaction success
  else
    # the transaction failed
    current_balance = txn_result.responses[0].response_range.kvs[0].value.to_d
  end
end

```