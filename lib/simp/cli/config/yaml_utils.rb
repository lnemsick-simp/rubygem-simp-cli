require 'yaml'

module Simp::Cli::Config
  module YamlUtils

    # Parses a YAML file and returns a Hash with following structure
    #  {
    #    :filename => '/the/file/path',
    #    :preamble => [ ... ],  # comment lines that precede '---'
    #    :content  => {
    #      'key1' => {
    #        :comments => [ ... ],  # comment lines that precede the key
    #        :value    => < value for key 1>
    #      },
    #      'key2' => {
    #        :comments => [ ... ],  # comment lines that precede the key
    #        :value    => < value for key 2>
    #      },
    #      ...
    #    }
    #  }
    #
    def load_yaml_with_comment_blocks(filename)
      yaml_hash = YAML.load(IO.read(filename))
      keys = yaml_hash.keys

      content = {}
      start_found = false
      key_index = 0
      key = keys[key_index]
      initial_comment_block = []
      comment_block = []
      raw_lines = IO.readlines(filename)
      raw_lines.each do |line|
        if line.start_with?('---')
          start_found = true
          initial_comment_block = comment_block.dup
          comment_block.clear
          next
        end

        if start_found
          if line.match(/^'?#{key}'?\s*:/)
            content[key] = { :comments => comment_block.dup, :value => yaml_hash[key] }
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

      {
        :filename => filename,
        :preamble => initial_comment_block,
        :content  => content
      }
    end

    # @return String containing the YAML tag directive for the <key,value> pair
    #
    # Examples:
    # * pair_to_yaml('key', 'value') would return "key: value"
    # * pair_to_yaml('key', [1, 2] would return
    #     <<~EOM
    #     key:
    #     - 1
    #     - 2
    #     EOM
    #
    def pair_to_yaml_tag(key, value)
      # TODO: should we be using SafeYAML?  http://danieltao.com/safe_yaml/
      { key => value }.to_yaml.gsub(/^---\s*\n/m, '')
    end

    # Merge/replace value of a key's tag directive in a YAML file
    #
    # - Leaves file untouched if no changes are required.
    # - Merging is controlled by the 'merge' parameter and can only be enabled
    #   for Arrays or Hashes
    # - Hash merges are limited to primary keys. In other words, **no**
    #   deep merging is provided.
    # - In order to make sure all the indentation in the resulting file is
    #   consistent, the file will be recreated with the standard Ruby
    #   YAML library, preserving blocks of comments (including empty lines)
    #   before the '---' and each major key.
    #   - Unnecessary quotes around string values will be removed and spacing
    #     will be normalized to that of the standard Ruby YAML output formatter.
    #     However, these formatting changes are insignificant.
    #   - TODO: Preserve other comments
    #
    # @param key key to update
    # @param new_value value to be merged/replaced
    # @param file_info Hash returned by load_yaml_with_comment_blocks
    # @param merge Whether to merge values for Array or Hash values. When false or
    #   value is not an Array or Hash, the value is replaced instead.
    #
    # @return operation performed: :none, :replace, :merge
    # @raise Exception if standard YAML parsing of the input file fails,
    #   any file operation fails, the value type of the YAML entry to be
    #   merged does not match the new value type (except when either one
    #   is nil).
    #
    def merge_or_replace_yaml_tag(key, new_value, file_info, merge = false)
      change_type = :none
      old_value = file_info[:content][key][:value]

      # we always retain any existing comment block for a key, so nothing to do
      return change_type if new_value == old_value

      if new_value.nil? || old_value.nil?
        change_type = :replace
        replace_yaml_tag(key, new_value, file_info)
      else
        if merge && (new_value.is_a?(Hash) || new_value.is_a?(Array))
          if merge_required?(old_value, new_value)
            change_type = :merge
            merge_yaml_tag(key, new_value, file_info)
          end
        else
          change_type = :replace
          replace_yaml_tag(key, new_value, file_info)
        end
      end

      change_type
    end

    # Add a tag directive to a YAML file
    #
    # - Will add tag_directive before the 1st key that matches
    #  'before_key_regex', when that regex is set
    # - The tag_directive must have been generated with the standard Ruby YAML
    #   library
    # - In order to make sure all the indentation in the resulting file is
    #   consistent, the file will be recreated with the standard Ruby
    #   YAML library, preserving blocks of comments (including empty lines)
    #   before the '---' and each major key.
    #   - Unnecessary quotes around string values will be removed and spacing
    #     will be normalized to that of the standard Ruby YAML output formatter.
    #     However, these formatting changes are insignificant.
    #   - TODO: Preserve other comments
    #
    # @param tag_directive tag directive to add
    # @param file_info Hash returned by load_yaml_with_comment_blocks
    # @param before_key_regex Optional regex specifying where tag directive
    #   should be inserted. When nil or no matching key is found,
    #   tag directive is appended the file.
    #
    def add_yaml_tag_directive(tag_directive, file_info, before_key_regex = nil)
      tag_added = false
      File.open(file_info[:filename], 'w') do |file|
        file.puts(file_info[:preamble].join("\n")) unless file_info[:preamble].empty?
        file.puts('---')
        file_info[:content].each do |k, info|
          if before_key_regex && !tag_added && k.match?(before_key_regex)
            file.puts
            file.puts(tag_directive.strip)
            tag_added = true
          end
          # use write + \n to eliminate puts dedup of \n
          file.write(info[:comments].join("\n") +  "\n") unless info[:comments].empty?
          file.puts(pair_to_yaml_tag(k, info[:value]))
        end

        unless tag_added
          file.puts
          file.puts(tag_directive.strip)
        end
      end
    end

    # Merge the new value for a key into its existing value and then replace
    # its tag directive in the YAML file
    #
    # - Only supports Arrays and Hashes
    # - Hash merges are limited to primary keys. In other words, **no** deep
    #   merging is provided.
    # - In order to make sure all the indentation in the resulting file is
    #   consistent, the file will be recreated with the standard Ruby
    #   YAML library, preserving blocks of comments (including empty lines)
    #   before the '---' and each major key.
    #   - Unnecessary quotes around string values will be removed and spacing
    #     will be normalized to that of the standard Ruby YAML output formatter.
    #     However, these formatting changes are insignificant.
    #   - TODO: Preserve other comments
    #
    # @param key key
    # @param new_value value to be merged
    #
    # @raise if the type of new_value differs from the type of the existing
    #   value or new_value is not an Array or Hash
    #
    def merge_yaml_tag(key, new_value, file_info)
      old_value = file_info[:content][key][:value]

      if old_value.class != new_value.class
        err_msg = "Unable to merge values for #{:key}:\n" +
          "type mismatch - old type: #{old_value.class}, new type:#{new_value.class}"
#FIXME should this be some other error?
        raise InternalError, err_msg
      end

      unless (new_value.is_a?(Array) || new_value.is_a?(Hash))
        err_msg = "Unable to merge values for #{key}:\n" +
          "unsupported type #{new_value.class}"
        raise InternalError, err_msg
      end

      merged_value = nil
      if new_value.is_a?(Array)
        merged_value = new_value + old_value
      else
        merged_value = old_value.merge(new_value)
      end

      replace_yaml_tag(key, merged_value, file_info)
    end

    # @return true if new_value is not contained in old_value, when both values are
    #   either Arrays or Hashes
    #
    def merge_required?(old_value, new_value)
      return false if old_value.class != new_value.class

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

    # Replace tag directive for a key in a YAML file, preserving any existing
    # comment block prior that tag directive
    #
    # @param key key
    # @param new_value replacement value
    # @param file_info Hash returned by load_yaml_with_comment_blocks
    #
    def replace_yaml_tag(key, new_value, file_info)
      File.open(file_info[:filename], 'w') do |file|
        file.puts(file_info[:preamble].join("\n")) unless file_info[:preamble].empty?
        file.puts('---')
        file_info[:content].each do |k, info|
          # use write + \n to eliminate puts dedup of \n
          file.write(info[:comments].join("\n") +  "\n") unless info[:comments].empty?
          yaml_str = ''
          if k == key
            yaml_str = pair_to_yaml_tag(k, new_value)
          else
            yaml_str = pair_to_yaml_tag(k, info[:value])
          end

          file.puts(yaml_str)
        end
      end
    end
  end
end

