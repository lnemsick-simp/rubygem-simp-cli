require 'highline/import'
require 'simp/cli/passgen/utils'
require 'simp/cli/utils'

# Class that provides legacy `simp passgen` operations for environments having
# old simplib module versions that do not support password management beyond
# the simplib::passgen() function.
#
class Simp::Cli::Passgen::LegacyPasswordManager
  require 'fileutils'

  def initialize(environment, password_dir = nil)
    @environment = environment
    @puppet_info = Simp::Cli::Utils.puppet_info(@environment)
    if password_dir.nil?
      @password_dir = get_password_dir
      @custom_password_dir = false
    else
      @password_dir = password_dir
      @custom_password_dir = true
    end
  end

  #########################################################
  # Operations
  #########################################################

  # Remove a list of passwords
  #
  # Removes all password files for the list of password names, including salt
  # files and backups of the password and salt files.
  #
  # @param names Array of names of passwords to remove
  # @param force_remove Whether to remove password files without prompting
  #   the user to verify the removal operation
  #
  def remove_passwords(names, force_remove=false)
    validate_password_dir
    validate_names(names)

    errors = []
    names.each do |name|
      remove = force_remove
      unless remove
        prompt = "Are you sure you want to remove all entries for #{name}?"
        remove = Simp::Cli::Passgen::Utils::yes_or_no(prompt, false)
      end

      if remove
        [
          File.join(@password_dir, name),
          File.join(@password_dir, "#{name}.salt"),
          File.join(@password_dir, "#{name}.last"),
          File.join(@password_dir, "#{name}.salt.last")
        ].each do |file|
          if File.exist?(file)
            begin
              File.unlink(file)
              puts "Deleted #{file}"
            rescue Exception => e
              # Will report all problems at end.
              errors << "'#{file}': #{e}"
            end
          end
        end
      end

      puts
    end

    unless errors.empty?
      err_msg = "Failed to delete the following password files:\n  #{errors.join("\n  ")}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

  # Set a list of passwords to values entered by the user
  #
  # For each password name, backups up existing password files and  creates a
  # new password file.  Does not create a salt file, but relies on
  # simplib::passgen to generate one the next time the catalog is compiled.
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
  #       * When nil, the existing password exists, and the existing password length
  #         >='minimum_length', use the length of the existing password
  #       * When nil, the existing password exists, and the existing password length
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
      password_filename = "#{@password_dir}/#{name}"

      location = @custom_password_dir ? @password_dir : "#{@environment} Environment"
      puts "Processing Name '#{name}' in #{location}"
      begin
        gen_options = options.dup
        gen_options[:length] = get_password_length(password_filename, options)
        password, generated = get_new_password(gen_options)
        backup_password_files(password_filename) if File.exists?(password_filename)

        FileUtils.mkdir_p(@password_dir)
        File.open(password_filename, 'w') { |file| file.puts password }

        # Ensure that the ownership and permissions are correct
        FileUtils.chown(puppet_user, puppet_group, password_filename)
        FileUtils.chmod(0640, password_filename)

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

      puts
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

  #########################################################
  # Helpers
  #########################################################
  def backup_password_files(password_filename)
    begin
      FileUtils.mv(password_filename, password_filename + '.last', :verbose => true, :force => true)
      salt_filename = password_filename + '.salt'
      if File.exists?(salt_filename)
        FileUtils.mv(salt_filename, salt_filename + '.last', :verbose => true, :force => true)
      end
    rescue SystemCallError => err
      err_msg = "Error occurred while backing up '#{password_filename}': #{err}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

  def get_names
    names = []
    begin
      Dir.chdir(@password_dir) do
        names = Dir.glob('*').select do |x|
          File.file?(x) && (x !~ /\.salt$|\.last$/)  # exclude salt and backup files
        end
      end
    rescue SystemCallError => err
      err_msg = "Error occurred while accessing '#{@password_dir}': #{err}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
    names.sort
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

  def get_password_dir
    password_env_dir = File.join(@puppet_info[:config]['vardir'], 'simp', 'environments')
    File.join(password_env_dir, @environment, 'simp_autofiles', 'gen_passwd')
  end

  def get_password_length(password_file, options)
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

  def validate_password_dir
    unless File.exist?(@password_dir)
      err_msg = "Password directory '#{@password_dir}' does not exist"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    unless File.directory?(@password_dir)
      err_msg = "Password directory '#{@password_dir}' is not a directory"
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
