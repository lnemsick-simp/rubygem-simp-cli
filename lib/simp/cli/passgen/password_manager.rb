require 'highline/import'
require 'simp/cli/exec_utils'
require 'simp/cli/passgen/utils'
#require 'simp/cli/utils'

class Simp::Cli::Passgen::PasswordManager

  def initialize(environment, backend, folder)
    @environment = environment
    @backend = backend
    @folder = folder
    @puppet_info = Simp::Cli::Utils.puppet_info(@environment)

    @location = "#{@environment} Environment"
    @location += " in #{@backend} backend" unless @backend.nil?
    @custom_options = @backend.nil? ? nil : "{ 'backend' => '#{@backend}' }"
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
    validate_password_dir
    names = get_names
    prefix = @custom_password_dir ? @password_dir : @environment
    puts "#{prefix} Names:\n  #{names.join("\n  ")}"
    puts
  end
  # Prints password info for the environment to the console.
  #
  # For each password name, prints its current value, and when present, its
  # previous value.
  #
  def show_passwords(names)
    validate_password_dir
    validate_names(names)

    prefix = @custom_password_dir ? @password_dir : "#{@environment} Environment"
    title =  "#{prefix} Passwords"
    puts title
    puts '='*title.length
    errors = []
    names.each do |name|
      Dir.chdir(@password_dir) do
        begin
          puts "Name: #{name}"
          current_password = File.read("#{@password_dir}/#{name}")
          last_password = nil
          last_password_file = "#{@password_dir}/#{name}.last"
          if File.exists?(last_password_file)
            last_password = File.read(last_password_file)
          end
          puts "  Current:  #{current_password}"
          puts "  Previous: #{last_password}" if last_password
        rescue Exception => e
          # Will report all problem details at end.
          puts '  UNKNOWN'
          errors << "'#{name}': #{e}"
        end
      end
      puts
    end

    unless errors.empty?
      err_msg = "Failed to read password info for the following:\n  #{errors.join("\n  ")}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

  #####################################################
  # Helpers
  #####################################################
  #
  def apply_manifest(manifest)
    cmd = "umask 0027 && sg #{@puppet_info[:config]['group']} -c 'puppet apply"
    result = Simp::Cli::ExecUtils.run_command(cmd)
    unless result[:status]
      err_message = "#{cmd} failed: #{result[:stderr]}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end


  def get_names
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

  def validate_names(names)
    if names.empty?
      err_msg = 'No names specified.'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    actual_names = get_names
    names.each do |name|
      unless actual_names.include?(name)
        #FIXME print out names nicely (e.g., max 8 per line)
        err_msg = "Invalid name '#{name}' selected.\n\nValid names: #{actual_names.join(', ')}"
        raise Simp::Cli::ProcessingError.new(err_msg)
      end
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
