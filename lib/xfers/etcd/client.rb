require "etcdv3"
require_relative "./mutex"

module Xfers
  module Etcd
    # Etcd v3 client class
    class Client
      # Raw etcd client connection
      attr_reader :etcd

      extend Forwardable

      # delegate transaction methods
      def_delegators :@etcd, :transaction

      # delegate misc. methods
      def_delegators :@etcd, :version, :db_size, :alarm_list

      def initialize(**options)
        @etcd = ::Etcdv3.new(options)
      end

      # Check if a key exist
      #
      # @param key [String] key
      # @return [Boolean] key exists or not
      def exist?(key)
        self.class.valid_string_argument?("key", key)
        response = self.etcd.get(key)
        !response.kvs.empty?
      end

      # Get the value of a key from etcd
      #
      # @param key [String] key to get
      #
      # @return [Mvccpb::KeyValue] the value of key
      def get(key)
        self.class.valid_string_argument?("key", key)
        self.etcd.get(key).kvs.first
      end

      # Get all keys currently stored
      #
      # @return [Array<Mvccpb::KeyValue>] sequence of key-value object
      def get_all
        self.etcd.get("\0", range_end: "\0").kvs
      end

      # Get a range of keys with a prefix
      #
      # @param key_prefix [String] first key in range
      # @param sort_order [Symbol] sort order, possible values: `:none`, `:ascend`, `:descend`
      # @return [Array<Mvccpb::KeyValue>] sequence of  key-value objects
      def get_prefix(key_prefix, sort_order: :none)
        self.class.valid_string_argument?("key_prefix", key_prefix)
        options = {
          range_end: prefix_range_end(key_prefix),
          sort_order: sort_order,
        }
        self.etcd.get(key_prefix, options).kvs
      end

      # Get a range of keys
      #
      # @param range_start [String] first key in range
      # @param range_end [String] last key in range, exclusive
      # @param sort_order [Symbol] sort order, possible values: `:none`, `:ascend`, `:descend`
      #
      # @return [Array<Mvccpb::KeyValue>] sequence of  key-value objects
      def get_range(range_start, range_end, sort_order: :none)
        self.class.valid_string_argument?("range_start", range_start)
        self.class.valid_string_argument?("range_end", range_end)
        options = {
          range_end: range_end,
          sort_order: sort_order,
        }
        self.etcd.get(range_start, options).kvs
      end

      # Save a value to etcd
      #
      # @param key [String] key to set
      # @param ttl [Integer] the advisory time-to-live in seconds, defaults to live forever
      def put(key, value, ttl: nil)
        self.class.valid_string_argument?("key", key)
        options = {}
        options[:lease] = self.lease_grant(ttl) if ttl&.respond_to?(:to_i)
        self.etcd.put(key, value.to_s, options)
        nil
      end

      # Delete a single key
      #
      # @param key [String] key to set
      #
      # @return [Integer] number of keys deleted
      def del(key)
        self.class.valid_string_argument?("key", key)
        response = self.etcd.del(key, {})
        response.deleted
      end

      # Delete all keys
      #
      # @return [Integer] number of keys deleted
      def del_all
        response = self.etcd.del("\0", range_end: "\0")
        response.deleted
      end

      # Delete a range of keys with a prefix
      #
      # @param key_prefix [String] first key in range
      # @return [Integer] number of keys deleted
      def del_prefix(key_prefix)
        self.class.valid_string_argument?("key_prefix", key_prefix)
        options = {
          range_end: prefix_range_end(key_prefix),
        }
        response = self.etcd.del(key_prefix, options)
        response.deleted
      end

      # Delete a range of keys
      #
      # @param range_start [String] first key in range
      # @param range_end [String] last key in range, exclusive
      # @return [Integer] number of keys deleted
      def del_range(range_start, range_end)
        self.class.valid_string_argument?("range_start", range_start)
        self.class.valid_string_argument?("range_end", range_end)
        options = {
          range_end: range_end,
        }
        response = self.etcd.del(range_start, options)
        response.deleted
      end

      # Create a new lease
      #
      # @param ttl [Integer] the advisory time-to-live in seconds
      # @return [Integer] lease id
      def lease_grant(ttl)
        self.class.valid_ttl?(ttl)
        self.etcd.lease_grant(ttl)["ID"]
      end

      # Revoke a lease
      #
      # @param lease_id [Integer] the lease ID for the lease
      def lease_revoke(lease_id)
        self.class.valid_lease_id?(lease_id)
        self.etcd.lease_revoke(lease_id)
        nil
      end

      # Query the TTL of lease
      #
      # @param lease_id [Integer] the lease ID for the lease
      # @return [Integer] the remaining TTL in seconds for the lease
      def lease_ttl(lease_id)
        self.class.valid_lease_id?(lease_id)
        self.etcd.lease_ttl(lease_id)["TTL"]
      end

      # Keep the lease alive
      #
      # @param lease_id [Integer] the lease ID for the lease
      # @return [Integer] the remaining TTL in seconds for the lease
      def lease_keep_alive_once(lease_id)
        self.class.valid_lease_id?(lease_id)
        self.etcd.lease_keep_alive_once(lease_id)["TTL"]
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

      # Watch for changes on a specified key range
      #
      # @param key [String] the key to register for watching
      # @param timeout [String]  the most waiting time in seconds, defaults to :command_timeout options
      #
      # @return [Array<Mvccpb::Event>, Nil] return events when event arrives, or Nil when timed out
      def watch(key, timeout: nil, &block)
        self.class.valid_string_argument?("key", key)
        self.etcd.watch(key, timeout: timeout, &block)
      rescue GRPC::DeadlineExceeded
        nil
      end

      # Watch forever for changes  on a specified key range
      #
      # @param key [String] the key to register for watching
      def watch_forever(key, &block)
        self.class.valid_string_argument?("key", key)
        loop do
          self.etcd.watch(key, timeout: 60, &block)
        rescue GRPC::DeadlineExceeded
          next
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
