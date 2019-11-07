require 'simp/cli/commands/passgen'
require 'spec_helper'
require 'etc'
require 'tmpdir'


=begin
def validate_set_and_backup(passgen, args, expected_output, expected_file_info)
  expect { passgen.run(args) }.to output(expected_output).to_stdout

  expected_file_info.each do |file,expected_contents|
    expect( File.exist?(file) ).to be true
    expect( IO.read(file).chomp ).to eq expected_contents
  end
end
=end

describe Simp::Cli::Commands::Passgen do

  let(:module_list_old_simplib) {
    <<-EOM
/etc/puppetlabs/code/environments/production/modules
├── puppet-yum (v3.1.1)
├── puppetlabs-stdlib (v5.2.0)
├── simp-aide (v6.3.0)
├── simp-simplib (v3.15.3)
/var/simp/environments/production/site_files
├── krb5_files (???)
└── pki_files (???)
/etc/puppetlabs/code/modules (no modules installed)
/opt/puppetlabs/puppet/modules (no modules installed)
    EOM
  }

  let(:module_list_new_simplib) {
    module_list_old_simplib.gsub(/simp-simplib .v3.15.3/,'simp-simplib (v4.0.0)')
  }

  let(:module_list_no_simplib) {
    list = module_list_old_simplib.dup.split("\n")
    list.delete_if { |line| line.include?('simp-simplib') }
    list.join("\n") + "\n"
  }

  let(:missing_deps_warnings) {
    <<-EOM
Warning: Missing dependency 'puppetlabs-apt':
  'puppetlabs-postgresql' (v5.12.1) requires 'puppetlabs-apt' (>= 2.0.0 < 7.0.0)
    EOM
  }

  describe '#find_valid_environments' do
    before :each do
      @tmp_dir   = Dir.mktmpdir(File.basename(__FILE__))
      @puppet_env_dir = File.join(@tmp_dir, 'environments')
      @user  = Etc.getpwuid(Process.uid).name
      @group = Etc.getgrgid(Process.gid).name
      puppet_info = {
        :config => {
          'user'            => @user,
          'group'           => @group,
          'environmentpath' => @puppet_env_dir
        }
      }

      allow(Simp::Cli::Utils).to receive(:puppet_info).and_return(puppet_info)
      @passgen = Simp::Cli::Commands::Passgen.new
    end

    after :each do
      FileUtils.remove_entry_secure @tmp_dir, true
    end

    it 'returns empty hash when Puppet environments dir is missing or inaccessible' do
      expect( @passgen.find_valid_environments ).to eq({})
    end

    it 'returns empty hash when Puppet environments dir is empty' do
      FileUtils.mkdir_p(@puppet_env_dir)
      expect( @passgen.find_valid_environments ).to eq({})
    end

    it 'returns empty hash when no Puppet environments have simp-simplib installed' do
      FileUtils.mkdir_p(File.join(@puppet_env_dir, 'production'))
      FileUtils.mkdir_p(File.join(@puppet_env_dir, 'dev'))
      FileUtils.mkdir_p(File.join(@puppet_env_dir, 'test'))

      module_list_results = {
        :status => true,
        :stdout => module_list_no_simplib,
        :stderr => missing_deps_warnings
      }

      [
        'puppet module list --color=false --environment=production',
        'puppet module list --color=false --environment=dev',
        'puppet module list --color=false --environment=test'
      ].each do |command|
        allow(Simp::Cli::ExecUtils).to receive(:run_command).with(command).and_return(module_list_results)
      end

      expect( @passgen.find_valid_environments ).to eq({})
    end

    it 'returns hash with only Puppet environments that have simp-simplib installed' do
      FileUtils.mkdir_p(File.join(@puppet_env_dir, 'production'))
      command = 'puppet module list --color=false --environment=production'
      module_list_results = {
        :status => true,
        :stdout => module_list_old_simplib,
        :stderr => missing_deps_warnings
      }
      allow(Simp::Cli::ExecUtils).to receive(:run_command).with(command).and_return(module_list_results)

      FileUtils.mkdir_p(File.join(@puppet_env_dir, 'dev'))
      command = 'puppet module list --color=false --environment=dev'
      module_list_results = {
        :status => true,
        :stdout => module_list_no_simplib,
        :stderr => missing_deps_warnings
      }
      allow(Simp::Cli::ExecUtils).to receive(:run_command).with(command).and_return(module_list_results)

      FileUtils.mkdir_p(File.join(@puppet_env_dir, 'test'))
      command = 'puppet module list --color=false --environment=test'
      module_list_results = {
        :status => true,
        :stdout => module_list_new_simplib,
        :stderr => missing_deps_warnings
      }
      allow(Simp::Cli::ExecUtils).to receive(:run_command).with(command).and_return(module_list_results)

      expected = { 'production' => '3.15.3', 'test' => '4.0.0' }
      expect( @passgen.find_valid_environments ).to eq(expected)
    end

    it 'fails if puppet module list command fails' do
      FileUtils.mkdir_p(File.join(@puppet_env_dir, 'production'))
      command = 'puppet module list --color=false --environment=production'
      module_list_results = {
        :status => false,
        :stdout => '',
        :stderr => 'some failure message'
      }
      allow(Simp::Cli::ExecUtils).to receive(:run_command).with(command).and_return(module_list_results)

      expect{ @passgen.find_valid_environments }.to raise_error(Simp::Cli::ProcessingError,
        "#{command} failed: some failure message")
    end
  end

  describe '#legacy_passgen?' do
    before :all do
      @passgen = Simp::Cli::Commands::Passgen.new
    end

    it 'should return true for old simplib' do
      expect( @passgen.legacy_passgen?('3.17.0') ).to eq(true)
    end

    it 'should return false for new simplib' do
      expect( @passgen.legacy_passgen?('4.0.1') ).to eq(false)
    end
  end

  describe '#run' do
    before :each do
      @tmp_dir   = Dir.mktmpdir(File.basename(__FILE__))
      @var_dir = File.join(@tmp_dir, 'vardir')
      @puppet_env_dir = File.join(@tmp_dir, 'environments')
      @user  = Etc.getpwuid(Process.uid).name
      @group = Etc.getgrgid(Process.gid).name
      puppet_info = {
        :config => {
          'user'   => @user,
          'group'  => @group,
          'vardir' => @var_dir,
          'environmentpath' => @puppet_env_dir
        }
      }

      allow(Simp::Cli::Utils).to receive(:puppet_info).and_return(puppet_info)
      @passgen = Simp::Cli::Commands::Passgen.new
    end

    after :each do
      FileUtils.remove_entry_secure @tmp_dir, true
    end

    describe '--list-env option' do
      it 'lists no environments, when no environments exist' do
        expected_output = "No environments with simp-simplib installed were found.\n\n"
        expect { @passgen.run(['--list-env']) }.to output(expected_output).to_stdout
      end

      it 'lists no environments, when no environments with simp-simplib exist' do
        FileUtils.mkdir_p(File.join(@puppet_env_dir, 'production'))
        command = 'puppet module list --color=false --environment=production'
        module_list_results = {
          :status => true,
          :stdout => module_list_no_simplib,
          :stderr => missing_deps_warnings
        }
        allow(Simp::Cli::ExecUtils).to receive(:run_command).with(command).and_return(module_list_results)

        expected_output = "No environments with simp-simplib installed were found.\n\n"
        expect { @passgen.run(['--list-env']) }.to output(expected_output).to_stdout
      end

      it 'lists available environments with simp-simplib installed' do
        FileUtils.mkdir_p(File.join(@puppet_env_dir, 'production'))
        command = 'puppet module list --color=false --environment=production'
        module_list_results = {
          :status => true,
          :stdout => module_list_old_simplib,
          :stderr => missing_deps_warnings
        }
        allow(Simp::Cli::ExecUtils).to receive(:run_command).with(command).and_return(module_list_results)

        FileUtils.mkdir_p(File.join(@puppet_env_dir, 'dev'))
        command = 'puppet module list --color=false --environment=dev'
        module_list_results = {
          :status => true,
          :stdout => module_list_no_simplib,
          :stderr => missing_deps_warnings
        }
        allow(Simp::Cli::ExecUtils).to receive(:run_command).with(command).and_return(module_list_results)

        FileUtils.mkdir_p(File.join(@puppet_env_dir, 'test'))
        command = 'puppet module list --color=false --environment=test'
        module_list_results = {
          :status => true,
          :stdout => module_list_new_simplib,
          :stderr => missing_deps_warnings
        }
        allow(Simp::Cli::ExecUtils).to receive(:run_command).with(command).and_return(module_list_results)
        expected_output = <<-EOM
Environments:
  production
  test

        EOM
        expect { @passgen.run(['-E']) }.to output(expected_output).to_stdout
      end

      it 'fails if puppet module list command fails' do
        FileUtils.mkdir_p(File.join(@puppet_env_dir, 'production'))
        command = 'puppet module list --color=false --environment=production'
        module_list_results = {
          :status => false,
          :stdout => '',
          :stderr => 'some failure message'
        }
        allow(Simp::Cli::ExecUtils).to receive(:run_command).with(command).and_return(module_list_results)

        expect { @passgen.run(['-E', '-d', @tmp_dir]) }.to raise_error(
          Simp::Cli::ProcessingError,
          "#{command} failed: some failure message")
      end
    end

    # The list name operation is fully tested in the objects that implement
    # this functionality.  This test is a subset of those tests with the intent
    # to verify the correct object was constructed and used and its results are
    # properly reported.
    describe '--list-name option' do
      context 'legacy manager for legacy passgen' do
        before :each do
          @password_env_dir = File.join(@var_dir, 'simp', 'environments')
          @default_password_dir = File.join(@password_env_dir, 'production', 'simp_autofiles', 'gen_passwd')
          FileUtils.mkdir_p(@default_password_dir)

          FileUtils.mkdir_p(File.join(@puppet_env_dir, 'production'))
          command = 'puppet module list --color=false --environment=production'
          module_list_results = {
            :status => true,
            :stdout => module_list_old_simplib,
            :stderr => missing_deps_warnings
          }
          allow(Simp::Cli::ExecUtils).to receive(:run_command).with(command).and_return(module_list_results)
        end

        it 'lists available names for default environment' do
          FileUtils.touch(File.join(@default_password_dir, 'production_name'))
          FileUtils.touch(File.join(@default_password_dir, 'production_name.salt'))
          FileUtils.touch(File.join(@default_password_dir, 'production_name.last'))
          FileUtils.touch(File.join(@default_password_dir, 'production_name.salt.last'))
          FileUtils.touch(File.join(@default_password_dir, '10.0.1.2'))
          FileUtils.touch(File.join(@default_password_dir, 'salt.and.pepper'))
          FileUtils.touch(File.join(@default_password_dir, 'my.last.name'))
          expected_output = <<EOM
'production' Environment Names:
  10.0.1.2
  my.last.name
  production_name
  salt.and.pepper

EOM
          expect { @passgen.run(['-l']) }.to output(expected_output).to_stdout
        end

        it 'lists available names for specified environment' do
          password_dir = File.join(@password_env_dir, 'env1', 'simp_autofiles', 'gen_passwd')
          FileUtils.mkdir_p(password_dir)
          FileUtils.touch(File.join(password_dir, 'env1_name1'))

          FileUtils.mkdir_p(File.join(@puppet_env_dir, 'env1'))
          command = 'puppet module list --color=false --environment=env1'
          module_list_results = {
            :status => true,
            :stdout => module_list_old_simplib,
            :stderr => missing_deps_warnings
          }
          allow(Simp::Cli::ExecUtils).to receive(:run_command).with(command).and_return(module_list_results)
          expected_output = <<EOM
'env1' Environment Names:
  env1_name1

EOM
          expect { @passgen.run(['-l', '-e', 'env1']) }.to output(expected_output).to_stdout
        end

        it 'fails when password directory is not a directory' do
          FileUtils.rm_rf(@default_password_dir)
          FileUtils.touch(@default_password_dir)
          expect { @passgen.run(['-l']) }.to raise_error(
            Simp::Cli::ProcessingError,
            "Password directory '#{@default_password_dir}' is not a directory")
        end
      end

=begin
      context 'current manager for legacy mode passgen' do
      end

      context 'current manager for libkv mode passgen' do
      end

=end
    end

=begin

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

def validate_set_and_backup(manager, args, expected_output, expected_file_info)
  expect { manager.set_passwords(*args) }.to output(expected_output).to_stdout

  expected_file_info.each do |file,expected_contents|
    if expected_contents.nil?
      expect( File.exist?(file) ).to be false
    else
      expect( File.exist?(file) ).to be true
      expect( IO.read(file).chomp ).to eq expected_contents
    end
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
    @alt_password_dir = File.join(@password_env_dir, 'gen_passwd')

    @user  = Etc.getpwuid(Process.uid).name
    @group = Etc.getgrgid(Process.gid).name
    puppet_info = {
      :config => {
        'user'   => @user,
        'group'  => @group,
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
Deleted #{@name1_file}
Deleted #{@name1_salt_file}
Deleted #{@name1_backup_file}
Deleted #{@name1_backup_salt_file}

Deleted #{@name2_file}
Deleted #{@name2_salt_file}

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

    it 'removes password, backup, and salt files in specified environment when force_remove=true' do
     expected_output = <<-EOM
Deleted #{@name1_file}
Deleted #{@name1_salt_file}
Deleted #{@name1_backup_file}
Deleted #{@name1_backup_salt_file}

Deleted #{@name2_file}
Deleted #{@name2_salt_file}

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

    it 'removes password, backup, and salt files in specified password dir when force_remove=true' do
      FileUtils.mkdir_p(@alt_password_dir)
      create_password_files(@alt_password_dir, ['env1_name4'])

      name4_file = File.join(@alt_password_dir, 'env1_name4')
      name4_salt_file = File.join(@alt_password_dir, 'env1_name4.salt')
      name4_backup_file = File.join(@alt_password_dir, 'env1_name4.last')
      name4_backup_salt_file = File.join(@alt_password_dir, 'env1_name4.salt.last')

      manager = Simp::Cli::Passgen::LegacyPasswordManager.new(@env, @alt_password_dir)

      expected_output = <<-EOM
Deleted #{name4_file}
Deleted #{name4_salt_file}
Deleted #{name4_backup_file}
Deleted #{name4_backup_salt_file}

      EOM

      expect { manager.remove_passwords(['env1_name4'], true) }.to \
        output(expected_output).to_stdout

      expect(File.exist?(name4_file)).to eq false
      expect(File.exist?(name4_salt_file)).to eq false
      expect(File.exist?(name4_backup_file)).to eq false
      expect(File.exist?(name4_backup_salt_file)).to eq false
    end

    it 'deletes all accessible files and fails with list of file delete failures' do
      allow(File).to receive(:unlink).with(any_args).and_call_original
      unreadable_files = [
        File.join(@password_dir, 'production_name2'),
        File.join(@password_dir, 'production_name2.salt')
      ]
      unreadable_files.each do |file|
        allow(File).to receive(:unlink).with(file).and_raise(
          Errno::EACCES, 'failed delete')
      end
     expected_stdout = <<-EOM
Deleted #{@name1_file}
Deleted #{@name1_salt_file}
Deleted #{@name1_backup_file}
Deleted #{@name1_backup_salt_file}


Deleted #{@name3_file}
Deleted #{@name3_salt_file}
Deleted #{@name3_backup_file}
Deleted #{@name3_backup_salt_file}

      EOM

      expected_err_msg = <<-EOM
Failed to delete the following password files:
  '#{unreadable_files[0]}': Permission denied - failed delete
  '#{unreadable_files[1]}': Permission denied - failed delete
      EOM

      names = ['production_name1', 'production_name2', 'production_name3']
      expect { @manager.remove_passwords(names, true) }.to raise_error(
        Simp::Cli::ProcessingError,
        expected_err_msg.strip).and output(expected_stdout).to_stdout
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
      @name2_backup_file = File.join(@password_dir, 'production_name2.last')
      @name2_backup_salt_file = File.join(@password_dir, 'production_name2.salt.last')

      @name3_file = File.join(@password_dir, 'production_name3')
      @name3_salt_file = File.join(@password_dir, 'production_name3.salt')
      @name3_backup_file = File.join(@password_dir, 'production_name3.last')
      @name3_backup_salt_file = File.join(@password_dir, 'production_name3.salt.last')
    end

    let(:options) do
      {
        :auto_gen       => false,
        :force_value    => false,
        :default_length => 32,
        :minimum_length => 8,
      }
    end

    let(:expected_file_info) do
      {
        # new password, no salt, and full backup
        @name1_file             => 'first_new_password',
        @name1_salt_file        => nil,
        @name1_backup_file      => 'production_name1_password',
        @name1_backup_salt_file => 'salt for production_name1',

        # new password, no salt, and full backup
        @name2_file             => 'second_new_password',
        @name2_salt_file        => nil,
        @name2_backup_file      => 'production_name2_password',
        @name2_backup_salt_file => 'salt for production_name2',

        # unchanged
        @name3_file             => 'production_name3_password',
        @name3_salt_file        => 'salt for production_name3',
        @name3_backup_file      => 'production_name3_backup_password',
        @name3_backup_salt_file => 'salt for production_name3 backup password'
      }
    end

    it 'updates password file and backs up old files in the specified environment' do
      # bypass password input
      allow(@manager).to receive(:get_new_password).and_return(
        ['first_new_password', false], ['second_new_password', false])

      # NOTE:  FileUtils.mv with :verbose sends output to something other than stdout
      expected_output = <<-EOM
Processing Name 'production_name1' in production Environment
  Password set

Processing Name 'production_name2' in production Environment
  Password set

      EOM

      validate_set_and_backup(@manager,
        [ ['production_name1', 'production_name2'], options ],
        expected_output, expected_file_info)
    end

    it 'updates password file and backs up old files in the specified password dir' do
      FileUtils.mkdir_p(@alt_password_dir)
      create_password_files(@alt_password_dir, ['env1_name4'])

      name4_file = File.join(@alt_password_dir, 'env1_name4')
      name4_salt_file = File.join(@alt_password_dir, 'env1_name4.salt')
      name4_backup_file = File.join(@alt_password_dir, 'env1_name4.last')
      name4_backup_salt_file = File.join(@alt_password_dir, 'env1_name4.salt.last')

      manager = Simp::Cli::Passgen::LegacyPasswordManager.new(@env, @alt_password_dir)
      allow(manager).to receive(:get_new_password).and_return(['new_password',false])

      # NOTE:  FileUtils.mv with :verbose sends output to something other than stdout
      expected_output = <<-EOM
Processing Name 'env1_name4' in #{@alt_password_dir}
  Password set

      EOM

      expected_file_info = {
        # new password, no salt, and full backup
        name4_file             => 'new_password',
        name4_salt_file        => nil,
        name4_backup_file      => 'env1_name4_password',
        name4_backup_salt_file => 'salt for env1_name4'
      }

      validate_set_and_backup(manager, [ ['env1_name4'], options ],
        expected_output, expected_file_info)
    end

    it 'creates and sets password when auto_gen=true' do
      new_options = options.dup
      new_options[:auto_gen] = true
      expected_regex = /Processing Name 'production_name1' in production Environment\n  Password set to '.*'/m
      expect { @manager.set_passwords(['production_name1'], new_options) }.to \
        output(expected_regex).to_stdout
    end

    it 'creates password file for new name' do
      allow(@manager).to receive(:get_new_password).and_return(['new_password',false])

      expected_output = <<-EOM
Processing Name 'new_name' in production Environment
  Password set

      EOM
      expect { @manager.set_passwords(['new_name'], options) }.to \
        output(expected_output).to_stdout
      new_password_file = File.join(@password_dir, 'new_name')
      expect( File.exist?(new_password_file) ).to eq true
      expect( File.exist?(new_password_file + '.salt') ).to eq false
      expect( File.exist?(new_password_file + '.last') ).to eq false
      expect( IO.read(new_password_file).chomp ).to eq 'new_password'
    end

    it 'allows multiple backups' do
      allow(@manager).to receive(:get_new_password).and_return(['new_password',false])
      expect { @manager.set_passwords(['name1'], options) }.not_to raise_error
      expect { @manager.set_passwords(['name1'], options) }.not_to raise_error
    end

    it 'updates and backs up what it can and fails with list of file operation failures' do
      files = {
        'pw_read_failure'   => File.join(@password_dir, 'pw_read_failure'),
        'good1'             => File.join(@password_dir, 'good1'),
        'pw_move_failure'   => File.join(@password_dir, 'pw_move_failure'),
        'good2'             => File.join(@password_dir, 'good2'),
        'salt_move_failure' => File.join(@password_dir, 'salt_move_failure'),
        'pw_write_failure'  => File.join(@password_dir, 'pw_write_failure'),
        'pw_chown_failure'  => File.join(@password_dir, 'pw_chown_failure')
      }
      create_password_files(@password_dir, files.keys)

      # password file read failure
      allow(File).to receive(:read).with(any_args).and_call_original
      allow(File).to receive(:read).with(files['pw_read_failure']).and_raise(
        Errno::EACCES, 'failed password file read')

      # password file move failure
      allow(FileUtils).to receive(:mv).with(any_args).and_call_original
      allow(FileUtils).to receive(:mv).with(files['pw_move_failure'],
        files['pw_move_failure'] + '.last', :verbose => true, :force => true).and_raise(
        Errno::EACCES, 'failed password file move')

      # salt file move failure
      allow(FileUtils).to receive(:mv).with(files['salt_move_failure'],
        files['salt_move_failure'] + '.last', :verbose => true, :force => true).and_raise(
        Errno::EACCES, 'failed salt file move')

      # password file write failure
      allow(File).to receive(:open).with(any_args).and_call_original
      allow(File).to receive(:open).with(files['pw_write_failure'], 'w').and_raise(
        Errno::EACCES, 'failed password file write')

      allow(FileUtils).to receive(:chown).with(any_args).and_call_original
      allow(FileUtils).to receive(:chown).with(@user, @group, files['pw_chown_failure']).and_raise(
        ArgumentError, 'failed password file chown')

      allow(@manager).to receive(:get_new_password).and_return(['new_password',false])

      expected_stdout = <<-EOM
Processing Name 'pw_read_failure' in production Environment

Processing Name 'good1' in production Environment
  Password set

Processing Name 'pw_move_failure' in production Environment

Processing Name 'good2' in production Environment
  Password set

Processing Name 'salt_move_failure' in production Environment

Processing Name 'pw_write_failure' in production Environment

Processing Name 'pw_chown_failure' in production Environment

      EOM

      expected_err_msg = <<-EOM
Failed to set 5 out of 7 passwords:
  'pw_read_failure': Error occurred while reading '#{files['pw_read_failure']}': Permission denied - failed password file read
  'pw_move_failure': Error occurred while backing up '#{files['pw_move_failure']}': Permission denied - failed password file move
  'salt_move_failure': Error occurred while backing up '#{files['salt_move_failure']}': Permission denied - failed salt file move
  'pw_write_failure': Error occurred while writing '#{files['pw_write_failure']}': Permission denied - failed password file write
  'pw_chown_failure': Could not set password file ownership for '#{files['pw_chown_failure']}': failed password file chown
      EOM

      expect { @manager.set_passwords(files.keys, options) }.to raise_error(
        Simp::Cli::ProcessingError,
        expected_err_msg.strip).and output(expected_stdout).to_stdout
    end

    it 'fails when no names specified' do
      expect { @manager.set_passwords([], options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'No names specified.')
    end

    it 'fails when password directory does not exist' do
      FileUtils.rm_rf(@password_dir)
      expect { @manager.set_passwords(['name1'], options) }.to raise_error(
        Simp::Cli::ProcessingError,
        "Password directory '#{@password_dir}' does not exist")
    end

    it 'fails when password directory is not a directory' do
      FileUtils.rm_rf(@password_dir)
      FileUtils.touch(@password_dir)
      expect { @manager.set_passwords(['name1'], options) }.to raise_error(
        Simp::Cli::ProcessingError,
        "Password directory '#{@password_dir}' is not a directory")
    end

    it 'fails when :auto_gen option missing' do
      bad_options = {
        :force_value    => false,
        :default_length => 32,
        :minimum_length => 8,
      }

      expect { @manager.set_passwords(['name1'], bad_options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'Missing :auto_gen option')
    end

    it 'fails when :force_value option missing' do
      bad_options = {
        :auto_gen       => false,
        :default_length => 32,
        :minimum_length => 8,
      }

      expect { @manager.set_passwords(['name1'], bad_options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'Missing :force_value option')
    end

    it 'fails when :default_length option missing' do
      bad_options = {
        :auto_gen       => false,
        :force_value    => false,
        :minimum_length => 8,
      }

      expect { @manager.set_passwords(['name1'], bad_options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'Missing :default_length option')
    end

    it 'fails when :minimum_length option missing' do
      bad_options = {
        :auto_gen       => false,
        :force_value    => false,
        :default_length => 32,
      }

      expect { @manager.set_passwords(['name1'], bad_options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'Missing :minimum_length option')
    end
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

    it 'lists available names for a specified password dir' do
      FileUtils.mkdir_p(@alt_password_dir)
      names = ['app1_user', 'app2_user' ]
      create_password_files(@alt_password_dir, names)
      manager = Simp::Cli::Passgen::LegacyPasswordManager.new(@env, @alt_password_dir)
      expected_output = <<-EOM
#{@alt_password_dir} Names:
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

    it 'shows current and previous passwords for specified names in a specified password dir' do
      FileUtils.mkdir_p(@alt_password_dir)
      create_password_files(@alt_password_dir, ['env1_name1'])
      manager = Simp::Cli::Passgen::LegacyPasswordManager.new(@env, @alt_password_dir)
      expected_output = <<-EOM
#{@alt_password_dir} Passwords
#{'='*@alt_password_dir.length}==========
Name: env1_name1
  Current:  env1_name1_password
  Previous: env1_name1_backup_password

      EOM
      expect { manager.show_passwords(['env1_name1']) }.
        to output(expected_output).to_stdout
    end

    it 'reports all accessible passwords and fails with list of password read failures' do
      names = ['name1', 'name2', 'name3']
      create_password_files(@password_dir, names)
      unreadable_file = File.join(@password_dir, 'name2')
      allow(File).to receive(:read).with(any_args).and_call_original
      allow(File).to receive(:read).with(unreadable_file).and_raise(
        Errno::EACCES, 'failed read')

      expected_stdout = <<-EOM
production Environment Passwords
================================
Name: name1
  Current:  name1_password
  Previous: name1_backup_password

Name: name2
  UNKNOWN

Name: name3
  Current:  name3_password
  Previous: name3_backup_password

      EOM

      expected_err_msg = <<-EOM
Failed to read password info for the following:
  'name2': Permission denied - failed read
      EOM

      expect { @manager.show_passwords(names) }.to raise_error(
        Simp::Cli::ProcessingError,
        expected_err_msg.strip).and output(expected_stdout).to_stdout
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

  # Helpers.  Since most helper methods are fully tested in Operations tests,
  # only use cases not otherwise tested are exercised here.

  describe '#get_new_password' do
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

    let(:good_password) { 'A=V3ry=Go0d=P@ssw0r!' }
    let(:bad_password) { 'password' }
    let(:short_password) { 'short' }

    let(:options) do
      {
        :auto_gen       => false,
        :force_value    => false,
        :default_length => 32,
        :minimum_length => 8,
        # If you set this too short on a SIMP-managed dev system,
        # password generation will be in a constant retry loop!
        :length         => 24
      }
    end

    it 'autogenerates a password of specified length when auto_gen=true' do
      new_options = options.dup
      new_options[:auto_gen] = true
      expect( @manager.get_new_password(new_options)[0].length ).to eq(24)
      expect( @manager.get_new_password(new_options)[1]).to be(true)
    end

    it 'gathers and returns valid user password when auto_gen=false' do
      @input << "#{good_password}\n"
      @input << "#{good_password}\n"
      @input.rewind
      expect( @manager.get_new_password(options)).to eq([good_password, false])
    end

    it 'gathers and returns insufficient complexity user password when auto_gen=false and force_value=true' do
      new_options = options.dup
      new_options[:force_value] = true
      @input << "#{bad_password}\n"
      @input << "#{bad_password}\n"
      @input.rewind
      expect( @manager.get_new_password(new_options)).to eq([bad_password, false])
    end

    it 'gathers and returns too short user password when auto_gen=false and force_value=true' do
      new_options = options.dup
      new_options[:force_value] = true
      @input << "#{short_password}\n"
      @input << "#{short_password}\n"
      @input.rewind
      expect( @manager.get_new_password(new_options)).to eq([short_password, false])
    end
  end

  describe '#get_password_length' do
    before(:each) do
      FileUtils.mkdir_p(@password_dir)
      @name = 'name'
      @password_file = File.join(@password_dir, @name)
    end

    let(:options) do
      {
        :default_length => 32,
        :minimum_length => 8
      }
    end


    it 'returns default length when password file does not exist and length option unset' do
      expect( @manager.get_password_length(@password_file, options) ).to eq(options[:default_length])
    end

    it 'returns length matching existing password length when it is valid and length option unset' do
      File.open(@password_file, 'w') { |file| file.puts '12345678' }
      expect( @manager.get_password_length(@password_file, options) ).to eq(8)
    end

    it 'returns default length when existing password length is too short and length option unset' do
      File.open(@password_file, 'w') { |file| file.puts '1234567' }
      expect( @manager.get_password_length(@password_file, options) ).to eq(options[:default_length])
    end

    it 'returns options length it is valid' do
      File.open(@password_file, 'w') { |file| file.puts "name_password" }
      new_options = options.dup
      new_options[:length] = 48
      expect( @manager.get_password_length(@password_file, new_options) ).to eq(48)
    end

    it 'returns default length when options length length is too short' do
      File.open(@password_file, 'w') { |file| file.puts "name_password" }
      new_options = options.dup
      new_options[:length] = 6
      expect( @manager.get_password_length(@password_file, new_options) ).to eq(new_options[:default_length])
    end
  end
end
=end
=begin
    # The list name operation is fully tested in the objects that implement
    # this functionality.  This test is a subset of those tests with the intent
    # to verify the correct object was constructed and used and its results are
    # properly reported.
    describe '--name option' do
      before :each do
        @default_password_dir = File.join(@password_env_dir, 'production', 'simp_autofiles', 'gen_passwd')
        FileUtils.mkdir_p(@default_password_dir)
        @name1_file = File.join(@default_password_dir, 'production_name1')
        File.open(@name1_file, 'w') { |file| file.puts "production_name1_password" }
        @name1_backup_file = File.join(@default_password_dir, 'production_name1.last')
        File.open(@name1_backup_file, 'w') { |file| file.puts "production_name1_backup_password" }
        @name2_file = File.join(@default_password_dir, 'production_name2')
        File.open(@name2_file, 'w') { |file| file.puts "production_name2_password" }
        @name3_file = File.join(@default_password_dir, 'production_name3')
        File.open(@name3_file, 'w') { |file| file.puts "production_name3_password" }
        @name3_backup_file = File.join(@default_password_dir, 'production_name3.last')
        File.open(@name3_backup_file, 'w') { |file| file.puts "production_name3_backup_password" }
      end

      it 'shows current and previous passwords for specified names of default environment' do
        expected_output = <<EOM
'production' Environment Passwords
==================================
Name: production_name2
  Current:  production_name2_password

Name: production_name3
  Current:  production_name3_password
  Previous: production_name3_backup_password

EOM
        expect { @passgen.run(['--name', 'production_name2,production_name3']) }.to output(expected_output).to_stdout
      end

      it 'shows current and previous passwords for specified names of specified environment' do
        password_dir = File.join(@password_env_dir, 'env1', 'simp_autofiles', 'gen_passwd')
        FileUtils.mkdir_p(password_dir)
        name1_file = File.join(password_dir, 'env1_name1')
        File.open(name1_file, 'w') { |file| file.puts "env1_name1_password" }
        name1_backup_file = File.join(password_dir, 'env1_name1.last')
        File.open(name1_backup_file, 'w') { |file| file.puts "env1_name1_backup_password" }
        expected_output = <<EOM
'env1' Environment Passwords
============================
Name: env1_name1
  Current:  env1_name1_password
  Previous: env1_name1_backup_password

EOM
        expect { @passgen.run(['-e', 'env1', '-n', 'env1_name1']) }.to output(expected_output).to_stdout
      end

      it 'fails when no names specified' do
        expect { @passgen.run(['-n']) }.to raise_error(OptionParser::MissingArgument)
      end

      it 'fails when invalid name specified' do
        expect { @passgen.run(['-n', 'oops']) }.to raise_error(
          OptionParser::ParseError,
          /Invalid name 'oops' selected.\n\nValid names: production_name1, production_name2, production_name3/)
      end

      it 'fails when password directory does not exist' do
        FileUtils.rm_rf(@default_password_dir)
        expect { @passgen.run(['-n', 'production_name1']) }.to raise_error(
          Simp::Cli::ProcessingError,
          "Password directory '#{@default_password_dir}' does not exist")
      end

      it 'fails when password directory is not a directory' do
        FileUtils.rm_rf(@default_password_dir)
        FileUtils.touch(@default_password_dir)
        expect { @passgen.run(['-n', 'production_name1']) }.to raise_error(
          Simp::Cli::ProcessingError,
          "Password directory '#{@default_password_dir}' is not a directory")
      end
    end

    describe '--set option' do
      before :each do
        @default_password_dir = File.join(@password_env_dir, 'production', 'simp_autofiles', 'gen_passwd')
        FileUtils.mkdir_p(@default_password_dir)

        @name1_file = File.join(@default_password_dir, 'production_name1')
        File.open(@name1_file, 'w') { |file| file.puts "production_name1_password" }
        @name1_salt_file = File.join(@default_password_dir, 'production_name1.salt')
        File.open(@name1_salt_file, 'w') { |file| file.puts 'production_name1_salt' }
        @name1_backup_file = File.join(@default_password_dir, 'production_name1.last')
        File.open(@name1_backup_file, 'w') { |file| file.puts "production_name1_backup_password" }

        @name2_file = File.join(@default_password_dir, 'production_name2')
        File.open(@name2_file, 'w') { |file| file.puts "production_name2_password" }

        @name3_file = File.join(@default_password_dir, 'production_name3')
        File.open(@name3_file, 'w') { |file| file.puts "production_name3_password" }
        @name3_backup_file = File.join(@default_password_dir, 'production_name3.last')
        File.open(@name3_backup_file, 'w') { |file| file.puts "production_name3_backup_password" }

        @env1_password_dir = File.join(@password_env_dir, 'env1', 'simp_autofiles', 'gen_passwd')
        FileUtils.mkdir_p(@env1_password_dir)
        @name4_file = File.join(@env1_password_dir, 'env1_name4')
        File.open(@name4_file, 'w') { |file| file.puts "env1_name4_password" }
        @name4_salt_file = File.join(@env1_password_dir, 'env1_name4.salt')
        File.open(@name4_salt_file, 'w') { |file| file.puts "env1_name4_salt" }
        @name4_backup_file = File.join(@env1_password_dir, 'env1_name4.last')
        File.open(@name4_backup_file, 'w') { |file| file.puts "env1_name4_backup_password" }
      end

      context 'with default environment' do
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
            allow(@passgen).to receive(:get_password).and_return(
              'first_new_password', 'second_new_password')
            allow(@passgen).to receive(:yes_or_no).and_return(true)
            expected_output = <<EOM
production Name: production_name1

production Name: production_name2

EOM
            validate_set_and_backup(@passgen, ['-s', 'production_name1,production_name2' ],
              expected_output, expected_file_info)

            expect(File.exist?(@name1_salt_file)).to be false
          end

          it 'updates password file and backs up old files per --backup option' do
            allow(@passgen).to receive(:get_password).and_return(
              'first_new_password', 'second_new_password')
            expected_output = <<EOM
production Name: production_name1

production Name: production_name2

EOM
            validate_set_and_backup(@passgen, ['--backup', '-s', 'production_name1,production_name2' ],
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
            allow(@passgen).to receive(:get_password).and_return(
              'first_new_password', 'second_new_password')
            allow(@passgen).to receive(:yes_or_no).and_return(true)
            allow(@passgen).to receive(:yes_or_no).and_return(false)

            # not mocking query output
            expected_output = <<EOM
production Name: production_name1

production Name: production_name2

EOM
            validate_set_and_backup(@passgen, ['-s', 'production_name1,production_name2' ],
              expected_output, expected_file_info)

            expect(File.exist?(@name1_salt_file)).to be false
            expect(File.exist?(@name1_salt_file + '.last')).to be false
            expect(File.exist?(@name2_file + '.last')).to eq false
          end

          it 'updates password file and does not back up old files per --no-backup option' do
            allow(@passgen).to receive(:get_password).and_return(
              'first_new_password', 'second_new_password')
            expected_output = <<EOM
production Name: production_name1

production Name: production_name2

EOM
            validate_set_and_backup(@passgen, ['--no-backup', '-s', 'production_name1,production_name2' ],
              expected_output, expected_file_info)

            expect(File.exist?(@name1_salt_file)).to be false
            expect(File.exist?(@name1_salt_file + '.last')).to be false
            expect(File.exist?(@name2_file + '.last')).to eq false
          end
        end

        it 'creates password file for new name' do
          allow(@passgen).to receive(:get_password).and_return('new_password')
          expected_output = <<EOM
production Name: new_name

EOM
          expect { @passgen.run(['--backup', '-s', 'new_name']) }.to output(
            expected_output).to_stdout
          new_password_file = File.join(@default_password_dir, 'new_name')
          expect( File.exist?(new_password_file) ).to eq true
          expect( File.exist?(new_password_file + '.salt') ).to eq false
          expect( File.exist?(new_password_file + '.last') ).to eq false
          expect( IO.read(new_password_file).chomp ).to eq 'new_password'
        end

        it 'allows multiple backups' do
          allow(@passgen).to receive(:get_password).and_return('new_password')
          @passgen.run(['--backup', '-s', 'production_name1'])
          expect { @passgen.run(['--backup', '-s', 'production_name1']) }.not_to raise_error
          expect { @passgen.run(['--backup', '-s', 'production_name1']) }.not_to raise_error
       end
      end

      context 'specified environment' do
        context 'with backups' do
          let(:expected_file_info) do {
              @name4_file                => 'new_password',
              @name4_salt_file + '.last' => 'env1_name4_salt',
              @name4_backup_file         => 'env1_name4_password'
            }
          end

          it 'updates password file and backs up old files per prompt' do
            allow(@passgen).to receive(:get_password).and_return('new_password')
            allow(@passgen).to receive(:yes_or_no).and_return(true)
            # not mocking query output
            expected_output = <<EOM
env1 Name: env1_name4

EOM
            validate_set_and_backup(@passgen, ['-e', 'env1', '-s', 'env1_name4'],
              expected_output, expected_file_info)

            expect(File.exist?(@name4_salt_file)).to be false
          end

          it 'updates password file and backs up old files per --backup option' do
            allow(@passgen).to receive(:get_password).and_return('new_password')
            expected_output = <<EOM
env1 Name: env1_name4

EOM
            validate_set_and_backup(@passgen, ['-e', 'env1', '--backup', '-s', 'env1_name4' ],
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
            allow(@passgen).to receive(:get_password).and_return('new_password')
            allow(@passgen).to receive(:yes_or_no).and_return(false)
            # not mocking query output
            expected_output = <<EOM
env1 Name: env1_name4

EOM
            validate_set_and_backup(@passgen, ['-e', 'env1', '-s', 'env1_name4' ],
              expected_output, expected_file_info)

            expect(File.exist?(@name4_salt_file)).to eq false
            expect(File.exist?(@name4_salt_file + '.last')).to eq false
          end

          it 'updates password file and does not back up old files per --no-backup option' do
            allow(@passgen).to receive(:get_password).and_return('new_password')
            expected_output = <<EOM
env1 Name: env1_name4

EOM
            validate_set_and_backup(@passgen, ['-e', 'env1', '--no-backup', '-s', 'env1_name4' ],
              expected_output, expected_file_info)

            expect(File.exist?(@name4_salt_file)).to eq false
            expect(File.exist?(@name4_salt_file + '.last')).to eq false
          end
        end

        it 'creates password file for new name' do
          allow(@passgen).to receive(:get_password).and_return('new_password')
          expected_output = <<EOM
env1 Name: new_name

EOM
          expect { @passgen.run(['-e', 'env1', '--backup', '-s', 'new_name']) }.to output(
            expected_output).to_stdout
          new_password_file = File.join(@env1_password_dir, 'new_name')
          expect( File.exist?(new_password_file) ).to eq true
          expect( File.stat(new_password_file).mode & 0777 ).to eq 0640
          expect( File.exist?(new_password_file + '.last') ).to eq false
          expect( IO.read(new_password_file).chomp ).to eq 'new_password'
        end
      end

      it 'fails when no names specified' do
        expect { @passgen.run(['-s']) }.to raise_error(OptionParser::MissingArgument)
      end

      it 'fails when password directory does not exist' do
        FileUtils.rm_rf(@default_password_dir)
        expect { @passgen.run(['-s', 'production_name1']) }.to raise_error(
          Simp::Cli::ProcessingError,
          "Password directory '#{@default_password_dir}' does not exist")
      end

      it 'fails when password directory is not a directory' do
        FileUtils.rm_rf(@default_password_dir)
        FileUtils.touch(@default_password_dir)
        expect { @passgen.run(['-s', 'production_name1']) }.to raise_error(
          Simp::Cli::ProcessingError,
          "Password directory '#{@default_password_dir}' is not a directory")
      end
    end

    describe '--remove option' do
      before :each do
        @default_password_dir = File.join(@password_env_dir, 'production', 'simp_autofiles', 'gen_passwd')
        FileUtils.mkdir_p(@default_password_dir)

        @name1_file = File.join(@default_password_dir, 'production_name1')
        File.open(@name1_file, 'w') { |file| file.puts 'production_name1_password' }
        @name1_salt_file = File.join(@default_password_dir, 'production_name1.salt')
        File.open(@name1_salt_file, 'w') { |file| file.puts 'production_name1_salt' }
        @name1_backup_file = File.join(@default_password_dir, 'production_name1.last')
        File.open(@name1_backup_file, 'w') { |file| file.puts 'production_name1_backup_password' }

        @name2_file = File.join(@default_password_dir, 'production_name2')
        File.open(@name2_file, 'w') { |file| file.puts 'production_name2_password' }

        @name3_file = File.join(@default_password_dir, 'production_name3')
        File.open(@name3_file, 'w') { |file| file.puts 'production_name3_password' }
        @name3_backup_file = File.join(@default_password_dir, 'production_name3.last')
        File.open(@name3_backup_file, 'w') { |file| file.puts 'production_name3_backup_password' }

        @env1_password_dir = File.join(@password_env_dir, 'env1', 'simp_autofiles', 'gen_passwd')
        FileUtils.mkdir_p(@env1_password_dir)
        @name4_file = File.join(@env1_password_dir, 'env1_name4')
        File.open(@name4_file, 'w') { |file| file.puts 'env1_name4_password' }
        @name4_salt_file = File.join(@env1_password_dir, 'env1_name4.salt')
        File.open(@name4_salt_file, 'w') { |file| file.puts 'env1_name4_salt' }
        @name4_backup_file = File.join(@env1_password_dir, 'env1_name4.last')
        File.open(@name4_backup_file, 'w') { |file| file.puts 'env1_name4_backup_password' }
      end

      context 'with default environment' do
        it 'removes password, backup, and salt files when prompt returns yes' do
          allow(@passgen).to receive(:yes_or_no).and_return(true)
          # not mocking query output
          expected_output = <<EOM
#{@name1_file} deleted
#{@name1_salt_file} deleted
#{@name1_backup_file} deleted

#{@name2_file} deleted

EOM
          expect { @passgen.run(['-r',
            'production_name1,production_name2' ]) }.to output(expected_output).to_stdout

          expect(File.exist?(@name1_file)).to eq false
          expect(File.exist?(@name1_salt_file)).to eq false
          expect(File.exist?(@name1_backup_file)).to eq false
          expect(File.exist?(@name2_file)).to eq false
          expect(File.exist?(@name3_file)).to eq true
          expect(File.exist?(@name3_backup_file)).to eq true
        end

        it 'does not remove password, backup and salt files when prompt returns no' do
          allow(@passgen).to receive(:yes_or_no).and_return(false)
          # not mocking query output
          expected_output = "\n\n"
          expect { @passgen.run(['-r',
            'production_name1,production_name2' ]) }.to output(expected_output).to_stdout

          expect(File.exist?(@name1_file)).to eq true
          expect(File.exist?(@name1_salt_file)).to eq true
          expect(File.exist?(@name1_backup_file)).to eq true
          expect(File.exist?(@name2_file)).to eq true
          expect(File.exist?(@name3_file)).to eq true
          expect(File.exist?(@name3_backup_file)).to eq true
        end

        it 'removes password, backup, and salt files, without prompting with --force-remove option' do
          expected_output = <<EOM
#{@name1_file} deleted
#{@name1_salt_file} deleted
#{@name1_backup_file} deleted

#{@name2_file} deleted

EOM
          expect { @passgen.run(['-r', 'production_name1,production_name2',
            '--force-remove']) }.to output(expected_output).to_stdout

          expect(File.exist?(@name1_file)).to eq false
          expect(File.exist?(@name1_salt_file)).to eq false
          expect(File.exist?(@name1_backup_file)).to eq false
          expect(File.exist?(@name2_file)).to eq false
          expect(File.exist?(@name3_file)).to eq true
          expect(File.exist?(@name3_backup_file)).to eq true
        end
      end

      context 'specified environment' do
        it 'removes password, backup, and salt files, per prompt' do
          allow(@passgen).to receive(:yes_or_no).and_return(true)
          # not mocking query output
          expected_output = <<EOM
#{@name4_file} deleted
#{@name4_salt_file} deleted
#{@name4_backup_file} deleted

EOM
          expect { @passgen.run(['-e', 'env1', '-r',
            'env1_name4']) }.to output(expected_output).to_stdout

          expect(File.exist?(@name4_file)).to eq false
          expect(File.exist?(@name4_salt_file)).to eq false
          expect(File.exist?(@name4_backup_file)).to eq false
        end

        it 'does not remove password files, including backup files, per prompt' do
          allow(@passgen).to receive(:yes_or_no).and_return(false)
          # not mocking query output
          expected_output = "\n"
          expect { @passgen.run(['-e', 'env1', '-r',
            'env1_name4']) }.to output(expected_output).to_stdout

          expect(File.exist?(@name4_file)).to eq true
          expect(File.exist?(@name4_salt_file)).to eq true
          expect(File.exist?(@name4_backup_file)).to eq true
        end

        it 'removes password files, including backup files, without prompting with --force-remove option' do
          expected_output = <<EOM
#{@name4_file} deleted
#{@name4_salt_file} deleted
#{@name4_backup_file} deleted

EOM
          expect { @passgen.run(['-e', 'env1', '-r', 'env1_name4',
            '--force-remove']) }.to output(expected_output).to_stdout

          expect(File.exist?(@name4_file)).to eq false
          expect(File.exist?(@name4_salt_file)).to eq false
          expect(File.exist?(@name4_backup_file)).to eq false
        end
      end

      it 'fails when no names specified' do
        expect { @passgen.run(['-r']) }.to raise_error(OptionParser::MissingArgument)
      end

      it 'fails when invalid names specified' do
        expect { @passgen.run(['-r', 'production_name1,oops,production_name2']) }.to raise_error(
          OptionParser::ParseError,
          /Invalid name 'oops' selected.\n\nValid names: production_name1, production_name2/)
      end

      it 'fails when password directory does not exist' do
        FileUtils.rm_rf(@default_password_dir)
        expect { @passgen.run(['-r', 'production_name1']) }.to raise_error(
          Simp::Cli::ProcessingError,
          "Password directory '#{@default_password_dir}' does not exist")
      end

      it 'fails when password directory is not a directory' do
        FileUtils.rm_rf(@default_password_dir)
        FileUtils.touch(@default_password_dir)
        expect { @passgen.run(['-r', 'production_name1']) }.to raise_error(
          Simp::Cli::ProcessingError,
          "Password directory '#{@default_password_dir}' is not a directory")
      end
    end
=end

    describe 'option validation' do
      it 'requires operation option to be specified' do
        expect { @passgen.run([]) }.to raise_error(OptionParser::ParseError,
          /The SIMP Passgen Tool requires at least one option/)

        expect { @passgen.run(['-e', 'production']) }.to raise_error(OptionParser::ParseError,
          /No password operation specified./)
      end
    end
  end
end
