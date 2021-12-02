require "securerandom"
require_relative "errors"

module Xfers
  module Etcd
    # Mutex class for distributed lock
    class Mutex
      attr_reader :key, :uuid

      # Create a new mutex instance
      #
      # @param name [String] the mutex name. The mutex instance with the same name will be treat as indivisual mutex
      #   which try to lock the same resource.
      # @param ttl [Integer] the time-to-live in seconds of this mutex when mutex lock perform, the lock will
      #   be released after this time elapses, unless refreshed.
      #
      # @return [Xfers::Etcd::Mutex] a new mutex instance
      def initialize(name, ttl: 60, conn: nil)
        Xfers::Etcd::Client.valid_string_argument?("name", name)
        @key = "/etcd_mutex/#{name}"
        @lease_id = nil
        @ttl = ttl
        @revision = -1
        @conn = conn
        @uuid = SecureRandom.uuid
      end

      # Acquire the lock
      #
      # @param timeout [Integer] Maximum time in seconds to wait before returning.
      #   0 means return immediately if lock fail, and < 0 means wait forever.
      #
      # @yield a block to be called after lock acquired
      # @yieldparam [Xfers::Etcd::Mutex] the self mutex object
      #
      # @return [Boolean] true if the lock has been acquired, false otherwise.
      def lock(timeout = 10, &block)
        lock_impl(false, timeout, &block)
      end

      # Acquire the lock, raise Xfers::Etcd::LockError or Xfers::Etcd::UnockError if lock timeout
      #
      # @param timeout [Integer] Maximum time in seconds to wait before returning.
      #   0 means return immediately if lock fail, and < 0 means wait forever.
      #
      # @yield a block to be called after lock acquired
      # @yieldparam [Xfers::Etcd::Mutex] the self mutex object
      def lock!(timeout = 10, &block)
        lock_impl(true, timeout, &block)
      end

      # Try to acquire the lock, and return false immediately when failed to acquire/relase lock
      #
      # @yield a block to be called after lock acquired
      # @yieldparam [Xfers::Etcd::Mutex] the self mutex object
      #
      # @return [Boolean] true if the lock has been acquired, false otherwise.
      def try_lock(&block)
        lock_impl(false, 0, &block)
      end

      # Try to acquire the lock and raise error immediately  when failed to acquire/relase lock,
      # raise Xfers::Etcd::LockError when failed to acquire lock,
      # raise Xfers::Etcd::UnlockError when failed to release lock
      #
      # @yield a block to be called after lock acquired
      # @yieldparam [Xfers::Etcd::Mutex] the self mutex object
      def try_lock!(&block)
        lock_impl(true, 0, &block)
      end

      private def lock_impl(raise_error, timeout, &block)
        raise ArgumentError, "timeout needs to be a number" unless timeout.is_a?(Numeric)

        @conn.synchronize do
          # try to acuire lock
          deadline = Time.now.to_f + timeout if timeout > 0

          loop do
            # try to acquire the lock
            acquire_result = try_acquire

            # break the loop if the lock acquired
            break if acquire_result

            # return immediately if timeout is zero
            if timeout.is_a?(Numeric) && timeout == 0
              return false unless raise_error
              raise ::Xfers::Etcd::LockError.new, "Key: #{@key}, UUID: #{@uuid} timeout"
            end

            # start to wait lock release
            if timeout > 0
              remaining_timeout = [(deadline - Time.now.to_f), 0].max
              if remaining_timeout == 0
                return false unless raise_error
                raise ::Xfers::Etcd::LockError.new, "Key: #{@key}, UUID: #{@uuid} timeout"
              end
            else
              remaining_timeout = nil
            end

            wait_delete_event(remaining_timeout)
          end

          return raise_error ? nil : true unless block_given?

          begin
            block.call self
            raise_error ? nil : true
          ensure
            unlock_result = unlock
            raise ::Xfers::Etcd::UnlockError.new, "Key: #{@key}, UUID: #{@uuid} timeout" if unlock_result == false && raise_error
          end
        end # end of synchronize
      end

      # Release the lock
      #
      # @return [Boolean] lock released success or not
      def unlock
        @conn.synchronize do |conn|
          response = conn.transaction do |txn|
            txn.compare = [
              txn.value(@key, :equal, @uuid)
            ]

            txn.success = [
              txn.del(@key)
            ]

            txn.failure = []
          end
          response.succeeded
        end
      end

      # Force destroy the lock key
      def destroy!
        @conn.synchronize do |conn|
          response = conn.transaction do |txn|
            txn.compare = [
              txn.version(@key, :greater, 0)
            ]

            txn.success = [
              txn.del(@key)
            ]

            txn.failure = []
          end
          response.succeeded
        end
      end

      # Refresh the time-to-live on this lock
      def refresh
        @conn.synchronize do |conn|
          raise NameError, "No lease associated with this lock" unless @lease_id
          conn.lease_keep_alive_once(@lease_id)
        end
      end

      # Check if this lock is currently acquired
      #
      # @return [Boolean] true if the lock has been acquired, false otherwise.
      def locked?
        @conn.synchronize do |conn|
          kv = conn.get(@key)
          return true if kv && kv.value == @uuid
          false
        end
      end

      def lock_exist?
        @conn.synchronize do |conn|
          conn.get(@key, { count_only: true }).count > 0
        end
      end

      private def synchronize
        mon_synchronize { yield(@conn) }
      end

      private def try_acquire
        @lease_id = @conn.lease_grant(@ttl)
        resp = @conn.transaction do |txn|
          txn.compare = [
            txn.create_revision(@key, :equal, 0)
          ]

          txn.success = [
            txn.put(@key, @uuid, @lease_id)
          ]
          txn.failure = [
            txn.get(@key)
          ]
        end

        if resp.succeeded
          @revision = resp.header.revision
          return true
        end

        @revision = resp.responses[0].response_range.kvs[0].mod_revision
        @lease_id = nil
        false
      end

      private def wait_delete_event(remaining_timeout)
        watch_timeout = remaining_timeout || 60
        @conn.client.watch(@key, start_revision: @revision + 1, timeout: watch_timeout) do |events|
          events.each do |event|
            return true if event.type == :DELETE
          end
        end
      rescue GRPC::DeadlineExceeded
        false
      end
    end # end of class Mutex
  end
end
