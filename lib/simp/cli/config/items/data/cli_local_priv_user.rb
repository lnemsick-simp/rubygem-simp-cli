require_relative '../item'

module Simp; end
class Simp::Cli; end
module Simp::Cli::Config
  class Item::CliLocalPrivUser < Item
    def initialize(puppet_env_info = DEFAULT_PUPPET_ENV_INFO)
      super(puppet_env_info)
      @key         = 'cli::local_priv_user'
      @description = ( <<~EOM
          The local user to configure with `sudo` and `ssh` privileges to prevent server
          lockout after bootstrap.
        EOM
      ).strip

      @data_type  = :cli_params
    end

    def get_recommended_value
      'simp'
    end

    def validate( x )
      x.match(/^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$/) != nil
    end
  end
end
