require 'simp/cli/utils'
require 'simp/cli/exec_utils'

require 'highline'
require 'highline/import'

HighLine.colorize_strings

module Simp; end
class Simp::Cli; end
module Simp::Cli::Passgen; end

module Simp::Cli::Passgen::Utils
  require 'fileutils'

  def self.get_password(attempts = 5, validate = true)
    if (attempts == 0)
      err_msg = 'FATAL: Too many failed attempts to enter password'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    password = ''
    question1 = "> #{'Enter password'.bold}: "
    password = ask(question1) do |q|
      q.echo = '*'
      if validate
        q.validate = lambda { |answer| self.validate_password(answer) }
      end
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
      password = get_password(attempts - 1, validate)
    end

    password
  end

#FIXME
# * Passwords generated by simplib::passgen are not validated against OS
# * Passwords generated by simplib::passgen with complexity 0 have no special
#   symbols and will fail OS validation
# * What about validating length, complexity, complex_only?
  def self.validate_password(password)
    begin
      Simp::Cli::Utils::validate_password(password)
      return true
    rescue Simp::Cli::PasswordError => e
      $stderr.puts "  #{e.message}.".red.bold
      return false
    end
  end

  def self.yes_or_no(prompt, default_yes)
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

  # Apply a Puppet manifest with simplib::passgen commands in an environment
  #
  # The 'puppet apply' is customized for simplib::passgen functions
  # * The apply sets Puppet's vardir setting explicitly to that of the puppet
  #   master.
  #   - vardir is used in simplib::passgen functions to determine the
  #     location of password files.
  #   - vardir defaults to the puppet agent's setting (a different value)
  #     otherwise.
  # * The apply is wrapped in 'sg  <puppet group>'  and run with a umask of
  #   0007 to ensure any files/directories created by a simplib::passgen
  #   function are still accessible by the puppetserver.  This group setting,
  #   alone, is insufficient for legacy passgen files, but works when
  #   used in conjunction with a legacy-passgen-specific 'user' setting
  #   in manifests that create/update passwords.
  #
  # LIMITATION:  This 'puppet apply' operation has ONLY been tested for
  # manifests containing simplib::passgen functions and applied as the root
  # user.
  #
  # @param manifest Contents of the manifest to be applied
  # @param opts Options
  #  * :env   - Puppet environment to which manifest will be applied.
  #             Defaults to 'production' when unspecified.
  #  * :fail  - Whether to raise an exception upon manifest failure.
  #             Defaults to true when unspecified
  #  * :title - Brief description of operation. Used in the exception
  #             message when apply fails and :fail is true.
  #             Defaults to 'puppet apply' when unspecified.
  #
  # @param logger Optional Simp::Cli::Logging::Logger object. When not
  #    set, logging is suppressed.
  #
  # @raise if manifest apply fails and :fail is true
  #
  # TODO Replace with Puppet PAL and rework manifests to return retrieved
  #   values, when we drop support for Puppet 5
  def self.apply_manifest(manifest, opts = { :env => 'production',
      :fail => false, :title => 'puppet apply'}, logger = nil)

    options = opts.dup
    options[:env]   = 'production'   unless options.key?(:env)
    options[:fail]  = true           unless options.key?(:fail)
    options[:title] = 'puppet apply' unless options.key?(:title)

    puppet_info = Simp::Cli::Utils.puppet_info(options[:env])

    result = nil
    cmd = nil
    Dir.mktmpdir( File.basename( __FILE__ ) ) do |dir|
      logger.debug("Creating manifest file for #{options[:title]} with" +
        " content:\n#{manifest}") if logger

      manifest_file = File.join(dir, 'passgen.pp')
      File.open(manifest_file, 'w') { |file| file.puts manifest }
      puppet_apply = [
        'puppet apply',
        '--color=false',
        "--environment=#{options[:env]}",
        "--vardir=#{puppet_info[:config]['vardir']}",
        manifest_file
      ].join(' ')

      # We need to defer handling of error logging to the caller, so don't pas
      # logger into run_command().  Since we are not using the logger in
      # run_command(), we will have to duplicate the command debug logging here.
      cmd = "umask 0007 && sg #{puppet_info[:config]['group']} -c '#{puppet_apply}'"
      logger.debug( "Executing: #{cmd}" ) if logger
      result = Simp::Cli::ExecUtils.run_command(cmd)
    end

    if logger
      logger.debug(">>> stdout:\n#{result[:stdout]}")
      logger.debug(">>> stderr:\n#{result[:stderr]}")
    end

    if !result[:status] && options[:fail]
      err_msg = [
        "#{options[:title]} failed:",
        ">>> Command: #{cmd}",
        '>>> Manifest:',
        manifest,
        '>>> stderr:',
        result[:stderr]
      ].join("\n")
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    result
  end

end
