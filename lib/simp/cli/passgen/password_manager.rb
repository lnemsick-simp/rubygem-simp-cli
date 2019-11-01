require 'highline/import'
require 'simp/cli/exec_utils'
require 'simp/cli/passgen/utils'
#require 'simp/cli/utils'
require 'tmpdir'

class Simp::Cli::Passgen::PasswordManager

  def initialize(environment, backend, folder)
    @environment = environment
    @backend = backend
    @folder = folder
    @puppet_info = Simp::Cli::Utils.puppet_info(@environment)

    @location = "#{@environment} Environment"
    @location += " in #{@backend} backend" unless @backend.nil?
    @custom_options = @backend.nil? ? nil : "{ 'backend' => '#{@backend}' }"

    @list = nil
  end

  #####################################################
  # Operations
  #####################################################

  # Remove a list of passwords
  #
  # Removes the listed passwords in the key/value store.
  #
  # @param names Array of names(keys) of passwords to remove
  # @param force_remove Whether to remove password files without prompting
  #   the user to verify the removal operation
  #
  def remove_passwords(names, force_remove=false)
    validate_names(names)

    # Load in available password info
    list = password_list

    names.each do |name|
      remove = force_remove
      unless remove
        prompt = "Are you sure you want to remove all entries for '#{name}'?".bold
        remove = Simp::Cli::Passgen::Utils::yes_or_no(prompt, false)
      end

      if remove
        fullname = @folder.nil? ? name : "#{@folder}/#{name}"
        begin
          args = "'#{fullname}'"
          args += ", #{@custom_options}" if @custom_options
          manifest = "simplib::passgen::remove(#{args})"
          apply_manifest(manifest)
          puts "Deleted #{fullname} in #{@location}"
        rescue Exception => e
          # Will report all problems at end.
          errors << "'#{fullname}': #{e}"
        end
      end

      puts
    end

    unless errors.empty?
      err_msg = "Failed to delete the following password keys in #{@location}:\n  #{errors.join("\n  ")}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

  # Set a list of passwords to values selected by the user
  #
  #
  # @param names Array of names of passwords to set
  # @param options Hash of password generation options.
  #   * Required keys:
  #     * :auto_gen - whether to auto-generate new passwords
  #     * :force_value - whether to accept passwords entered by user without
  #       validation
  #     * :default_length - default password length of auto-generated passwords.
  #     * :minimum_length - minimum password length
  #
  #   * Optional keys:
  #     * :length - requested length of auto-generated passwords.
  #       * When nil, the password exists, and the existing password length
  #         >='minimum_length', use the length of the existing password
  #       * When nil, the password exists, and the existing password length
  #         < 'minimum_length', use the 'default_length'
  #       * When nil and the password does not exist, use 'default_length'
  #
  def set_passwords(names, options)
    validate_set_config(names, options)

    puppet_user = @puppet_info[:config]['user']
    puppet_group = @puppet_info[:config]['group']
    errors = []
    names.each do |name|
      next if name.strip.empty?

      puts "Processing Name '#{name}' in #{@location}"
      begin
        gen_options = options.dup
        gen_options[:length] = get_password_length(password_filename, options)
        password, generated = get_new_password(gen_options)
        if generated
          puts "  Password set to '#{password}'" if generated
        else
          puts '  Password set'
        end
     # Will report all problems at end.
      rescue Simp::Cli::ProcessingError => err
        errors << "'#{name}': #{err.message}"
      rescue ArgumentError => err
        # This will happen if group does not exist
        err_msg = "'#{name}': Could not set password file ownership for '#{password_filename}': #{err}"
        errors << err_msg
      rescue SystemCallError => err
        err_msg = "'#{name}': Error occurred while writing '#{password_filename}': #{err}"
        errors << err_msg
      end

    end

    unless errors.empty?
      err_msg = "Failed to set #{errors.length} out of #{names.length} passwords:\n  #{errors.join("\n  ")}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

  # Prints the list of password names for the environment to the console
  def show_name_list
    # empty result means no keys found
    names = password_list.key?('keys') ? password_list['keys'].keys : []
    puts "#{@location} Names:\n  #{names.sort.join("\n  ")}"
    puts
  end

  # Prints password info for the environment to the console.
  #
  # For each password name, prints its current value, and when present, its
  # previous value.
  #
  # TODO:  Print out all other available information.
  #
  def show_passwords(names)
    validate_names(names)

    # Load in available password info
    list = password_list

    prefix = @custom_password_dir ? @password_dir : "#{@environment} Environment"
    title =  "#{prefix} Passwords"
    puts title
    puts '='*title.length
    errors = []
    names.each do |name|
      puts "Name: #{name}"
      if list['keys'].key?(name)
        info = list['keys'][name]
        puts "  Current:  #{info['value']['password']}"
        unless info['metadata']['history'].empty?
          puts "  Previous: #{info['metadata']['history'][0][0]}"
        end
      else
        puts '  UNKNOWN'
        errors << name
      end
      puts
    end

    unless errors.empty?
      err_msg = "Failed to fetch password info for the following:\n  #{errors.join("\n  ")}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

  #####################################################
  # Helpers
  #####################################################

  # @param manifest Contents of the manifest to be applied
  # @param name Basename of the manifest
  #
  def apply_manifest(manifest, name = 'passgen')
    result = {}
    Dir.mktmpdir( File.basename( __FILE__ ) ) do |dir|
      manifest_file = File.join(dir, "#{name}.pp")
      File.open(manifest_file, 'w') { |file| file.puts manifest }
      puppet_apply = [
        'puppet apply',
        '--color=false',
        "--environment=#{@environment}",
        # this is required for finding the correct vardir when either legacy
        # password files or files from the auto-default key/value store are
        # being processed
        "--vardir=#{@puppet_info[:config]['vardir']}",
        manifest_file
      ].join(' ')

      # umask and sg only needed for operations that modify files
      # FIXME  Would really like this to be handled some other way for non-root users
      cmd = "umask 0027 && sg #{@puppet_info[:config]['group']} -c '#{puppet_apply}'"
      result = Simp::Cli::ExecUtils.run_command(cmd)
    end

    unless result[:status]
      err_message = "#{cmd} failed: #{result[:stderr]}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    result
  end

  def extract_yaml_from_log(log)
    # get rid of initial Notice text
    yaml_string = log.gsub(/^.*?\-\-\-/m,'---')

    # get rid of trailing Notice text
    yaml_lines = yaml_string.split("\n").delete_if { |line| line =~ /^Notice:/ }
    yaml_string = yaml_lines.join("\n")
    begin
      yaml = YAML.load(yaml_string)
      return yaml
    rescue Exception =>e
      err_msg = "Failed to extract YAML: #{e}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

  def get_new_password(options)
    password = ''
    generated = false
    if options[:auto_gen]
      password = Simp::Cli::Utils.generate_password(options[:length])
      generated = true
    else
      password = Simp::Cli::Passgen::Utils::get_password(5, !options[:force_value])
    end

    [ password, generated ]
  end

  def get_password_length
    length = nil
    if options[:length].nil?
      if File.exist?(password_file)
        begin
          password = File.read(password_file).chomp
          length = password.length
        rescue Exception => e
          err_msg = "Error occurred while reading '#{password_file}': #{e}"
          raise Simp::Cli::ProcessingError.new(err_msg)
        end
      end
    else
      length = options[:length]
    end

    if length.nil? || (length < options[:minimum_length])
      length = options[:default_length]
    end

    length
  end

  # Retrieve and validate a list of a password folder
  #
  # @raise if manifest apply to retrieve the list fails, the manifest result
  #   cannot be parsed as YAML, or the result does not have the required keys
  def password_list
    return @password_list unless @password_list.nil?

    args = ''
    if @custom_options
      if @folder
        args = "'#{@folder}', #{@custom_options}"
      else
        args = "'/', #{@custom_options}"
      end
    end

    manifest = "notice(to_yaml(simplib::passgen::list(#{args})))"
    result = apply_manifest(manifest, 'list')
    list = extract_yaml_from_log(result[:stdout])

    # make sure results are something we can process...should only have a problem
    # if simplib::passgen::list changes and this software was not updated
    unless valid_password_list?(list)
      err_msg = "Invalid result returned from simplib::passgen::list:\n\n#{list}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    @password_list = list
  end

  def valid_password_list?(list)
    valid = true
    unless list.empty?
      if list.key?('keys')
        list['keys'].each do |name, info|
          unless (
              info.key?('value') && info['value'].key?('password') &&
              info.key?('metadata') && info['metadata'].key?('history') )
            valid = false
            break
          end
        end
      else
        valid = false
      end
    end

    valid
  end

  # @raise Simp::Cli::ProcessingError if names is empty
  def validate_names(names)
    if names.empty?
      err_msg = 'No names specified.'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

  def validate_set_config(names, options)
    validate_password_dir

    if names.empty?
      err_msg = 'No names specified.'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    unless options.key?(:auto_gen)
      err_msg = 'Missing :auto_gen option'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    unless options.key?(:force_value)
      err_msg = 'Missing :force_value option'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    unless options.key?(:default_length)
      err_msg = 'Missing :default_length option'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    unless options.key?(:minimum_length)
      err_msg = 'Missing :minimum_length option'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

end
