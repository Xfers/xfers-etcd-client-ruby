module Xfers
  module Etcd
    # Alias class to {https://www.rubydoc.info/gems/etcdv3/Etcdv3/KV/Transaction Etcdv3::KV::Transaction} class, for documentation only.
    #
    # The `Etcdserverpb` module documentation is: {https://www.rubydoc.info/gems/etcdv3/Etcdserverpb}
    #
    # Available comparison types: `:equal`, `:greater`, `:less`, `:not_equal`
    class Transaction
      # Set a list of comparision operations representing a conjunction of terms for guarding the transaction
      # @param value [Array<Etcdserverpb::Compare>]
      #
      # @return [void]
      attr_writer :compare

      # Set a list of operations to process if all compare tests evaluate to true
      # @param value [Array<Etcdserverpb::RangeRequest, Etcdserverpb::DeleteRangeRequest, Etcdserverpb::PutRequest>]
      #
      # @return [void]
      attr_writer :success

      # Set a list of operations to process if any compare test evaluates to false
      # @param value [Array<Etcdserverpb::RangeRequest, Etcdserverpb::DeleteRangeRequest, Etcdserverpb::PutRequest>]
      #
      # @return [void]
      attr_writer :failure

      # Put operation in transaction
      # @param key [String] key name
      # @param value [String] the value of key
      # @param lease_id [Integer] the lease id, can use {Xfers::Etcd::Client#lease_grant} method to grant a lease ID
      #
      # @return [Etcdserverpb::PutRequest]
      def put(key, value, lease_id = nil); end

      # Get operation in transaction
      # @param key [String] the key or the first key in range
      # @param opts [Hash]
      # @option opts [String] :range_end the last key in range, exclusive
      # @option opts [Symbol] :sort_target the sort target, possible values: `:key`, `:version`, `:create`, `:mode`, `:value`
      # @option opts [Symbol] :sort_order the sort order, possible values: `:none`, `:ascend`, `:descend`
      #
      # @return [Etcdserverpb::RangeRequest]
      def get(key, opts = {}); end

      # Delete operation in transaction
      # @param key [String] key to set
      #
      # @return [Etcdserverpb::DeleteRangeRequest]
      def del(key, range_end = ""); end

      # Compare operation in transaction, compare the version of key
      # @param key [String] the key to compare
      # @param compare_type [Symbol] the compare type, possible values: `:equal`, `:greater`, `:less`, `:not_equal`
      # @param value [Integer] the key's version
      #
      # @return [Etcdserverpb::Compare]
      def version(key, compare_type, value); end

      # Compare operation in transaction, compare the value of key
      # @param key [String] the key to be compared
      # @param compare_type [Symbol] the compare type, possible values: `:equal`, `:greater`, `:less`, `:not_equal`
      # @param value [String] the value of key, compare by alphabetical order
      #
      # @return [Etcdserverpb::Compare]
      def value(key, compare_type, value); end

      # Compare operation in transaction, compare the last modification revision of key
      # @param key [String] the key to be compared
      # @param compare_type [Symbol] the compare type, possible values: `:equal`, `:greater`, `:less`, `:not_equal`
      # @param value [Integer] the revision of the last modification on the key
      #
      # @return [Etcdserverpb::Compare]
      def mod_revision(key, compare_type, value); end

      # Compare operation in transaction, compare the last creation revision of key
      # @param key [String] the key to be compared
      # @param compare_type [Symbol] the compare type, possible values: `:equal`, `:greater`, `:less`, `:not_equal`
      # @param value [Integer] the revision of the last creation on the key
      #
      # @return [Etcdserverpb::Compare]
      def create_revision(key, compare_type, value); end
    end
  end
end
