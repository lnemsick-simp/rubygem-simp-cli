require_relative '../yes_no_item'

module Simp; end
class Simp::Cli; end

module Simp::Cli::Config
  class Item::SimpYumRepoLocalOsUpdatesEnableRepo < YesNoItem
    def initialize(puppet_env_info = DEFAULT_PUPPET_ENV_INFO)
      super(puppet_env_info)
      @key         = 'simp::yum::repo::local_os_updates::enable_repo'
      @description = 'Whether to enable the SIMP-managed OS Update YUM repository.'
      @data_type   = :server_hiera
    end

    # NOTE: The default is 'no', because we are only using this to
    # turn off the repo in the SIMP server host YAML.
    def get_recommended_value
      'no'
    end
  end
end
