require "connection_pool"
require_relative "client"
module Xfers
  module Etcd
    # Etcd v3 client connection pool
    class Pool
      def initialize(pool_size: 10, pool_timeout: 10, **options)
        @pool = ConnectionPool.new(pool_size: pool_size, pool_timeout: pool_timeout) do
          Client.new(**options)
        end
      end

      def with(&block)
        @pool.with(&block)
      end

      def pool_shutdown(&block)
        @pool.shutdown(&block)
      end

      def pool_size
        @pool.size
      end

      def pool_available?
        @pool.available
      end

      def watch(key, timeout: nil, &block)
        @pool.with do |client|
          client.watch(key, timeout: timeout, &block)
        end
      end

      def watch_forever(key, &block)
        @pool.with do |client|
          client.watch_forever(key, &block)
        end
      end

      def watch_prefix(key_prefix, timeout: nil, &block)
        @pool.with do |client|
          client.watch(key_prefix, timeout: timeout, &block)
        end
      end

      def watch_prefix_forever(key_prefix, &block)
        @pool.with do |client|
          client.watch_forever(key_prefix, &block)
        end
      end

      def transaction(timeout: nil, &block)
        @pool.with do |client|
          client.transaction(timeout: timeout, &block)
        end
      end

      %i[
        version
        db_size
        get_all
        del_all
      ].each do |method_name|
        define_method(method_name) do
          @pool.with do |client|
            client.send(method_name)
          end
        end
      end

      %i[
        exist?
        get
        del
        del_prefix
        del_range
        lease_grant
        lease_revoke
        lease_ttl
        lease_keep_alive_once
      ].each do |method_name|
        define_method(method_name) do |*args|
          @pool.with do |client|
            client.send(method_name, *args)
          end
        end
      end

      %i[
        get_prefix
        get_range
        put
        mutex_new
      ].each do |method_name|
        define_method(method_name) do |*args, **kargs|
          @pool.with do |client|
            client.send(method_name, *args, **kargs)
          end
        end
      end
    end # end of class Pool
  end
end
