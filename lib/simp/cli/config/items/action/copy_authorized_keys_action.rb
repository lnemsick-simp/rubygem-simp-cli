require_relative '../action_item'
require_relative '../data/cli_network_dhcp'
require_relative '../data/cli_network_hostname'
require_relative '../data/cli_network_interface'
require 'etc'
require 'fileutils'

module Simp; end
class Simp::Cli; end
module Simp::Cli::Config
  class Item::CopyAuthorizedKeysAction < ActionItem
    def initialize(puppet_env_info = DEFAULT_PUPPET_ENV_INFO)
      super(puppet_env_info)
      @key               = 'copy::authorized_ssh_keys'
      @description       = 'Copy ssh authorized keys'
      @category          = :system
      @die_on_apply_fail = true
      @username          = nil
    end

    def apply
      @applied_status = :failed
      @username = get_item( 'cli::local_priv_user' ).value

      info = Etc.getpwnam(@username)
      authorized_keys_file = File.join(info.dir, '.ssh', 'authorized_keys')
      dest_dir = '/etc/ssh/local_keys'
      dest = "/etc/ssh/local_keys/#{@username}"
      info( "Copying authorized ssh keys for #{@username} to SIMP-managed #{dest}" )

      begin
        # dest directory may not exist yet
        FileUtils.mkdir_p(dest_dir)
        FileUtils.chmod(0755, dest_dir)
        FileUtils.cp(authorized_keys_file, dest)
        FileUtils.chmod(0644, dest)
        @applied_status = :succeeded
      rescue Exception => e
        error("Copy of #{authorized_keys_file} to #{dest} failed:\n#{e}")
      end
    end

    def apply_summary
      "Copying ssh authorized keys of local user#{@username ? " #{@username}" : ''} #{@applied_status}"
    end
  end
end
