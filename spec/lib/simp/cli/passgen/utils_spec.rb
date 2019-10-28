require 'simp/cli/passgen/utils'
require 'spec_helper'


describe Simp::Cli::Passgen::Utils do
  describe '#get_password' do
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

  describe '#yes_or_no' do
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
end
