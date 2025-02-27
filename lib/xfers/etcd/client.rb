require "etcdv3"
require "monitor"
require_relative "mutex"
require_relative "transaction"

module Xfers
  module Etcd
    # Xfers etcd v3 client class, it wraps {https://www.rubydoc.info/gems/etcdv3/ etcdv3-ruby} gem
    # and provides some advanced feature like: {Mutex}, {#watch_forever}...etc
    class Client
      # Raw {https://www.rubydoc.info/gems/etcdv3/Etcdv3 Etcdv3} instance
      # @return [Etcdv3]
      attr_reader :client

      include MonitorMixin

      # Create a new etcd client connection
      #
      # @param endpoints [String] the etcd server endpoints, seperated by commas
      # @param allow_reconnect [Boolean] allow to reconnect, defaults to `true`
      # @param command_timeout [Integer] the default global timeout, unit is second, defaults to `120`
      # @param user [String] the username for authentication (if RBAC enabled on server side)
      # @param password [String] the user password for authentication (if RBAC enabled on server side)
      def initialize(**options)
        @client = ::Etcdv3.new(**options)

        super() # Monitor#initialize
      end

      # Version of Etcd running on member
      #
      # @return [String] version string
      def version
        synchronize(&:version)
      end

      # Store size in bytes.
      #
      # @return [Integer] the size of the backend database, in bytes.
      def db_size
        synchronize(&:db_size)
      end

      # Check if a key exist
      #
      # @param key [String] key
      #
      # @return [Boolean] key exists or not
      def exist?(key)
        synchronize do |client|
          self.class.valid_string_argument?("key", key)
          count = client.get(key, count_only: true)&.count
          !count.nil? && count > 0
        end
      end

      # Get the key-value object of a key from etcd
      #
      # @param key [String] key to get
      #
      # @return [Mvccpb::KeyValue] the value of key
      def get(key)
        synchronize do |client|
          self.class.valid_string_argument?("key", key)
          client.get(key).kvs.first
        end
      end

      # Get all key-value objects currently stored
      #
      # @return [Array<Mvccpb::KeyValue>] sequence of key-value object
      def get_all
        synchronize do |client|
          client.get("\0", range_end: "\0").kvs
        end
      end

      # Get a range of key-value objects with the prefix
      #
      # @param key_prefix [String] the key prefix
      # @param keys_only [Boolean] returns only the keys.
      # @param sort_target [Symbol] sort target, possible values: `:key`, `:version`, `:create`, `:mode`, `:value`
      # @param sort_order [Symbol] sort order, possible values: `:none`, `:ascend`, `:descend`
      #
      # @return [Array<Mvccpb::KeyValue>] sequence of key-value objects
      def get_prefix(key_prefix, keys_only: false, sort_target: :key, sort_order: :none)
        synchronize do |client|
          self.class.valid_string_argument?("key_prefix", key_prefix)
          options = {
            range_end: prefix_range_end(key_prefix),
            keys_only: keys_only,
            sort_target: sort_target,
            sort_order: sort_order,
          }
          client.get(key_prefix, **options).kvs
        end
      end

      # Get the count of keys with the prefix
      # @param key_prefix [String] the key prefix
      #
      # @return [Integer] the count of keys with the prefix
      def get_prefix_count(key_prefix)
        synchronize do |client|
          self.class.valid_string_argument?("key_prefix", key_prefix)
          client.get(key_prefix, range_end: prefix_range_end(key_prefix), count_only: true).count
        end
      end

      # Get a range of key-value objects
      #
      # @param range_start [String] first key in range
      # @param range_end [String] last key in range, exclusive
      # @param keys_only [Boolean] returns only the keys.
      # @param sort_target [Symbol] sort target, possible values: `:key`, `:version`, `:create`, `:mode`, `:value`
      # @param sort_order [Symbol] sort order, possible values: `:none`, `:ascend`, `:descend`
      #
      # @return [Array<Mvccpb::KeyValue>] sequence of  key-value objects
      def get_range(range_start, range_end, keys_only: false, sort_target: :key, sort_order: :none)
        synchronize do |client|
          self.class.valid_string_argument?("range_start", range_start)
          self.class.valid_string_argument?("range_end", range_end)
          options = {
            range_end: range_end,
            keys_only: keys_only,
            sort_target: sort_target,
            sort_order: sort_order,
          }
          client.get(range_start, **options).kvs
        end
      end

      # Get the count of key range
      # @param range_start [String] first key in range
      # @param range_end [String] last key in range, exclusive
      #
      # @return [Integer] the count of key range
      def get_range_count(range_start, range_end)
        synchronize do |client|
          self.class.valid_string_argument?("range_start", range_start)
          self.class.valid_string_argument?("range_end", range_end)
          client.get(range_start, range_end: range_end, count_only: true).count
        end
      end

      # Set a value to specific key
      #
      # @param key [String] key name
      # @param value [String] the value of key
      # @param ttl [Integer] the advisory time-to-live in seconds, defaults to live forever
      # @param lease [Integer] lease attached to the key, if ttl and lease are both provided, it will use ttl
      #
      # @return [void]
      def put(key, value, ttl: nil, lease: nil)
        synchronize do |client|
          self.class.valid_string_argument?("key", key)
          options = {}
          options[:lease] = lease unless lease.nil?
          options[:lease] = self.lease_grant(ttl) if ttl&.respond_to?(:to_i)
          client.put(key, value.to_s, **options)
          nil
        end
      end

      # Delete a single key
      #
      # @param key [String] key to set
      #
      # @return [Integer] number of keys deleted
      def del(key)
        synchronize do |client|
          self.class.valid_string_argument?("key", key)
          client.del(key, **{}).deleted
        end
      end

      # Delete all keys
      #
      # @return [Integer] number of keys deleted
      def del_all
        synchronize do |client|
          client.del("\0", range_end: "\0").deleted
        end
      end

      # Delete a range of keys with a prefix
      #
      # @param key_prefix [String] first key in range
      #
      # @return [Integer] number of keys deleted
      def del_prefix(key_prefix)
        synchronize do |client|
          self.class.valid_string_argument?("key_prefix", key_prefix)
          options = {
            range_end: prefix_range_end(key_prefix),
          }
          client.del(key_prefix, **options).deleted
        end
      end

      # Delete a range of keys
      #
      # @param range_start [String] first key in range
      # @param range_end [String] last key in range, exclusive
      #
      # @return [Integer] number of keys deleted
      def del_range(range_start, range_end)
        synchronize do |client|
          self.class.valid_string_argument?("range_start", range_start)
          self.class.valid_string_argument?("range_end", range_end)
          options = {
            range_end: range_end,
          }
          client.del(range_start, **options).deleted
        end
      end

      # Create a new lease
      #
      # @param ttl [Integer] the advisory time-to-live in seconds
      #
      # @return [Integer] lease id
      def lease_grant(ttl)
        synchronize do |client|
          self.class.valid_ttl?(ttl)
          client.lease_grant(ttl)["ID"]
        end
      end

      # Revoke a lease
      #
      # @param lease_id [Integer] the lease ID for the lease
      #
      # @return [void]
      def lease_revoke(lease_id)
        synchronize do |client|
          self.class.valid_lease_id?(lease_id)
          client.lease_revoke(lease_id)
          nil
        end
      end

      # Query the TTL of lease
      #
      # @param lease_id [Integer] the lease ID for the lease
      #
      # @return [Integer] the remaining TTL in seconds for the lease
      def lease_ttl(lease_id)
        synchronize do |client|
          self.class.valid_lease_id?(lease_id)
          client.lease_ttl(lease_id)["TTL"]
        end
      end

      # Keep the lease alive
      #
      # @param lease_id [Integer] the lease ID for the lease
      #
      # @return [Integer] the remaining TTL in seconds for the lease
      def lease_keep_alive_once(lease_id)
        synchronize do |client|
          self.class.valid_lease_id?(lease_id)
          client.lease_keep_alive_once(lease_id)["TTL"]
        end
      end

      # Create a new mutex instance
      #
      # @param name [String] the mutex name, the same name of different mutes instance will be treat the same
      # @param ttl [Integer] the time-to-live in seconds of this mutex when mutex lock perform, the lock will
      #   be released after this time elapses, unless refreshed.
      #
      # @return [Xfers::Etcd::Mutex] a new mutex instance
      def mutex_new(name, ttl: 60)
        self.class.valid_string_argument?("name", name)
        self.class.valid_ttl?(ttl)
        Mutex.new(name, ttl: ttl, conn: self)
      end

      # Watch for changes on a key
      #
      # @param key [String] the key to register for watching
      # @param timeout [Integer]  the most waiting time in seconds, defaults to :command_timeout options
      # @param start_revision [Integer] the revision for where to inclusively begin watching
      #
      # @yieldparam [Array<Mvccpb::Event>] events a list of new events in sequence
      #
      # @return [Array<Mvccpb::Event>, Nil] return events when event arrives if no given block, Nil when timed out or has given block
      def watch(key, timeout: nil, start_revision: nil, &block)
        synchronize do |client|
          self.class.valid_string_argument?("key", key)
          client.watch(key, timeout: timeout, start_revision: start_revision, &block)
        rescue GRPC::DeadlineExceeded
          nil
        end
      end

      # Watch forever for a key changes
      #
      # @param key [String] the key to register for watching
      # @param start_revision [Integer] the revision for where to inclusively begin watching
      #
      # @yieldparam [Array<Mvccpb::Event>] events a list of new events in sequence
      #
      # @return [void]
      def watch_forever(key, start_revision: nil, &block)
        synchronize do |client|
          self.class.valid_string_argument?("key", key)
          loop do
            client.watch(key, timeout: 60, start_revision: start_revision, &block)
          rescue GRPC::DeadlineExceeded
            next
          end
        end
        nil
      end

      # Watch for changes on a specified key prefix
      #
      # @param key_prefix [String] first key in range
      # @param timeout [Integer] the most waiting time in seconds, defaults to :command_timeout options
      # @param start_revision [Integer] the revision for where to inclusively begin watching
      #
      # @yieldparam [Array<Mvccpb::Event>] events a list of new events in sequence
      #
      # @return [Array<Mvccpb::Event>, Nil] return events when event arrives if no given block, Nil when timed out or has given block
      def watch_prefix(key_prefix, timeout: nil, start_revision: nil, &block)
        synchronize do |client|
          self.class.valid_string_argument?("key_prefix", key_prefix)
          client.watch(key_prefix, range_end: prefix_range_end(key_prefix), timeout: timeout, start_revision: start_revision, &block)
        rescue GRPC::DeadlineExceeded
          nil
        end
      end

      # Watch forever for changes on a specified key prefix
      #
      # @param key [String] the key to register for watching
      # @param start_revision [Integer] the revision for where to inclusively begin watching
      #
      # @return [void]
      def watch_prefix_forever(key_prefix, start_revision: nil, &block)
        synchronize do |client|
          self.class.valid_string_argument?("key_prefix", key_prefix)
          loop do
            client.watch(key_prefix, range_end: prefix_range_end(key_prefix), timeout: 120, start_revision: start_revision, &block)
          rescue GRPC::DeadlineExceeded
            next
          end
        end
      end

      # Transaction
      #
      # @yieldparam [Xfers::Etcd::Transaction] txn the transaction opertaion object
      #
      # @return [Etcdserverpb::TxnResponse]
      def transaction(timeout: nil, &block)
        synchronize do |client|
          client.transaction(timeout: timeout, &block)
        end
      end

      private def prefix_range_end(key)
        bytes = key.dup.codepoints.to_a
        (bytes.length - 1).downto(0).each do |i|
          if bytes[i] < 0xFF
            bytes[i] = bytes[i] + 1
            return bytes[0..i].pack("U*")
          end
        end
        "\0"
      end

      # @private
      def synchronize
        mon_synchronize { yield(@client) }
      end

      # @private
      def self.valid_string_argument?(name, value)
        raise ArgumentError, "#{name} argument needs to be a non-empty string" if !value.is_a?(String) || value.empty?
      end

      # @private
      def self.valid_ttl?(ttl)
        raise ArgumentError, "ttl argument needs to be a non-empty string" if !ttl.is_a?(Integer) || ttl < 1
      end

      # @private
      def self.valid_lease_id?(lease_id)
        raise ArgumentError, "lease_id argument needs to be a non-empty string" unless lease_id.is_a?(Integer)
      end
    end # end of Client class
  end
end
