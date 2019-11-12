require 'simp/cli/passgen/utils'
require 'spec_helper'

class PassgenUtilsMockLogger
  attr_accessor :messages
  def initialize
     @messages = []
  end

  def debug(message)
    @messages << message
  end
end

describe Simp::Cli::Passgen::Utils do
  describe '.get_password' do
    before :each do
      @input = StringIO.new
      @output = StringIO.new
      @prev_terminal = $terminal
      $terminal = HighLine.new(@input, @output)
    end

    after :each do
      @input.close
      @output.close
      $terminal = @prev_terminal
    end

    let(:password1) { 'A=V3ry=Go0d=P@ssw0r!' }

    it 'accepts a valid password when entered twice' do
      @input << "#{password1}\n"
      @input << "#{password1}\n"
      @input.rewind
      expect( Simp::Cli::Passgen::Utils.get_password ).to eq password1

      expected = <<EOM
> Enter password: ********************
> Confirm password: ********************
EOM
      expect(@output.string.uncolor).to eq expected
    end

    it 're-prompts when the entered password fails validation' do
      @input << "short\n"
      @input << "#{password1}\n"
      @input << "#{password1}\n"
      @input.rewind
      expect( Simp::Cli::Passgen::Utils.get_password ).to eq password1

      expected = <<EOM
> Enter password: *****
> Enter password: ********************
> Confirm password: ********************
EOM
      expect(@output.string.uncolor).to eq expected
    end

    it 'starts over when the confirm password does not match the entered password' do
      @input << "#{password1}\n"
      @input << "bad confirm\n"
      @input << "#{password1}\n"
      @input << "#{password1}\n"
      @input.rewind
      expect( Simp::Cli::Passgen::Utils.get_password ).to eq password1

      expected = <<EOM
> Enter password: ********************
> Confirm password: ***********
> Enter password: ********************
> Confirm password: ********************
EOM
      expect(@output.string.uncolor).to eq expected
    end

    it 'fails after 5 failed start-over attempts' do
      @input << "#{password1}\n"
      @input << "bad confirm 1\n"
      @input << "#{password1}\n"
      @input << "bad confirm 2\n"
      @input << "#{password1}\n"
      @input << "bad confirm 3\n"
      @input << "#{password1}\n"
      @input << "bad confirm 4\n"
      @input << "#{password1}\n"
      @input << "bad confirm 5\n"
      @input.rewind
      expect{ Simp::Cli::Passgen::Utils.get_password }
        .to raise_error(Simp::Cli::ProcessingError)
    end

    it 'accepts an invalid password when validation disabled' do
      simple_password = 'password'
      @input << "#{simple_password}\n"
      @input << "#{simple_password}\n"
      @input.rewind
      expect( Simp::Cli::Passgen::Utils.get_password(5, false) ).to eq simple_password
    end
  end

  describe '.yes_or_no' do
    before :each do
      @input = StringIO.new
      @output = StringIO.new
      @prev_terminal = $terminal
      $terminal = HighLine.new(@input, @output)
    end

    after :each do
      @input.close
      @output.close
      $terminal = @prev_terminal
    end

    it "when default_yes=true, prompts, accepts default of 'yes' and returns true" do
      @input << "\n"
      @input.rewind

      expect( Simp::Cli::Passgen::Utils.yes_or_no('Remove backups', true) ).to eq true
      expect( @output.string.uncolor ).to eq '> Remove backups: |yes| '
    end

    it "when default_yes=false, prompts, accepts default of 'no' and returns false" do
      @input << "\n"
      @input.rewind
      expect( Simp::Cli::Passgen::Utils.yes_or_no('Remove backups', false) ).to eq false
      expect( @output.string.uncolor ).to eq '> Remove backups: |no| '
    end

    ['yes', 'YES', 'y', 'Y'].each do |response|
      it "accepts '#{response}' and returns true" do
        @input << "#{response}\n"
        @input.rewind
        expect( Simp::Cli::Passgen::Utils.yes_or_no('Remove backups', false) ).to eq true
      end
    end

    ['no', 'NO', 'n', 'N'].each do |response|
      it "accepts '#{response}' and returns false" do
        @input << "#{response}\n"
        @input.rewind
        expect( Simp::Cli::Passgen::Utils.yes_or_no('Remove backups', false) ).to eq false
      end
    end

    it 're-prompts user when user does not enter a string that begins with Y, y, N, or n' do
      @input << "oops\n"
      @input << "I\n"
      @input << "can't\n"
      @input << "type!\n"
      @input << "yes\n"
      @input.rewind
      expect( Simp::Cli::Passgen::Utils.yes_or_no('Remove backups', false) ).to eq true
    end

  end

#FIXME
  describe '.apply_manifest' do
    context 'without logger' do
    end

    context 'with logger' do
    end
  end

  describe '.load_yaml' do
    let(:files_dir) { File.join(File.dirname(__FILE__), 'files') }
    context 'without logger' do
      it 'returns Hash for valid YAML file' do
        file = File.join(files_dir, 'good.yaml')
        yaml =  Simp::Cli::Passgen::Utils.load_yaml(file, 'password info')

        expected = { 'value' => { 'password' => 'password1', 'salt' => 'salt1' } }
        expect( yaml ).to eq(expected)
      end

      it 'fails when the file does not exist' do
        expect{ Simp::Cli::Passgen::Utils.load_yaml('oops', 'password list') }
        .to raise_error(Simp::Cli::ProcessingError,
         /Failed to load password list YAML:\n<<< Error: No such file or directory/m)
      end

      it 'fails when YAML file cannot be parsed' do
        file = File.join(files_dir, 'bad.yaml')
        expected_regex = /Failed to load password info YAML:\n<<< YAML Content:\n#{File.read(file)}\n<<< Error: /m
        expect{ Simp::Cli::Passgen::Utils.load_yaml(file, 'password info') }
        .to raise_error(Simp::Cli::ProcessingError, expected_regex)
      end
    end

    context 'with logger' do
      it 'returns Hash for valid YAML file' do
        file = File.join(files_dir, 'good.yaml')
        logger = PassgenUtilsMockLogger.new
        yaml =  Simp::Cli::Passgen::Utils.load_yaml(file, 'password info', logger)

        expected = { 'value' => { 'password' => 'password1', 'salt' => 'salt1' } }
        expect( yaml ).to eq(expected)
        expected_debug = [
          'Loading password info YAML from file',
          "Content:\n#{File.read(file)}"
        ]
        expect( logger.messages ).to eq(expected_debug)
      end

      it 'fails when the file does not exist' do
        logger = PassgenUtilsMockLogger.new
        expect{ Simp::Cli::Passgen::Utils.load_yaml('oops', 'password list', logger) }
        .to raise_error(Simp::Cli::ProcessingError,
         /Failed to load password list YAML:\n<<< Error: No such file or directory/m)
        expected_debug = ['Loading password list YAML from file']
        expect( logger.messages ).to eq(expected_debug)
      end

      it 'fails when YAML file cannot be parsed' do
        file = File.join(files_dir, 'bad.yaml')
        logger = PassgenUtilsMockLogger.new
        expected_regex = /Failed to load password info YAML:\n<<< YAML Content:\n#{File.read(file)}\n<<< Error: /m
        expect{ Simp::Cli::Passgen::Utils.load_yaml(file, 'password info', logger) }
        .to raise_error(Simp::Cli::ProcessingError, expected_regex)
        expected_debug = [
          'Loading password info YAML from file',
          "Content:\n#{File.read(file)}"
        ]
        expect( logger.messages ).to eq(expected_debug)
      end
    end
  end
end
