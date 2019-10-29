require 'simp/cli/utils'

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
      err_msg = 'FATAL: Too may failed attempts to enter password'
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


end
