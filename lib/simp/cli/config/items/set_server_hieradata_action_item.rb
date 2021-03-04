require 'yaml'
require 'simp/cli/config/items/action_item'
require 'simp/cli/config/items/data/cli_network_hostname'

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
      @merge_value = false # whether to merge a key's value with its existing
                           # value; only applies when the value is an array
                           # or a Hash
    end

    def apply
      "#{@hiera_to_add} not set!" if @hiera_to_add.nil?

      @applied_status = :failed
      fqdn  = get_item( 'cli::network::hostname' ).value
      @file = File.join( @dir, "#{fqdn}.yaml")

      if File.exists?(@file)
        initial_comment_block, yaml_plus = load_yaml_with_comment_blocks
        @hiera_to_add.each do |key|
          item = get_valid_item(key)

          if yaml_plus.key?(key)
            merge_or_replace_yaml_entry(item, initial_comment_block, yaml_plus)
          else
            add_yaml_entry(key, initial_comment_block, yaml_plus)
          end
          @applied_status = :succeeded
        end
      else
        error( "\nERROR: file not found: #{@file}", [:RED] )
      end
    end

    def get_valid_item(key)
      item = get_item(key)
      if item.to_yaml_s.nil?
        raise InternalError, "YAML string for #{key} is not set"
      end
    end

    def merge_or_replace_yaml_entry(item, initial_comment_block, yaml_plus)
      new_value = item.value
      old_value = yaml_hash[key][:value]

      # not going to attempt to figure out if the comment block needs to
      # be updated
      return if new_value == old_value

      if new_value.nil? || old_value.nil?
        replace_yaml_entry(item, initial_comment_block, yaml_plus)
      else
        if @merge_value && (new_value.is_a?(Hash) || new_value.is_a?(Array))
          merge_yaml_entry(item, initial_comment_block, yaml_plus)
        else
          replace_yaml_entry(item, initial_comment_block, yaml_plus)
        end
      end
    end

    # Add YAML entry to SIMP server hiera file
    #
    # NOTES:
    # - Need to make sure all the indentation in the resulting file
    #   is consistent, so we are going to recreate the file, preserving
    #   blocks of comments before the '---' and before major keys.
    #   - TODO: Preserve other comments
    #   - TODO: Detect when each Item's standard description block has
    #     changed and update the comment.
    # - Will add the new key before the 1st 'simp::classes',
    #   'simp::server::classes', or 'classes' key, to be consistent with how
    #   the current file organization.
    #   - 'classes' is for backward compatibility with earlier versions of SIMP
    #     and can be removed when logic using it is removed from the site.pp from
    #     simp-environment-skeleton
    #
    def add_yaml_entry(item, initial_comment_block, yaml_plus)
      full_yaml_string = item.to_yaml_s

      info( "Adding #{item.key} to #{File.basename(@file)}" )

      # want to insert before the first classes array is found
      classes_key_regex = Regexp.new(/^(simp::(server::)?)?classes\s*:/)
      entry_added = false
      File.open(@file, 'w') do |file|
        file.puts(initial_comment_block.join("\n")) unless initial_comment_block.empty?
        file.puts('---')
        yaml_plus.each do |key, info|
          if key.match?(classes_key_regex)
            f.puts(full_yaml_string)
            entry_added = true
          end
          file.puts(info[:comments].join("\n")) unless info[:comments].empty?
          file.puts({ key => info[:value] }.to_yaml.gsub(/^---\s*\n/m, ''))
        end

        unless entry_added
          f.puts full_yaml_string
        end
      end
    end

    def merge_yaml_entry(item, initial_comment_block, yaml_plus)
      hiera_item = @config_items.fetch( hiera_key )
      new_value = hiera_item.value
      if new_value.nil?
        raise InternalError, "Value for #{hiera_key} is not set"
      end

      if old_value.class != new_value.class
        err_msg = "Unable to merge values: type mismatch #{hiera_key}:\n" +
          "#{old_value.class} vs #{new_value.class}"
        raise InternalError, err_msg
      end

      old_value = yaml_plus[hiera_key][:value]
      if old_value.is_a?(Array)
      else
      end

      info( "Merging new data into #{hiera_key} in #{File.basename(@file)}" )

      
      else
      end
    end


    # Replace a YAML entry in SIMP server hiera file
    #
    # Retains any existing documentation block prior to the entry
    # in the existing YAML file
    #
    def replace_yaml_entry(item, initial_comment_block, yaml_plus)

      info( "Replacing #{hiera_key} in #{File.basename(@file)}" )

      File.open(@file, 'w') do |file|
        file.puts(initial_comment_block.join("\n")) unless initial_comment_block.empty?
        file.puts('---')
        yaml_plus.each do |key, info|
          file.puts(info[:comments].join("\n")) unless info[:comments].empty?
          yaml_str = ''
          if key == item.key
            yaml_str = item.pair_to_yaml_snippet(item.key, item.value)
          else
            yaml_str = item.pair_to_yaml_snippet(key, info[:value])
          end
          f.puts(yaml_string)
        end

    end

    def apply_summary
      file = @file ? File.basename(@file) : 'SIMP server <host>.yaml'
      key_list = @hiera_to_add.join(', ')
      "Setting of #{key_list} in #{file} #{@applied_status}"
    end

    def load_yaml_with_comment_blocks
      yaml_hash = YAML.load(IO.read(@file))
      keys = yaml_hash.keys

      yaml_plus = {}
      start_found = false
      key_index = 0
      key = keys[key_index]
      initial_comment_block = []
      comment_block = []
      raw_lines = IO.readlines(@file)
      raw_lines.each do |line|
        if line.start_with?('---')
          start_found = true
          initial_comment_block = comment_block.dup
          comment_block.clear
          next
        end

        if start_found
          if line.match(/^'?#{key}'?\s*:/)
            yaml_plus[key] = { :comments => comment_block.dup, :value => yaml_hash[key] }
            key_index += 1
            key = keys[key_index]
            comment_block.clear
          elsif (line[0] == '#') || line.strip.empty?
            comment_block << line.strip
          end
        else
          comment_block << line
        end
      end
      [ initial_comment_block, yaml_plus]
    end

    def write_yaml_with_comment_blocks(initial_comment_block, yaml_plus)
      File.open(@file, 'w') do |file|
        file.puts(initial_comment_block.join("\n")) unless initial_comment_block.empty?
        file.puts('---')
        yaml_plus.each do |key, info|
          file.puts(info[:comments].join("\n")) unless info[:comments].empty?
          file.puts({ key => info[:value] }.to_yaml.gsub(/^---\s*\n/m, ''))
        end
      end
    end
  end
end
