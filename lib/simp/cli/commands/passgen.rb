require 'simp/cli/commands/command'
require 'simp/cli/exec_utils'
require 'simp/cli/utils'
require 'highline/import'

class Simp::Cli::Commands::Passgen < Simp::Cli::Commands::Command
  require 'fileutils'

  DEFAULT_ENVIRONMENT        = 'production'
  DEFAULT_AUTO_GEN_PASSWORDS = false
  DEFAULT_PASSWORD_LENGTH    = 32
  MINIMUM_PASSWORD_LENGTH    = 8

  # First simplib version in which simplib::passgen could use libkv
  LIBKV_SIMPLIB_VERSION = '4.0.0'

  def initialize
    @operation = nil
    @environment = nil
    @backend = nil
    @folder = nil        # passgen sub-folder in libkv
    @password_dir = nil  # fully qualified path to legacy passgen dir
    @names = Array.new
    @password_gen_options = {
     :auto_gen       => DEFAULT_AUTO_GEN_PASSWORDS,
     :force_value    => false,  # whether to accept passwords from user without validation
     :length         => nil,
     :default_length => DEFAULT_PASSWORD_LENGTH,
     :minimum_length => MINIMUM_PASSWORD_LENGTH
# FIXME: Do we need the next 2?
#    :complexity = nil
#    :complex_only = nil
    }
    @force_remove = false
  end

  #####################################################
  # Simp::Cli::Commands::Command API methods
  #####################################################
  #
  def description
    "Utility for managing 'simplib::passgen' passwords"
  end

  def help
    parse_command_line( [ '--help' ] )
  end

  def run(args)
    parse_command_line(args)
    return if @help_requested

    @environment = (@environment.nil? ? DEFAULT_ENVIRONMENT : @environment)

    valid_env_info = find_valid_environments
    unless valid_env_info.keys.include?(@environment)
      err_msg = "Invalid Puppet environment '#{@environment}':\n" +
        "  Cannot have simplib::passgen passwords since 'simp-simplib' is not installed."
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    manager = nil
    if legacy_passgen?(valid_env_info[@environment])
      # This environment does not have Puppet functions to manage
      # simplib::passgen passwords. Fallback to how these passwords were
      # managed, before.
      # TODO See if we can use functions from another environment that does
      # have the passgen-managing functions?  The simplib::passgen::legacy
      # functions would have to be reworked to allow overriding the environment.
      manager = Simp::Cli::Passgen::LegacyPasswordManager.new(@environment,
        @password_dir)
    else
      # This environment has Puppet functions to manage simplib::passgen
      # passwords, whether they are stored in the legacy directory for the
      # environment or in a key/value store via libkv.  The functions figure
      # out where the passwords are stored and executes appropriate logic.
      manager = Simp::Cli::Passgen::PasswordManager.new(@environment,
        @backend, @folder)
    end

    case @operation
    when :show_environment_list
      show_environment_list(valid_env_info.keys)
    when :show_name_list
      manager.show_name_list
    when :show_passwords
      manager.show_passwords
    when :set_passwords
      manager.set_passwords(@names, @password_gen_options)
    when :remove_passwords
      manager.remove_passwords(@names, @force_remove)
    end
  end

  #####################################################
  # Custom methods
  #####################################################

  # @returns Hash Puppet environments in which simp-simplib has been installed
  #   - key is the environment name
  #   - value is the version of simp-simplib
  # @raise Simp::Cli::ProcessingError if `puppet module list` fails
  def find_valid_environments
    # grab the environments path from the production env puppet master config
    environments_dir = Simp::Cli::Utils.puppet_info[:config]['environmentpath']
    environments = Dir.glob(File.join(environments_dir, '*'))
    environments.map! { |env| File.basename(env) }

    # only keep environments that have simplib installed
    env_info = {}
    environments.sort.each do |env|
      command = "puppet module list --color=false --environment=#{env}"
      result = Simp::Cli::ExecUtils.run_command(command)

      if result[:status]
        regex = /\s+simp-simplib\s+\(v([0-9]+\.[0-9]+\.[0-9]+)\)/m
        match = result[:stdout].match(regex)
        unless match.nil?
          env_info[env] = match[1] # version of simp-simplib
        end
      else
        err_msg = "#{command} failed: #{result[:stderr]}"
        raise Simp::Cli::ProcessingError.new(err_msg)
      end
    end

    env_info
  end

  # @returns whether the environment has an old version of simplib
  #   that does not provide password-managing Puppet functions
  def legacy_passgen?(env_simplib_version)
    env_simplib_version.split('.')[0] < LIBKV_SIMPLIB_VERSION.split('.')[0]
  end

  def parse_command_line(args)
    raise OptionParser::ParseError.new('The SIMP Passgen Tool requires at least one option') if args.empty?

    opt_parser = OptionParser.new do |opts|
      opts.banner = "\n=== The SIMP Passgen Tool ===."
      opts.separator ''
      opts.separator 'The SIMP Passgen Tool is a simple password control utility. It allows the'
      opts.separator 'viewing, setting, and removal of passwords generated by simplib::passgen.'
      opts.separator ''
      opts.separator '  # Show a list of environments that may have simplib::passgen passwords'
      opts.separator '  simp passgen -E'
      opts.separator ''
      opts.separator '  # Show a list of the password names in the production environment'
      opts.separator '  simp passgen -l'
      opts.separator ''
      opts.separator '  # Show password details for specific passwords in the dev environment'
      opts.separator '  simp passgen -e dev -n NAME1,NAME2,NAME3'
      opts.separator ''
      opts.separator '  # Show password details for a password in a sub-folder in a key/value store.'
      opts.separator "  # This example is for a password from simplib::passgen('app1/admin')"
      opts.separator '  simp passgen -f app1 -n admin'
      opts.separator ''
      opts.separator '  # remove specific passwords in the test environment'
      opts.separator '  simp passgen -e test -r NAME1,NAME2'
      opts.separator ''
      opts.separator '  # manually set specific passwords in the production environment'
      opts.separator '  simp passgen -s NAME1,NAME2,NAME3'
      opts.separator ''
      opts.separator '  # regenerate specific passwords in the production environment'
      opts.separator '  simp passgen --auto-generate -s NAME1,NAME2,NAME3'
      opts.separator ''
      opts.separator 'COMMANDS:'
      opts.separator ''

      opts.on('-E', '--list-env', 'List possible environments that may contain passwords.') do
        @operation = :show_environment_list
      end

      opts.on('-l', '--list-names',
        'List possible password names for the specified environment.',
        'For passwords in a libkv key/value store, the listing is for the',
        'sub-folder specified by --folder.') do
        @operation = :show_name_list
      end

      opts.on('-n', '--name NAME1[,NAME2,...]', Array,
            'Show password info for NAME1[,NAME2,...] in the',
            'specified environment.',
             'For passwords in a libkv key/value store, the listing is for the',
             'sub-folder specified by --folder.') do |names|
        @operation = :show_passwords
        @names = names
      end

      opts.on('-r', '--remove NAME1[,NAME2,...]', Array,
            'Remove all password info for NAME1[,NAME2,...] in the',
            'specified environment.',
            'For passwords in a libkv key/value store, use --folder to specify a sub-folder.') do |names|
        @operation = :remove_passwords
        @names = names
      end

      opts.on('-s', '--set NAME1[,NAME2,...]', Array,
            'Set password(s) for NAME1[,NAME2,...] in the',
            'specified environment, backing up any previous values.',
            'For passwords in a libkv key/value store, use --folder to specify a sub-folder.') do |names|
        @operation = :set_passwords
        @names = names
      end

      opts.on('-h', '--help', 'Print this message.') do
        puts opts
        @help_requested = true
      end

      opts.separator ''
      opts.separator 'COMMAND MODIFIERS:'
      opts.separator ''

      opts.on('--[no-]auto-generate',
            'Whether to auto-generate new passwords.',
            'When disabled the user will be prompted to enter new passwords.',
            "Defaults to #{DEFAULT_AUTO_GEN_PASSWORDS ? 'enabled' : 'disabled'}.") do |auto_gen|
        @password_gen_options[:auto_gen] = auto_gen
      end

      opts.on('--complexity', Integer,
            'Password complexity to use when auto-generated.',
            'For existing passwords stored a libkv key/value store, defaults to the current password complexity.',
#DEFAULT
            "Otherwise, defaults to '0'.",
            'See simplib::passgen documentation for details') do |complexity|
        @password_gen_options[:complexity] = complexity
      end

      opts.on('--[no-]complex-only',
            'Whether to only use only complex characters when password is auto-generated.',
            'For existing passwords in a libkv key/value store, defaults to the current password setting.',
#DEFAULT
            "Otherwise, defaults to 'false'.",
            'See simplib::passgen documentation for details') do |complex_only|
        @password_gen_options[:complex_only] = complex_only
      end


      opts.on('--backend BACKEND',
            'Specific libkv backend to query for the specified environment.',
            'Defaults to the default backend for simplib::passgen.',
            'Only needed for passwords from simplib::passgen calls with custom libkv settings.') do |backend|
        @backend = backend
      end

      opts.on('-d', '--dir DIR',
            'Fully qualified path to a legacy password store.',
            "Overrides an environment specified by the '-e' option.") do |dir|
        @password_dir = dir
      end

      opts.on('-e', '--env ENV',
            'Puppet environment to which the passgen operation will',
            "be applied. Defaults to '#{DEFAULT_ENVIRONMENT}'.") do |env|
        @environment = env
      end

      opts.on('--folder FOLDER',
        '(Sub-)folder in which to find password names in a libkv key/value store.',
        "For simplib::passgen('app1/admin'), the folder",
        "would be 'app1' and the name would be 'admin'.",
        'Defaults to the top-level folder for passgen.'  ) do |folder|
        @folder = folder
      end

      opts.on('--force-remove',
            'Remove passwords without prompting user to confirm.',
            'If unspecified, user will be prompted to confirm the',
            'removal action for each password.') do |force_remove|
        @force_remove = force_remove
      end

      opts.on('--force-value',
            'Disable validation of user-entered passwords.') do |force_value|
        @password_gen_options[:force_value] = force_value
      end

      opts.on('--length', Integer,
            'Password length to use when auto-generated.',
            'Defaults to the current password length, when password is present',
            "provided the length is >= #{MINIMUM_PASSWORD_LENGTH}",
            "Otherwise, defaults to '#{DEFAULT_PASSWORD_LENGTH}'.") do |length|
        @password_gen_options[:length] = length
      end
    end

    opt_parser.parse!(args)

    unless @help_requested
      if @operation.nil?
        raise OptionParser::ParseError.new("No password operation specified.\n" + opt_parser.help)
      end
    end
  end

  # Prints to the console the list of Puppet environments for which
  # simp-simplib is installed
  def show_environment_list(valid_envs)
    if valid_envs.empty?
      puts 'No environments with simp-simplib installed found.'
    else
      puts "Environments:\n  #{valid_envs.sort.join("\n  ")}"
    end
    puts
  end
end
