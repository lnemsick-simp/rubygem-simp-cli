require 'highline/import'

class Simp::Cli::::Passgen::PasswordManager
  require 'fileutils'

  def initialize(environment)
    @environment = environment
  end

  #####################################################
  # Operations
  #####################################################
  #

  #####################################################
  # Helpers
  #####################################################

  def run(args)
    parse_command_line(args)
    return if @help_requested

    @environment = (@environment.nil? ? DEFAULT_ENVIRONMENT : @environment)

    case @operation
    when :show_environment_list
      show_environment_list
    when :show_name_list
# list the key/value pairs for an environment
#   recursion?  no?  dangerous?  allow user to specify
#   a subdir
#    --> Only applies to libkv-enabled simplib::passgen.
#        Legacy doesn't allow subdirs.
#
# don't need to allow user to specify app_id if allow them to specify a backend
# simplib::passgen::list
      show_name_list
    when :show_passwords
# simplib::passgen::list
      show_passwords
    when :set_passwords
# retrieve a password and any stored attributes from an environment
# if it exists, otherwise return empty {}
# simplib::passgen::get
#
# set password with attributes (after generating salt) and backup existing
# password as 'last' password
# simplib::passgen::set
      set_passwords
    when :remove_passwords
# remove current and last setting for a password
# simplib::passgen::remove
      remove_passwords
    end
  end


  def execute_apply(manifest, environment)

  end

  def parse_command_line(args)
  end

  def get_names
  end

  def get_password(allow_autogenerate = true, attempts = 5)
    if (attempts == 0)
      raise Simp::Cli::ProcessingError.new('FATAL: Too may failed attempts to enter password')
    end

    password = ''
    if allow_autogenerate and yes_or_no('Do you want to autogenerate the password?', true )
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

  def validate_names
    names = get_names
    @names.each do |name|
      unless names.include?(name)
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

# For listing of environments
# look at /etc/puppetlabs/code/environments for possible environments
# NO OPTION 1
# iterate through each
# - Examine simplib version of the environment selected
#    YES: puppet module list --tree | grep simplib
#    │ └─┬ simp-simplib (v3.17.0)
# - If has newer simplib, can do all operations on new or old passwords
#   using manifests for new simplib::passgen::xxx commands
# - If does not have newer simplib, there won't be any libkv passwords.  So,
#   execute the legacy 'simp passgen' code.
#
# environment_exists
#   directory exists and is not empty
#
# YES OPTION 2
# iterate through each
# remove environments that don't have simp-simplib
#
  def show_environment_list
# return the environments that have passgen keys
# which backend? --> default backend unless specified
# otherwise.  Will need to read  libkv::options in case
# has a backend hard-coded in lieu of 'default'.  May
# be auto_default as well.
#
#   will have to query both old and new and merge
# simplib::passgen::environments
#FIXME Only way to replace is with a directory list of environments dir...
#May want to go further and check if has modules.
    # FIXME This ASSUMES @password_dir follows a known pattern of
    #   <env dir>/<env>/simp_autofiles/gen_passwd
    # (which also assumes Linux path separators)
    result = execute_apply(manifest, nil)

    puts "Environments:\n\t#{environments.join("\n\t")}"
    puts
  end

# For all other commands (show_name_list, show_passwords, etc.)
# - Examine simplib version of the environment selected
#    YES: puppet module list --tree | grep simplib
#    │ └─┬ simp-simplib (v3.17.0)
# - If has newer simplib, can do all operations on new and old passwords
#   using manifests for new simplib::passgen::xxx commands
# - If does not have newer simplib, there won't be any libkv passwords.  So,
#   execute the legacy 'simp passgen' code.
# 

  def show_name_list
    validate_password_dir
    names = get_names
    puts "#{@environment} Names:\n\t#{names.join("\n\t")}"
    puts
  end

  def show_passwords
    validate_password_dir
    validate_names

    title =  "#{@environment} Environment"
    puts title
    puts '='*title.length
    @names.each do |name|
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

  def backup_password_files(password_filename)
    backup_passwords = @backup_passwords
    if backup_passwords.nil?
      backup_passwords = yes_or_no("Would you like to rotate the old password?", false)
    end
    if backup_passwords
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
  end

# OLD PASSGEN
# need to use simplib::gen_random_password to generate new password and salt
# FileUtils.cp with preserve to backup last files to dot files
# then FileUtils.cp with preserve to copy current contents to the last contents
# overwrite current contents
# remove last dot files
# revert if any failure
# NEW PASSGEN
# use the api...
  def set_passwords
  end

  def remove_passwords
  end

  def validate_environment
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
