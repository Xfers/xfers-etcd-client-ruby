module Xfers
  module Etcd
    # error when client failed to acquire the lock
    class LockError < StandardError; end

    # error when client failed to unlock the lock
    class UnlockError < StandardError; end
  end
end
