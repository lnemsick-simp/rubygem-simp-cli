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

      group_cmd = "puppet resource group #{@username} ensure=present"
      result = Simp::Cli::Utils::show_wait_spinner {
        execute(group_cmd)
      }

      home_dir = "/var/local/#{@username}"
      user_cmd = [
        "puppet resource user #{@username}",
        'ensure=present',
        "groups='#{@username}'",
        "password='#{pwd_hash}'",
        "home=#{home_dir}",
        'manageHome=true',
        'shell=/bin/bash'
      ].join(' ')

      result = Simp::Cli::Utils::show_wait_spinner {
        execute(user_cmd)
      }

      @applied_status = :succeeded if result
    end

    def apply_summary
      "Creation of local user#{@username ? " #{@username}" : ''} #{@applied_status}"
    end

  end
end