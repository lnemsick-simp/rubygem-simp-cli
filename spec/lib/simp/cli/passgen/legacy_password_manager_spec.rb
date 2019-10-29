require 'simp/cli/passgen/legacy_password_manager'
require 'spec_helper'
require 'etc'
require 'tmpdir'

def create_password_files(password_dir, names_with_backup, names_without_backup=[])
  names_with_backup.each do |name|
    name_file = File.join(password_dir, name)
    File.open(name_file, 'w') { |file| file.puts "#{name}_password" }
    File.open("#{name_file}.salt", 'w') { |file| file.puts "salt for #{name}" }
    File.open("#{name_file}.last", 'w') { |file| file.puts "#{name}_backup_password" }
    File.open("#{name_file}.salt.last", 'w') { |file| file.puts "salt for #{name} backup password" }
  end

  names_without_backup.each do |name|
    name_file = File.join(password_dir, name)
    File.open(name_file, 'w') { |file| file.puts "#{name}_password" }
    File.open("#{name_file}.salt", 'w') { |file| file.puts "salt for #{name}" }
  end
end

def validate_set_and_backup(passgen, args, expected_output, expected_file_info)
  expect { passgen.run(args) }.to output(expected_output).to_stdout

  expected_file_info.each do |file,expected_contents|
    expect( File.exist?(file) ).to be true
    expect( IO.read(file).chomp ).to eq expected_contents
  end
end

describe Simp::Cli::Passgen::LegacyPasswordManager do
  before :each do
    @tmp_dir   = Dir.mktmpdir(File.basename(__FILE__))
    @var_dir = File.join(@tmp_dir, 'vardir')
    @password_env_dir = File.join(@var_dir, 'simp', 'environments')
    FileUtils.mkdir_p(@password_env_dir)
    @env = 'production'
    @password_dir = File.join(@password_env_dir, @env, 'simp_autofiles', 'gen_passwd')

    puppet_info = {
      :config => {
        'user'   => Etc.getpwuid(Process.uid).name,
        'group'  => Etc.getgrgid(Process.gid).name,
        'vardir' => @var_dir
      }
    }
    allow(Simp::Cli::Utils).to receive(:puppet_info).with(@env).and_return(puppet_info)
    @manager = Simp::Cli::Passgen::LegacyPasswordManager.new(@env)
  end

  after :each do
    FileUtils.remove_entry_secure @tmp_dir, true
  end

  # Operations
  describe '#remove_passwords' do
    before :each do
      FileUtils.mkdir_p(@password_dir)
      names_with_backup = ['production_name1', 'production_name3']
      names_without_backup = ['production_name2']
      create_password_files(@password_dir, names_with_backup, names_without_backup)

      @name1_file = File.join(@password_dir, 'production_name1')
      @name1_salt_file = File.join(@password_dir, 'production_name1.salt')
      @name1_backup_file = File.join(@password_dir, 'production_name1.last')
      @name1_backup_salt_file = File.join(@password_dir, 'production_name1.salt.last')

      @name2_file = File.join(@password_dir, 'production_name2')
      @name2_salt_file = File.join(@password_dir, 'production_name2.salt')

      @name3_file = File.join(@password_dir, 'production_name3')
      @name3_salt_file = File.join(@password_dir, 'production_name3.salt')
      @name3_backup_file = File.join(@password_dir, 'production_name3.last')
      @name3_backup_salt_file = File.join(@password_dir, 'production_name3.salt.last')
    end

    it 'removes password, backup, and salt files for specified environment when prompt returns yes' do
      allow(Simp::Cli::Passgen::Utils).to receive(:yes_or_no).and_return(true)
      expected_output = <<-EOM
#{@name1_file} deleted
#{@name1_salt_file} deleted
#{@name1_backup_file} deleted
#{@name1_backup_salt_file} deleted

#{@name2_file} deleted
#{@name2_salt_file} deleted

      EOM

      names = ['production_name1', 'production_name2']
      expect { @manager.remove_passwords(names) }.to \
        output(expected_output).to_stdout

      expect(File.exist?(@name1_file)).to eq false
      expect(File.exist?(@name1_salt_file)).to eq false
      expect(File.exist?(@name1_backup_file)).to eq false
      expect(File.exist?(@name1_backup_salt_file)).to eq false
      expect(File.exist?(@name2_file)).to eq false
      expect(File.exist?(@name2_salt_file)).to eq false
      expect(File.exist?(@name3_file)).to eq true
      expect(File.exist?(@name3_salt_file)).to eq true
      expect(File.exist?(@name3_backup_file)).to eq true
      expect(File.exist?(@name3_backup_salt_file)).to eq true
    end

    it 'does not remove password, backup and salt files for specified environment when prompt returns no' do
      allow(Simp::Cli::Passgen::Utils).to receive(:yes_or_no).and_return(false)
      # not mocking query output
      expected_output = "\n\n"
      names = ['production_name1', 'production_name2']
      expect { @manager.remove_passwords(names) }.to \
        output(expected_output).to_stdout

      expect(File.exist?(@name1_file)).to eq true
      expect(File.exist?(@name1_salt_file)).to eq true
      expect(File.exist?(@name1_backup_file)).to eq true
      expect(File.exist?(@name1_backup_salt_file)).to eq true
      expect(File.exist?(@name2_file)).to eq true
      expect(File.exist?(@name2_salt_file)).to eq true
      expect(File.exist?(@name3_file)).to eq true
      expect(File.exist?(@name3_salt_file)).to eq true
      expect(File.exist?(@name3_backup_file)).to eq true
      expect(File.exist?(@name3_backup_salt_file)).to eq true
    end

    it 'removes password, backup, and salt files for specified environment when force_remove=true' do
     expected_output = <<-EOM
#{@name1_file} deleted
#{@name1_salt_file} deleted
#{@name1_backup_file} deleted
#{@name1_backup_salt_file} deleted

#{@name2_file} deleted
#{@name2_salt_file} deleted

      EOM

      names = ['production_name1', 'production_name2']
      expect { @manager.remove_passwords(names, true) }.to \
        output(expected_output).to_stdout

      expect(File.exist?(@name1_file)).to eq false
      expect(File.exist?(@name1_salt_file)).to eq false
      expect(File.exist?(@name1_backup_file)).to eq false
      expect(File.exist?(@name1_backup_salt_file)).to eq false
      expect(File.exist?(@name2_file)).to eq false
      expect(File.exist?(@name2_salt_file)).to eq false
      expect(File.exist?(@name3_file)).to eq true
      expect(File.exist?(@name3_salt_file)).to eq true
      expect(File.exist?(@name3_backup_file)).to eq true
      expect(File.exist?(@name3_backup_salt_file)).to eq true
    end

    it 'removes password, backup, and salt files for specified password directory when force_remove=true' do

      alt_password_dir = File.join(@password_env_dir, 'env1', 'simp_autofiles', 'gen_passwd')
      FileUtils.mkdir_p(alt_password_dir)
      create_password_files(alt_password_dir, ['env1_name4'])

      name4_file = File.join(alt_password_dir, 'env1_name4')
      name4_salt_file = File.join(alt_password_dir, 'env1_name4.salt')
      name4_backup_file = File.join(alt_password_dir, 'env1_name4.last')
      name4_backup_salt_file = File.join(alt_password_dir, 'env1_name4.salt.last')

      manager = Simp::Cli::Passgen::LegacyPasswordManager.new(@env, alt_password_dir)

      expected_output = <<-EOM
#{name4_file} deleted
#{name4_salt_file} deleted
#{name4_backup_file} deleted
#{name4_backup_salt_file} deleted

      EOM

      expect { manager.remove_passwords(['env1_name4'], true) }.to \
        output(expected_output).to_stdout

      expect(File.exist?(name4_file)).to eq false
      expect(File.exist?(name4_salt_file)).to eq false
      expect(File.exist?(name4_backup_file)).to eq false
      expect(File.exist?(name4_backup_salt_file)).to eq false
    end

    it 'fails when no names specified' do
      expect { @manager.remove_passwords([]) }.to raise_error(
        Simp::Cli::ProcessingError,
        'No names specified.')
    end

    it 'fails when invalid names specified' do
      names = ['production_name1', 'oops', 'production_name2']
      expect { @manager.remove_passwords(names) }.to raise_error(
        Simp::Cli::ProcessingError,
        /Invalid name 'oops' selected.\n\nValid names: production_name1, /)
    end

    it 'fails when password directory does not exist' do
      FileUtils.rm_rf(@password_dir)
      names = ['production_name1', 'production_name2']
      expect { @manager.remove_passwords(names) }.to raise_error(
        Simp::Cli::ProcessingError,
        "Password directory '#{@password_dir}' does not exist")
    end

    it 'fails when password directory is not a directory' do
      FileUtils.rm_rf(@password_dir)
      FileUtils.touch(@password_dir)
      names = ['production_name1', 'production_name2']
      expect { @manager.remove_passwords(names) }.to raise_error(
        Simp::Cli::ProcessingError,
        "Password directory '#{@password_dir}' is not a directory")
    end
  end

  describe '#set_passwords' do
  end

  describe '#show_name_list' do
    before :each do
      FileUtils.mkdir_p(@password_dir)
    end

    it 'lists no password names, when no names exist' do
      expected_output = <<-EOM
production Names:
  

      EOM
      expect { @manager.show_name_list }.to output(expected_output).to_stdout
    end

    it 'lists available names for the specified environment' do
      names = ['production_name', '10.0.1.2', 'salt.and.pepper', 'my.last.name']
      create_password_files(@password_dir, names)
      expected_output = <<-EOM
production Names:
  10.0.1.2
  my.last.name
  production_name
  salt.and.pepper

      EOM
      expect { @manager.show_name_list }.to output(expected_output).to_stdout
    end

    it 'lists available names for a specific passgen directory' do
      alt_password_dir = File.join(@password_env_dir, 'gen_passwd')
      FileUtils.mkdir_p(alt_password_dir)
      names = ['app1_user', 'app2_user' ]
      create_password_files(alt_password_dir, names)
      manager = Simp::Cli::Passgen::LegacyPasswordManager.new(@env, alt_password_dir)
      expected_output = <<-EOM
#{alt_password_dir} Names:
  app1_user
  app2_user

      EOM
      expect { manager.show_name_list }.to output(expected_output).to_stdout
    end

    it 'fails when password directory does not exist' do
      FileUtils.rm_rf(@password_dir)
      expect { @manager.show_name_list }.to raise_error(
        Simp::Cli::ProcessingError,
        "Password directory '#{@password_dir}' does not exist")
    end

    it 'fails when password directory is not a directory' do
      FileUtils.rm_rf(@password_dir)
      FileUtils.touch(@password_dir)
      expect { @manager.show_name_list }.to raise_error(
        Simp::Cli::ProcessingError,
        "Password directory '#{@password_dir}' is not a directory")
    end
  end

  describe '#show_passwords' do
    before :each do
      FileUtils.mkdir_p(@password_dir)
    end

    it 'shows current and previous passwords for specified names of specified environment' do
      names_with_backup = ['production_name1', 'production_name3']
      names_without_backup = ['production_name2']
      create_password_files(@password_dir, names_with_backup, names_without_backup)
      expected_output = <<-EOM
production Environment Passwords
================================
Name: production_name2
  Current:  production_name2_password

Name: production_name3
  Current:  production_name3_password
  Previous: production_name3_backup_password

      EOM
      expect { @manager.show_passwords(['production_name2','production_name3']) }.
        to output(expected_output).to_stdout
    end

    it 'shows current and previous passwords for specified names in a specific passgen directory' do
      alt_password_dir = File.join(@password_env_dir, 'gen_passwd')
      FileUtils.mkdir_p(alt_password_dir)
      create_password_files(alt_password_dir, ['env1_name1'])
      manager = Simp::Cli::Passgen::LegacyPasswordManager.new(@env, alt_password_dir)
      expected_output = <<-EOM
#{alt_password_dir} Passwords
#{'='*alt_password_dir.length}==========
Name: env1_name1
  Current:  env1_name1_password
  Previous: env1_name1_backup_password

      EOM
      expect { manager.show_passwords(['env1_name1']) }.
        to output(expected_output).to_stdout
    end

    it 'fails when no names specified' do
      expect { @manager.show_passwords([]) }.to raise_error(
        Simp::Cli::ProcessingError,
        'No names specified.')
    end

    it 'fails when invalid name specified' do
      names = ['name1', 'name2', 'name3']
      create_password_files(@password_dir, names)
      expect { @manager.show_passwords(['oops']) }.to raise_error(
        Simp::Cli::ProcessingError,
        "Invalid name 'oops' selected.\n\nValid names: name1, name2, name3")
    end

    it 'fails when password directory does not exist' do
      FileUtils.rm_rf(@password_dir)
      expect { @manager.show_passwords(['name1']) }.to raise_error(
        Simp::Cli::ProcessingError,
        "Password directory '#{@password_dir}' does not exist")
    end

    it 'fails when password directory is not a directory' do
      FileUtils.rm_rf(@password_dir)
      FileUtils.touch(@password_dir)
      expect { @manager.show_passwords(['name1']) }.to raise_error(
        Simp::Cli::ProcessingError,
        "Password directory '#{@password_dir}' is not a directory")
    end

    it 'fails when password directory cannot be accessed' do
      allow(Dir).to receive(:chdir).with(@password_dir).and_raise(
        Errno::EACCES, 'failed dir access')

      expect { @manager.show_passwords(['name1']) }.to raise_error(
        Simp::Cli::ProcessingError,
        "Error occurred while accessing '#{@password_dir}': Permission denied - failed dir access")
    end
  end

  # Helpers.  Since some helper methods are fully tested in Operations tests,
  # only methods not otherwise fully tested are exercised here.
  describe '#backup_password_files' do
  end

=begin
  describe '#get_new_password' do
    before :each do
      @input = StringIO.new
      @output = StringIO.new
      @prev_terminal = $terminal
      $terminal = HighLine.new(@input, @output)

      @manager = Simp::Cli::Commands::Passgen.new
    end

    after :each do
      @input.close
      @output.close
      $terminal = @prev_terminal
    end

    let(:password1) { 'A=V3ry=Go0d=P@ssw0r!' }

    it 'autogenerates a password when default is selected' do
      @input << "\n"
      @input.rewind
      expect( @manager.get_password.length )
        .to eq Simp::Cli::Utils::DEFAULT_PASSWORD_LENGTH

      expected = '> Do you want to autogenerate the password?: |yes| '
      expect( @output.string.uncolor ).to eq expected
    end

    it "autogenerates a password when 'yes' is entered" do
      @input << "yes\n"
      @input.rewind
      expect( @manager.get_password.length )
        .to eq Simp::Cli::Utils::DEFAULT_PASSWORD_LENGTH

      expected = '> Do you want to autogenerate the password?: |yes| '
      expect( @output.string.uncolor ).to eq expected
    end

    it 'does not prompt for autogenerate when allow_autogenerate=false' do
      @input << "#{password1}\n"
      @input << "#{password1}\n"
      @input.rewind
      expect( @manager.get_password(false) ).to eq password1

      expected = <<-EOM
> Enter password: ********************
> Confirm password: ********************
      EOM
      expect( @output.string.uncolor ).to_not match /Do you want to autogenerate/
    end

    it 'accepts a valid password when entered twice' do
      @input << "no\n"
      @input << "#{password1}\n"
      @input << "#{password1}\n"
      @input.rewind
      expect( @manager.get_password ).to eq password1

      expected = <<-EOM
> Do you want to autogenerate the password?: |yes| > Enter password: ********************
> Confirm password: ********************
      EOM
      expect(@output.string.uncolor).to eq expected
    end

    it 're-prompts when the entered password fails validation' do
      @input << "short\n"
      @input << "#{password1}\n"
      @input << "#{password1}\n"
      @input.rewind
      expect( @manager.get_password(false) ).to eq password1

      expected = <<-EOM
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
      expect( @manager.get_password(false) ).to eq password1

      expected = <<-EOM
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
      expect{ @manager.get_password(false) }
        .to raise_error(Simp::Cli::ProcessingError)
    end

  end

  describe '#get_password_length' do
  end

  describe '#run' do
    describe '--set option' do
      before :each do
        @password_dir = File.join(@password_env_dir, 'production', 'simp_autofiles', 'gen_passwd')
        FileUtils.mkdir_p(@password_dir)

        @name1_file = File.join(@password_dir, 'production_name1')
        File.open(@name1_file, 'w') { |file| file.puts "production_name1_password" }
        @name1_salt_file = File.join(@password_dir, 'production_name1.salt')
        File.open(@name1_salt_file, 'w') { |file| file.puts 'production_name1_salt' }
        @name1_backup_file = File.join(@password_dir, 'production_name1.last')
        File.open(@name1_backup_file, 'w') { |file| file.puts "production_name1_backup_password" }

        @name2_file = File.join(@password_dir, 'production_name2')
        File.open(@name2_file, 'w') { |file| file.puts "production_name2_password" }

        @name3_file = File.join(@password_dir, 'production_name3')
        File.open(@name3_file, 'w') { |file| file.puts "production_name3_password" }
        @name3_backup_file = File.join(@password_dir, 'production_name3.last')
        File.open(@name3_backup_file, 'w') { |file| file.puts "production_name3_backup_password" }

        @alt_password_dir = File.join(@password_env_dir, 'env1', 'simp_autofiles', 'gen_passwd')
        FileUtils.mkdir_p(@alt_password_dir)
        @name4_file = File.join(@alt_password_dir, 'env1_name4')
        File.open(@name4_file, 'w') { |file| file.puts "env1_name4_password" }
        @name4_salt_file = File.join(@alt_password_dir, 'env1_name4.salt')
        File.open(@name4_salt_file, 'w') { |file| file.puts "env1_name4_salt" }
        @name4_backup_file = File.join(@alt_password_dir, 'env1_name4.last')
        File.open(@name4_backup_file, 'w') { |file| file.puts "env1_name4_backup_password" }
      end

      context 'for specified environment' do
        context 'with backups' do
          let(:expected_file_info) do {
              @name1_file                => 'first_new_password',
              @name1_backup_file         => 'production_name1_password',
              @name1_salt_file + '.last' => 'production_name1_salt',
              @name2_file                => 'second_new_password',
              @name2_file + '.last'      => 'production_name2_password',
              @name3_file                => 'production_name3_password',       # unchanged
              @name3_backup_file         => 'production_name3_backup_password' # unchanged
            }
          end

          it 'updates password file and backs up old files per prompt' do
            allow(@manager).to receive(:get_password).and_return(
              'first_new_password', 'second_new_password')
            allow(@manager).to receive(:yes_or_no).and_return(true)
            expected_output = <<EOM
production Name: production_name1

production Name: production_name2

EOM
            validate_set_and_backup(@manager, ['-s', 'production_name1,production_name2' ],
              expected_output, expected_file_info)

            expect(File.exist?(@name1_salt_file)).to be false
          end

          it 'updates password file and backs up old files per --backup option' do
            allow(@manager).to receive(:get_password).and_return(
              'first_new_password', 'second_new_password')
            expected_output = <<EOM
production Name: production_name1

production Name: production_name2

EOM
            validate_set_and_backup(@manager, ['--backup', '-s', 'production_name1,production_name2' ],
              expected_output, expected_file_info)

            expect(File.exist?(@name1_salt_file)).to be false
          end
        end

        context 'without backups' do
          let(:expected_file_info) do {
              @name1_file        => 'first_new_password',
              @name1_backup_file => 'production_name1_backup_password', # unchanged
              @name2_file        => 'second_new_password',
              @name3_file        => 'production_name3_password',        # unchanged
              @name3_backup_file => 'production_name3_backup_password'  # unchanged
            }
          end

          it 'updates password file and does not back up old files per prompt' do
            allow(@manager).to receive(:get_password).and_return(
              'first_new_password', 'second_new_password')
            allow(@manager).to receive(:yes_or_no).and_return(true)
            allow(@manager).to receive(:yes_or_no).and_return(false)

            # not mocking query output
            expected_output = <<EOM
production Name: production_name1

production Name: production_name2

EOM
            validate_set_and_backup(@manager, ['-s', 'production_name1,production_name2' ],
              expected_output, expected_file_info)

            expect(File.exist?(@name1_salt_file)).to be false
            expect(File.exist?(@name1_salt_file + '.last')).to be false
            expect(File.exist?(@name2_file + '.last')).to eq false
          end

          it 'updates password file and does not back up old files per --no-backup option' do
            allow(@manager).to receive(:get_password).and_return(
              'first_new_password', 'second_new_password')
            expected_output = <<EOM
production Name: production_name1

production Name: production_name2

EOM
            validate_set_and_backup(@manager, ['--no-backup', '-s', 'production_name1,production_name2' ],
              expected_output, expected_file_info)

            expect(File.exist?(@name1_salt_file)).to be false
            expect(File.exist?(@name1_salt_file + '.last')).to be false
            expect(File.exist?(@name2_file + '.last')).to eq false
          end
        end

        it 'creates password file for new name' do
          allow(@manager).to receive(:get_password).and_return('new_password')
          expected_output = <<EOM
production Name: new_name

EOM
          expect { @manager.run(['--backup', '-s', 'new_name']) }.to output(
            expected_output).to_stdout
          new_password_file = File.join(@password_dir, 'new_name')
          expect( File.exist?(new_password_file) ).to eq true
          expect( File.exist?(new_password_file + '.salt') ).to eq false
          expect( File.exist?(new_password_file + '.last') ).to eq false
          expect( IO.read(new_password_file).chomp ).to eq 'new_password'
        end

        it 'allows multiple backups' do
          allow(@manager).to receive(:get_password).and_return('new_password')
          @manager.run(['--backup', '-s', 'production_name1'])
          expect { @manager.run(['--backup', '-s', 'production_name1']) }.not_to raise_error
          expect { @manager.run(['--backup', '-s', 'production_name1']) }.not_to raise_error
       end
      end

      context 'for specified password directory' do
        context 'with backups' do
          let(:expected_file_info) do {
              @name4_file                => 'new_password',
              @name4_salt_file + '.last' => 'env1_name4_salt',
              @name4_backup_file         => 'env1_name4_password'
            }
          end

          it 'updates password file and backs up old files per prompt' do
            allow(@manager).to receive(:get_password).and_return('new_password')
            allow(@manager).to receive(:yes_or_no).and_return(true)
            # not mocking query output
            expected_output = <<EOM
env1 Name: env1_name4

EOM
            validate_set_and_backup(@manager, ['-e', 'env1', '-s', 'env1_name4'],
              expected_output, expected_file_info)

            expect(File.exist?(@name4_salt_file)).to be false
          end

          it 'updates password file and backs up old files per --backup option' do
            allow(@manager).to receive(:get_password).and_return('new_password')
            expected_output = <<EOM
env1 Name: env1_name4

EOM
            validate_set_and_backup(@manager, ['-e', 'env1', '--backup', '-s', 'env1_name4' ],
              expected_output, expected_file_info)

            expect(File.exist?(@name4_salt_file)).to be false
          end
        end

        context 'without backups' do
          let(:expected_file_info) do {
              @name4_file                => 'new_password',
              @name4_backup_file         => 'env1_name4_backup_password' # unchanged
            }
          end

          it 'updates password file and does not back up old files per prompt' do
            allow(@manager).to receive(:get_password).and_return('new_password')
            allow(@manager).to receive(:yes_or_no).and_return(false)
            # not mocking query output
            expected_output = <<EOM
env1 Name: env1_name4

EOM
            validate_set_and_backup(@manager, ['-e', 'env1', '-s', 'env1_name4' ],
              expected_output, expected_file_info)

            expect(File.exist?(@name4_salt_file)).to eq false
            expect(File.exist?(@name4_salt_file + '.last')).to eq false
          end

          it 'updates password file and does not back up old files per --no-backup option' do
            allow(@manager).to receive(:get_password).and_return('new_password')
            expected_output = <<EOM
env1 Name: env1_name4

EOM
            validate_set_and_backup(@manager, ['-e', 'env1', '--no-backup', '-s', 'env1_name4' ],
              expected_output, expected_file_info)

            expect(File.exist?(@name4_salt_file)).to eq false
            expect(File.exist?(@name4_salt_file + '.last')).to eq false
          end
        end

        it 'creates password file for new name' do
          allow(@manager).to receive(:get_password).and_return('new_password')
          expected_output = <<EOM
env1 Name: new_name

EOM
          expect { @manager.run(['-e', 'env1', '--backup', '-s', 'new_name']) }.to output(
            expected_output).to_stdout
          new_password_file = File.join(@alt_password_dir, 'new_name')
          expect( File.exist?(new_password_file) ).to eq true
          expect( File.stat(new_password_file).mode & 0777 ).to eq 0640
          expect( File.exist?(new_password_file + '.last') ).to eq false
          expect( IO.read(new_password_file).chomp ).to eq 'new_password'
        end
      end

      it 'fails when no names specified' do
        expect { @manager.run(['-s']) }.to raise_error(OptionParser::MissingArgument)
      end

      it 'fails when password directory does not exist' do
        FileUtils.rm_rf(@password_dir)
        expect { @manager.run(['-s', 'production_name1']) }.to raise_error(
          Simp::Cli::ProcessingError,
          "Password directory '#{@password_dir}' does not exist")
      end

      it 'fails when password directory is not a directory' do
        FileUtils.rm_rf(@password_dir)
        FileUtils.touch(@password_dir)
        expect { @manager.run(['-s', 'production_name1']) }.to raise_error(
          Simp::Cli::ProcessingError,
          "Password directory '#{@password_dir}' is not a directory")
      end
    end

  end
=end
end
