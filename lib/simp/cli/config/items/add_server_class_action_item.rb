require 'simp/cli/config/items/action_item'
require 'simp/cli/config/items/data/cli_network_hostname'
require 'simp/cli/config/yaml_utils'

module Simp::Cli::Config

  # An ActionItem that adds an entry to a class list in the SIMP server's
  # <host>.yaml file
  # Derived class must set @key and @class_to_add
  class AddServerClassActionItem < ActionItem
    require 'simp/cli/config/yaml_utils'

    def initialize(puppet_env_info = DEFAULT_PUPPET_ENV_INFO)
      super(puppet_env_info)
      @dir         = File.join(@puppet_env_info[:puppet_env_datadir], 'hosts')
      @description = "Add #{@class_to_add} class to SIMP server <host>.yaml"
      @file        = nil
      @category    = :puppet_env_server
      @merge_value = true
    end

    def apply
      raise InternalError.new( "@class_to_add empty for #{self.class}" ) if "#{@class_to_add}".empty?


      @applied_status = :failed
      fqdn    = get_item( 'cli::network::hostname' ).value
      @file    = File.join( @dir, "#{fqdn}.yaml")

      if File.exist?(@file)
        file_info = load_yaml_with_comment_blocks(@file)
        classes_key = get_classes_key(file_info[:content].keys)
        unless classes_key
          # SIMP server YAML is not configured as expected
          err_msg = "Unable to add #{@class_to_add} to the class list in #{File.basename(@file)}."
          err_msg += "\n#{@file} is missing a classes array."
          raise ApplyError, err_msg
        end

        info( "Adding #{@class_to_add} to #{classes_key} in #{File.basename(@file)}.", [:GREEN] )
        merge_yaml_tag(classes_key, [ @class_to_add ], file_info)
        @applied_status = :succeeded
      else
        error( "\nERROR: file not found: #{@file}", [:RED] )
      end
    end

    def apply_summary
      file = @file ? File.basename(@file) : 'SIMP server <host>.yaml'
      "Addition of #{@class_to_add} to #{file} class list #{@applied_status}"
    end

    # @param Array of keys
    # @return which classes key is found in keys or nil if none is found
    def get_classes_key(keys)
      classes_key = nil
      if keys.include?('simp::server::classes')
        classes_key = 'simp::server::classes'
      elsif keys.include?('simp::classes')
        classes_key = 'simp::classes'
      elsif keys.include?('classes')
        classes_key = 'classes'
      end

      classes_key
    end
  end
end
