require_relative '../yes_no_item'
require 'etc'

module Simp; end
class Simp::Cli; end
module Simp::Cli::Config
  class Item::CliLocalPrivUserHasAuthorizedSshKeys < YesNoItem
    attr_accessor :local_repo
    def initialize(puppet_env_info = DEFAULT_PUPPET_ENV_INFO)
      super(puppet_env_info)
      @key         = 'cli::local_priv_user_has_authorized_ssh_keys'
      @description = 'Whether the local privileged user has an authorized ssh keys file'

      @data_type  = :internal  # don't persist this as it needs to be
                               # evaluated each time simp config is run
    end

    def get_os_value
      username   = get_item( 'cli::local_priv_user' ).value
      info = Etc.getpwnam(username)
      result = nil
      if (info.dir.empty? || (info.dir == '/dev/null'))
        result = 'no'
      else
        authorized_keys_file = File.join(info.dir, '.ssh', 'authorized_keys')
        result = (File.exist?(authorized_keys_file) ? 'yes' : 'no')
      end

      result
    end

    def get_recommended_value
      os_value
    end
  end
end
