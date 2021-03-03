require_relative '../set_server_hieradata_action_item'
require_relative '../data/cli_local_priv_user'
require_relative '../data/pam_access_users'
require_relative '../data/sudo_user_specifications'

module Simp; end
class Simp::Cli; end

module Simp::Cli::Config
  class Item::AllowLocalPrivUserAction < SetServerHieradataActionItem
    def initialize(puppet_env_info = DEFAULT_PUPPET_ENV_INFO)
      @hiera_to_add = [
        'pam::access::users',
        'sudo::user_specifications'
      ]
      super(puppet_env_info)
      @key = 'puppet::allow_local_priv_user'

      # override with a shorter message
      @description = 'Allow ssh+sudo access to local user in SIMP server <host>.yaml'

    end

    # override with a shorter message
    def apply_summary
      username = get_item( 'cli::local_priv_user' ).value
      file = @file ? File.basename(@file) : 'SIMP server <host>.yaml'
      "Configuring ssh+sudo for local user '#{username}' in #{file} #{@applied_status}"
    end
  end
end
