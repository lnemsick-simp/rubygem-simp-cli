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
    else
      @password_dir = password_dir
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
  def remove_passwords(names, force_remove)
    validate_names(names)

    names.each do |name|
      remove = force_remove
      unless remove
        prompt = "Are you sure you want to remove all entries for #{name}?"
        remove = Simp::Cli::Passgen::Utils::yes_or_no(prompt, false)
      end
      if remove
        [
          password_filename,
          password_filename + '.salt',
          password_filename + '.last',
          password_filename + '.salt.last',
        ].each do |file|
          if File.exist?(file)
            File.unlink(file)
            puts "#{file} deleted"
          end
        end
      end
      puts
    end
  end

  # Set a list of passwords to values entered by the user
  #
  # For each password name, backups up existing password files and  creates a
  # new password file.  Does not create a salt file, but relies on
  # simplib::passgen to generate one the next time the catalog is compiled.
  #
  # @param names Array of names of passwords to set
  #
  def set_passwords(names, options)
    names.each do |name|
      next if name.strip.empty?
      password_filename = "#{@password_dir}/#{name}"

      puts "#{@environment} Name: #{name}"
      if options[:length].nil?
        options[:length] = get_password_length(password_file, options)
      end
      password = get_new_password(options)
      backup_password_files(password_filename) if File.exists?(password_filename)

      begin
        File.open(password_filename, 'w') { |file| file.puts password }

        # Ensure that the ownership and permissions are correct
        puppet_user = @puppet_info[:config]['user']
        puppet_group = @puppet_info[:config]['group']
        if puppet_user.empty? or puppet_group.empty?
          err_msg = 'Could not set password file ownership:  unable to determine puppet user and group'
          raise Simp::Cli::ProcessingError.new(err_msg)
        end
        FileUtils.chown(puppet_user, puppet_group, password_filename)
        FileUtils.chmod(0640, password_filename)

      rescue ArgumentError => err
        # This will happen if group does not exist
        err_msg = "Could not set password file ownership: #{err}"
        raise Simp::Cli::ProcessingError.new(err_msg)
      rescue SystemCallError => err
        err_msg = "Error occurred while writing '#{password_filename}': #{err}"
        raise Simp::Cli::ProcessingError.new(err_msg)
      end
      puts
    end
  end

  # Prints the list of password names for the environment to the console
  def show_name_list
    names = get_names
    puts "#{@environment} Names:\n\t#{names.join("\n\t")}"
    puts
  end

  # Prints password info for the environment to the console.
  #
  # For each password name, prints its current value, and when present, its
  # previous value.
  #
  def show_passwords(names)
    validate_names(names)

    title =  "#{@environment} Environment"
    puts title
    puts '='*title.length
    names.each do |name|
      Dir.chdir(@password_dir) do
        puts "Name: #{name}"
        current_password = File.open("#{@password_dir}/#{name}", 'r').gets
        puts "  Current:  #{current_password}"
        last_password = nil
        last_password_file = "#{@password_dir}/#{name}.last"
        if File.exists?(last_password_file)
          last_password = File.open(last_password_file, 'r').gets
        end
        puts "  Previous: #{last_password}" if last_password
      end
      puts
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
      err_msg = "Error occurred while backing up '#{password_filename}' files: #{err}"
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
    prompt = 'Do you want to autogenerate the password?'
    if options[:auto_gen] || Simp::Cli::Passgen::Utils::yes_or_no(prompt, true)
      password = Simp::Cli::Utils.generate_password(option[:length])
      puts "  Password set to '#{password}'"
    else
      password = Simp::Cli::Passgen::Utils::get_password(5, !options[:force_value])
    end
    password
  end

  def get_password_dir
    password_env_dir = File.join(@puppet_info[:config]['vardir'], 'simp', 'environments')
    File.join(password_env_dir, @environment, 'simp_autofiles', 'gen_passwd')
  end

  def get_password_length(password_file, options)
    length =nil
    if File.exist?(password_file)
      begin
        current_password = File.open(password_file, 'r').gets.chomp
        if current_password.length >= options[:minimum_length]
          length = current_password.length
        end
      rescue Exception => e
        err_msg = "Error occurred while reading '#{password_filename}': #{e}"
        raise Simp::Cli::ProcessingError.new(err_msg)
      end
    end
    length = options[:default_length] if length.nil?
    length
  end

  def validate_names(names)
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

end
