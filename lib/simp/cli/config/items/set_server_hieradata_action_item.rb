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
          # reread info because we are writing out to file with every key
          initial_comment_block, yaml_plus = load_yaml_with_comment_blocks
          item = get_valid_item(key)

          if yaml_plus.key?(key)
            merge_or_replace_yaml_entry(item, initial_comment_block, yaml_plus)
          else
            add_yaml_entry(item, initial_comment_block, yaml_plus)
          end
          successes += 1
        end

        @applied_status = :succeeded if (successes == @hiera_to_add.size)
      else
        error( "\nERROR: file not found: #{@file}", [:RED] )
      end
    end

    def get_valid_item(key)
      item = get_item(key)
      if item.to_yaml_s.nil?
        # Only get here if the Item explicitly disables YAML generation, which
        # means the decision tree is misconfigured!
        raise InternalError, "YAML string for #{key} is not set"
      end

      item
    end

    # Merge/replace value of a YAML entry in the SIMP server hiera file
    #
    # - Leaves file untouched if no changes are required.
    # - Merging is controlled by @merge_value and can only be enabled for
    #   Arrays or Hashes
    # - Hash merges are limited to primary keys. In other words, **no**
    #   deep merging is provided.
    # - Need to make sure all the indentation in the resulting file is
    #   consistent, so, when a value change is required, recreates the file,
    #   preserving blocks of comments (including empty lines) before the
    #   '---' and each major key.
    #   - TODO: Preserve other comments
    #
    def merge_or_replace_yaml_entry(item, initial_comment_block, yaml_plus)
      new_value = item.value
      old_value = yaml_plus[item.key][:value]

      # we always use any existing comment block, so nothing to do
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
    # - Will add the new key before the 1st 'simp::classes',
    #   'simp::server::classes', or 'classes' key, to be consistent with how
    #   the current file organization.
    #   - 'classes' is for backward compatibility with earlier versions of SIMP
    #     and can be removed when logic using it is removed from the site.pp from
    #     simp-environment-skeleton
    # - Need to make sure all the indentation in the resulting file is
    #   consistent, so recreates the file, preserving blocks of comments (including
    #   empty lines) before the '---' and each major key.
    #   - TODO: Preserve other comments
    #
    def add_yaml_entry(item, initial_comment_block, yaml_plus)
      full_yaml_string = item.to_yaml_s

      info( "Adding #{item.key} to #{File.basename(@file)}" )

      # want to insert before the first classes array is found
      classes_key_regex = Regexp.new(/^(simp::(server::)?)?classes$/)
      entry_added = false
      File.open(@file, 'w') do |file|
        file.puts(initial_comment_block.join("\n")) unless initial_comment_block.empty?
        file.puts('---')
        yaml_plus.each do |key, info|
          if !entry_added && key.match?(classes_key_regex)
            file.puts
            file.puts(full_yaml_string.strip)
            entry_added = true
          end
          # use write + \n to eliminate puts dedup of \n
          file.write(info[:comments].join("\n") +  "\n") unless info[:comments].empty?
          file.puts(Simp::Cli::Config::Utils.pair_to_yaml_snippet(key, info[:value]))
        end

        unless entry_added
          file.puts full_yaml_string
        end
      end
    end

    # Merge any new content for a YAML entry in SIMP server hiera file
    #
    # - Only supports Arrays and Hashes
    # - Hash merges are limited to primary keys. In other words, **no**
    #   deep merging is provided.
    #
    def merge_yaml_entry(item, initial_comment_block, yaml_plus)
      new_value = item.value
      old_value = yaml_plus[item.key][:value]

      if old_value.class != new_value.class
        err_msg = "Unable to merge values for #{item.key}:\n" +
          "type mismatch - old type: #{old_value.class}, new type:#{new_value.class}"
        raise InternalError, err_msg
      end

      unless (old_value.is_a?(Array) || old_value.is_a?(Hash))
        err_msg = "Unable to merge values for #{item.key}:\n" +
          "unsupported type #{old_value.class}"
        raise InternalError, err_msg
      end

      return unless merge_required?(old_value, new_value)

      info( "Merging new data into #{item.key} in #{File.basename(@file)}" )

      merged_value = nil
      if old_value.is_a?(Array)
        merged_value = new_value + old_value
      else
        merged_value = old_value.merge(new_value)
      end

      replace_entry_in_file(item.key, merged_value, initial_comment_block, yaml_plus)
    end

    def merge_required?(old_value, new_value)
      merge_required = false
      if old_value.is_a?(Array)
        merge_required = !( (new_value & old_value) == new_value)
      elsif old_value.is_a?(Hash)
        if (new_value.keys & old_value.keys) == new_value.keys
          new_hash.each do |key,value|
            if old_hash[key] != value
              merge_required = true
              break
            end
          end
        else
          merge_required = true
        end
      end

      merge_required
    end


    # Replace a YAML entry in SIMP server hiera file
    #
    # Retains any existing documentation block prior to the entry
    # in the existing YAML file
    #
    def replace_yaml_entry(item, initial_comment_block, yaml_plus)
      info( "Replacing #{item.key} in #{File.basename(@file)}" )
      replace_entry_in_file(item.key, item.value, initial_comment_block, yaml_plus)
    end


    # Replace the value of the named key in the SIMP server hiera file
    def replace_entry_in_file(name, value, initial_comment_block, yaml_plus)
      File.open(@file, 'w') do |file|
        file.puts(initial_comment_block.join("\n")) unless initial_comment_block.empty?
        file.puts('---')
        yaml_plus.each do |key, info|
          # use write + \n to eliminate puts dedup of \n
          file.write(info[:comments].join("\n") +  "\n") unless info[:comments].empty?
          yaml_str = ''
          if key == name
            yaml_str = Simp::Cli::Config::Utils.pair_to_yaml_snippet(key, value)
          else
            yaml_str = Simp::Cli::Config::Utils.pair_to_yaml_snippet(key, info[:value])
          end
          file.puts(yaml_str)
        end
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
  end
end
