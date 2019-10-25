require 'highline/import'

# Class that provides legacy `simp passgen` operations for environments having
# old simplib module versions that do not support password management beyond
# the simplib::passgen() function.
#
class Simp::Cli::Passgen::LegacyPasswordManager
  require 'fileutils'

  def initialize(environment, password_dir = nil)
    @environment = environment
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
      password_filename = "#{@password_dir}/#{name}"
      if File.exists?(password_filename)
        remove = force_remove
        unless remove
          remove = yes_or_no("Are you sure you want to remove all entries for #{name}?", false)
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
  def set_passwords(names)
    names.each do |name|
      next if name.strip.empty?
      password_filename = "#{@password_dir}/#{name}"

      puts "#{@environment} Name: #{name}"
      password = get_password
      backup_password_files(password_filename) if File.exists?(password_filename)

      begin
        File.open(password_filename, 'w') { |file| file.puts password }

        # Ensure that the ownership and permissions are correct
        puppet_user = `puppet config print user 2>/dev/null`.strip
        puppet_group = `puppet config print group 2>/dev/null`.strip
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

  def get_password(allow_autogenerate = true, attempts = 5)
    if (attempts == 0)
      raise Simp::Cli::ProcessingError.new('FATAL: Too may failed attempts to enter password')
    end

    password = ''
    if allow_autogenerate and yes_or_no('Do you want to autogenerate the password?', true )
#FIXME need to use simplib::gen_random_password to generate new password and salt
      password = Simp::Cli::Utils.generate_password
      puts "  Password set to '#{password}'"
    else
      question1 = "> #{'Enter password'.bold}: "
      password = ask(question1) do |q|
        q.echo = '*'
        q.validate = lambda { |answer| validate_password(answer) }
        q.responses[:not_valid] = nil
        q.responses[:ask_on_error] = :question
        q
      end

      question2 = "> #{'Confirm password'.bold}: "
      confirm_password = ask(question2) do |q|
        q.echo = '*'
        q
      end

      if password != confirm_password
        $stderr.puts '  Passwords do not match! Please try again.'.red.bold

        # start all over, skipping the autogenerate question
        password = get_password(false, attempts - 1)
      end
    end
    password
  end

  def get_password_dir
    password_env_dir = File.join(`puppet config print vardir --section master 2>/dev/null`.strip, 'simp', 'environments')
    File.join(password_env_dir, @environment, 'simp_autofiles', 'gen_passwd')
  end

  def validate_names(names)
    actual_names = get_names
    names.each do |name|
      unless actual_names.include?(name)
        #FIXME print out names nicely (e.g., max 8 per line)
        raise OptionParser::ParseError.new("Invalid name '#{name}' selected.\n\nValid names: #{names.join(', ')}")
      end
    end
  end

  def validate_password(password)
    begin
      Simp::Cli::Utils::validate_password(password)
      return true
    rescue Simp::Cli::PasswordError => e
      $stderr.puts "  #{e.message}.".red.bold
      return false
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


  def yes_or_no(prompt, default_yes)
    question = "> #{prompt.bold}: "
    answer = ask(question) do |q|
      q.validate = /^y$|^n$|^yes$|^no$/i
      q.default = (default_yes ? 'yes' : 'no')
      q.responses[:not_valid] = "Invalid response. Please enter 'yes' or 'no'".red
      q.responses[:ask_on_error] = :question
      q
    end
    result = (answer.downcase[0] == 'y')
  end
end
