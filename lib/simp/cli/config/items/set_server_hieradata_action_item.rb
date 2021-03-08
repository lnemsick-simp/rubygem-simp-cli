require 'yaml'
require 'simp/cli/config/items/action_item'
require 'simp/cli/config/items/data/cli_network_hostname'
require 'simp/cli/config/utils'

module Simp::Cli::Config
  # An ActionItem that adds/updates a hieradata key in the SIMP server's
  # <host>.yaml file
  # Derived class must set @key and @hiera_to_add where @key must be
  # unique and @hiera_to_add is an array of hiera keys
  class SetServerHieradataActionItem < ActionItem

    def initialize(puppet_env_info = DEFAULT_PUPPET_ENV_INFO)
      super(puppet_env_info)
      @dir         = File.join(@puppet_env_info[:puppet_env_datadir], 'hosts')
      @description = "Set #{@hiera_to_add.join(', ')} in SIMP server <host>.yaml"
      @file        = nil
      @category    = :puppet_env_server
      @merge_value = false # whether to merge an Item's value with its existing
                           # value in the hiera file; only applies when the
                           # value is an array or a Hash
    end

    def apply
      "#{@hiera_to_add} not set!" if @hiera_to_add.nil?

      @applied_status = :failed
      fqdn  = get_item( 'cli::network::hostname' ).value
      @file = File.join( @dir, "#{fqdn}.yaml")

      successes = 0
      if File.exists?(@file)
        @hiera_to_add.each do |key|
          info( "Processing #{key} in #{File.basename(@file)}" )
          # reread info because we are writing out to file with every key
          file_info = load_yaml_with_comment_blocks(@file)
          item = get_valid_item(key)

          if file_info[:content].key?(key)
            change = merge_or_replace_yaml_tag(item.key, item.value, file_info,
              @merge_value)

            if change == :none
              info( "No change to #{item.key} required in #{File.basename(@file)}" )
            else
              info( "#{item.key} #{change}d in #{File.basename(@file)}" )
            end
          else
            # want to insert before the first classes array is found, since
            # the classes arrays are typically at the end of the SIMP server
            # hiera file
            classes_key_regex = Regexp.new(/^(simp::(server::)?)?classes$/)
            add_yaml_tag_directive(item.to_yaml_s, file_info, classes_key_regex)
            info( "#{item.key} added to #{File.basename(@file)}" )
          end
          successes += 1
        end

        @applied_status = :succeeded if (successes == @hiera_to_add.size)
      else
        error( "\nERROR: file not found: #{@file}", [:RED] )
      end
    end

    def apply_summary
      file = @file ? File.basename(@file) : 'SIMP server <host>.yaml'
      key_list = @hiera_to_add.join(', ')
      "Setting of #{key_list} in #{file} #{@applied_status}"
    end

    def get_valid_item(key)
      item = get_item(key)
      if item.skip_yaml
        # Only get here if the Item explicitly disables YAML generation, which
        # means the decision tree is misconfigured!
        raise InternalError, "YAML generation for #{key} is suppressed"
      end

      item
    end
  end
end
