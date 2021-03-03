require_relative '../action_item'
require_relative '../data/cli_local_priv_user'
require_relative '../data/cli_local_priv_user_password'

module Simp; end
class Simp::Cli; end
module Simp::Cli::Config
  class Item::CreateLocalUserAction < ActionItem
    def initialize(puppet_env_info = DEFAULT_PUPPET_ENV_INFO)
      super(puppet_env_info)
      @key               = 'cli::create_local_user'
      @description       = 'Create a privileged local user'
      @die_on_apply_fail = true
      @username          = nil
      @category          = :system
    end

    def apply
      @applied_status = :failed
      @username = get_item( 'cli::local_priv_user' ).value
      pwd_hash = get_item( 'cli::local_priv_user_password' ).value

      #TODO Set the user's home dir?
      cmd = "puppet resource user #{@username} password='#{pwd_hash}' ensure=present"

      result = Simp::Cli::Utils::show_wait_spinner {
        execute(cmd)
      }

      @applied_status = :succeeded if result
    end

    def apply_summary
      "Creation of local user#{@username ? " #{@username}" : ''} #{@applied_status}"
    end

  end
end
