require_relative '../yes_no_item'
require 'etc'

module Simp; end
class Simp::Cli; end
module Simp::Cli::Config
  class Item::CliIsLocalPrivUserSimp < YesNoItem
    def initialize(puppet_env_info = DEFAULT_PUPPET_ENV_INFO)
      super(puppet_env_info)
      @key         = 'cli::is_local_priv_user_simp'
      @description = "Whether the local priviledged user is 'simp'"
      @data_type  = :internal  # don't persist this as it needs to be
                               # evaluated each time simp config is run
    end

    def get_recommended_value
      username = get_item( 'cli::local_priv_user' ).value
      (username == 'simp') ? 'yes' : 'no'
    end
  end
end
