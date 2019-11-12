require 'simp/cli/passgen/password_manager'

require 'etc'
require 'spec_helper'

describe Simp::Cli::Passgen::PasswordManager do
  before :each do
    @user  = Etc.getpwuid(Process.uid).name
    @group = Etc.getgrgid(Process.gid).name
    @env = 'production'
    puppet_info = {
      :config => {
        'user'   => @user,
        'group'  => @group,
        'vardir' => '/server/var/dir'
      }
    }
    allow(Simp::Cli::Utils).to receive(:puppet_info).with(@env).and_return(puppet_info)

    @manager = Simp::Cli::Passgen::PasswordManager.new(@env, nil, nil)

    # backend and folder are independent options, but can be tested at the same time to
    # no ill effect
    @backend = 'backend3'
    @folder = 'app1'
    @manager_custom = Simp::Cli::Passgen::PasswordManager.new(@env, @backend, @folder)

    @simple_name = 'name1'
    @complex_name = "#{@folder}/#{@simple_name}"
  end

  #
  # Password Manager API tests
  # Most tests use mocked behavior for the `puppet apply` operations.  Those operations
  # must be tested with an acceptance test.
  #
  describe 'location' do
    it 'returns string with only environment when no backend or folder are specified' do
      expect( @manager.location ).to eq("'#{@env}' Environment")
    end

    it 'returns string with environment and backend when folder is not specified' do
      manager = Simp::Cli::Passgen::PasswordManager.new(@env, @backend, nil)
      expect( manager.location ).to eq("'#{@env}' Environment, '#{@backend}' libkv Backend")
    end

    it 'returns string with environment and folder when backend is not specified' do
      manager = Simp::Cli::Passgen::PasswordManager.new(@env, nil, @folder)
      expect( manager.location ).to eq("'#{@env}' Environment, '#{@folder}' Folder")
    end

    it 'returns string with environment, backend, and folder when all specified' do
      manager = Simp::Cli::Passgen::PasswordManager.new(@env, @backend, @folder)
      expected = "'#{@env}' Environment, '#{@folder}' Folder, '#{@backend}' libkv Backend"
      expect( manager.location ).to eq(expected)
    end
  end

#FIXME
  describe '#name_list' do
    it 'returns empty array when no names exist' do
    end

    it 'returns list of available names for the top folder of the specified env' do
      
      #expect( @manager.name_list ).to eq(expected)
    end

    it 'returns list of available names for the <env, folder, backend>' do
    end

    it 'fails when puppet apply with list operation fails' do
=begin
      expect { @manager.name_list }.to raise_error(
        Simp::Cli::ProcessingError,
        'List failed: Permission denied - failed chdir')
=end
    end

  end

#FIXME
  describe '#password_info' do

    it 'returns hash with info for name in the top folder of the specified env' do
=begin
      expected = {
        'value'    => {
          'password' => 'production_name3_password',
          'salt'     => 'salt for production_name3'
        },
          'metadata' => {
          'history' => [
            ['production_name3_backup_password', 'salt for production_name3 backup' ]
          ]
        }
      }

      expect( @manager.password_info('production_name3') ).to eq(expected)
=end
    end

    it 'returns hash with info for name in <env, folder, backend> ' do
    end

    it 'fails when non-existent name specified' do
=begin
      expect { @manager.password_info('oops') }.to raise_error(
        Simp::Cli::ProcessingError,
        "'oops' password not present")
=end
    end

    it 'fails when puppet apply with get operation fails' do
=begin
=end
    end

  end

#FIXME
  describe '#remove_password' do

    it 'removes password for name in the specified env' do
=begin
      @manager.remove_password('production_name1')
=end
    end

    it 'removes password for name in <env, folder, backend>' do
    end

    it 'fails when no password for the name exists' do
=begin
      expect { @manager.remove_password('oops') }.to raise_error(
        Simp::Cli::ProcessingError,
        "'oops' password not found")
=end
    end

    it 'fails when puppet apply with remove operation fails' do
    end

  end

#FIXME
  describe '#set_password' do

    let(:options) do
      {
        :auto_gen             => false,
        :validate             => false,
        :default_length       => 32,
        :minimum_length       => 8,
        :default_complexity   => 0,
        :default_complex_only => false
      }
    end

    it 'updates password and returns new password for name in the specified env' do
=begin
      # bypass password input
      allow(@manager).to receive(:get_new_password).and_return(
        ['first_new_password', false], ['second_new_password', false])

      expect( @manager.set_password('production_name1', options) ).to eq('first_new_password')
      expect( @manager.set_password('production_name2', options) ).to eq('second_new_password')
=end
    end

    it 'updates password and returns new password for name in <env, folder, backend>' do
    end

    it 'updates password file, and backs up old files, and returns new password for name in the specified password dir' do
    end

    it 'creates and sets a new password with same length as old password when auto_gen=true' do
      new_options = options.dup
      new_options[:auto_gen] = true
=begin
      new_password = @manager.set_password('production_name1', new_options)
      expect(new_password.length).to eq('production_name1_password'.length)
=end
    end

    it 'creates password file for new name' do
=begin
      allow(@manager).to receive(:get_new_password).and_return(['new_password',false])

      expect( @manager.set_password('new_name', options) ).to eq('new_password')
=end
    end

    it 'fails when options is missing a required key' do
      bad_options = {
        :validate             => false,
        :default_length       => 32,
        :minimum_length       => 8,
        :default_complexity   => 0,
        :default_complex_only => false
      }
      expect { @manager.set_password('name1', bad_options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'Missing :auto_gen option')
    end

    it 'fails if puppet apply to get previous password fails' do
    end

    it 'fails if get_new_password fails' do
=begin
      allow(@manager).to receive(:get_new_password).and_raise(
        Simp::Cli::ProcessingError, 'FATAL: Too many failed attempts to enter password')

      expect { @manager.set_password('new_name', options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'Set failed: FATAL: Too many failed attempts to enter password')
=end
    end

    it 'fails if puppet apply to set password fails' do
    end

  end


  #
  # Helper tests.  Since most helper methods are tested in Password
  # Manager API tests, only use cases not otherwise tested are exercised here.
  #
  describe '#current_password_info' do
    let(:password_info) { {
      'value'    => { 'password' => 'password1', 'salt' => 'salt' },
      'metadata' => { 'history'  => [] }
    } }

    it 'applies manifest to retrieve password info and then returns it' do
      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_return({}) # don't care about return

      allow(Simp::Cli::Passgen::Utils).to receive(:load_yaml)
        .and_return(password_info)

      expect( @manager.current_password_info(@simple_name) )
        .to eq(password_info)
    end

    it 'applies manifest with folder and backend to retrieve password info and then returns it' do
      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_return({}) # don't care about return

      allow(Simp::Cli::Passgen::Utils).to receive(:load_yaml)
        .and_return(password_info)

      expect( @manager_custom.current_password_info(@complex_name) )
        .to eq(password_info)
    end

    it 'fails when manifest apply fails' do
      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_raise(Simp::Cli::ProcessingError, 'Password retrieve failed')

      expect{ @manager_custom.current_password_info(@complex_name) }
        .to raise_error(Simp::Cli::ProcessingError, 'Password retrieve failed')
    end

    it 'fails when interim password info YAML fails to load' do
      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_return({}) # don't care about return

      allow(Simp::Cli::Passgen::Utils).to receive(:load_yaml).and_raise(
        Simp::Cli::ProcessingError, 'Failed to load password info YAML')

      expect{ @manager_custom.current_password_info(@complex_name) }
        .to raise_error(Simp::Cli::ProcessingError,
        'Failed to load password info YAML')
    end
  end

  describe '#generate_and_set_password' do
    let(:options) do
      {
        :length       => 32,
        :complexity   => 0,
        :complex_only => false
      }
    end

    let(:generated_password) { 'new generated password' }

    it 'applies manifest to generate and set <password,salt> and then returns generated password' do
      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_return({}) # don't care about return

      allow(File).to receive(:read).with(/password.txt$/).and_return(generated_password)

      expect( @manager.generate_and_set_password(@simple_name, options) )
        .to eq(generated_password)
    end

    it 'applies manifest with folder and backend to generate and set <password,salt> and then returns generated password' do
      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_return({}) # don't care about return

      allow(File).to receive(:read).with(/password.txt$/).and_return(generated_password)

      expect( @manager_custom.generate_and_set_password(@complex_name, options) )
        .to eq(generated_password)
    end

    it 'fails when manifest apply fails' do
      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_raise(Simp::Cli::ProcessingError, "Password generate and set failed")

      expect{ @manager.generate_and_set_password(@simple_name, options) }
        .to raise_error(
        Simp::Cli::ProcessingError, "Password generate and set failed")
    end

    it 'fails when interim password file cannot be read' do
      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_return({}) # don't care about return

      allow(File).to receive(:read).with(/password.txt$/).and_raise(
         Errno::EACCES, 'password file read failed')

      expect{ @manager.generate_and_set_password(@simple_name, options) }
        .to raise_error(
        Simp::Cli::ProcessingError,
        'Failed to read generated password: Permission denied - password file read failed')
    end
  end

  describe '#get_and_set_password' do
    let(:options) do
      {
        :length       => 32,
        :complexity   => 0,
        :complex_only => false,
        :validate     => false
      }
    end

    let(:user_input_password) { 'new password from user' }

    it 'gets password from user, applies manifest to generate salt and set pair, and then returns password' do
      allow(Simp::Cli::Passgen::Utils).to receive(:get_password)
        .and_return(user_input_password)

      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_return({}) # don't care about return

      expect( @manager.get_and_set_password(@simple_name, options) )
        .to eq(user_input_password)
    end

    it 'gets password from user, applies manifest with folder and backend to generate salt and set pair, and then returns password' do
      allow(Simp::Cli::Passgen::Utils).to receive(:get_password)
        .and_return(user_input_password)

      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_return({}) # don't care about return

      expect( @manager_custom.get_and_set_password(@complex_name, options) )
        .to eq(user_input_password)
    end

    it 'fails if user password input fails' do
      allow(Simp::Cli::Passgen::Utils).to receive(:get_password)
        .and_raise(Simp::Cli::ProcessingError,
        'FATAL: Too many failed attempts to enter password')

      expect{ @manager.get_and_set_password(@simple_name, options) }
        .to raise_error(
        Simp::Cli::ProcessingError,
        'FATAL: Too many failed attempts to enter password')
    end

    it 'fails when manifest apply fails' do
      allow(Simp::Cli::Passgen::Utils).to receive(:get_password)
        .and_return(user_input_password)

      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_raise(Simp::Cli::ProcessingError, "Password set failed")

      expect{ @manager.get_and_set_password(@simple_name, options) }
        .to raise_error(
        Simp::Cli::ProcessingError, "Password set failed")
    end
  end

  describe '#merge_password_options' do

    let(:fullname) { 'name1' }
    let(:options) do
      {
        :default_length       => 32,
        :minimum_length       => 8,
        :default_complexity   => 0,
        :default_complex_only => false,
      }
    end

    context ':length option' do
      context 'input :length option unset' do
        it 'returns options with :length=:default_length when password does not exist' do
          allow(@manager).to receive(:current_password_info).with(fullname)
            .and_return({})

          merged_options = @manager.merge_password_options(fullname, options)
          expect( merged_options[:length] ).to eq(options[:default_length])
        end

        it 'returns options with :length=existing valid password length' do
          allow(@manager).to receive(:current_password_info).with(fullname)
            .and_return({ 'value' => { 'password' => '12345678'} })

          merged_options = @manager.merge_password_options(fullname, options)
          expect( merged_options[:length] ).to eq(8)
        end

        it 'returns options with :length=:default_length when existing password length is too short' do
          allow(@manager).to receive(:current_password_info).with(fullname)
            .and_return({ 'value' => { 'password' => '1234567'} })

          merged_options = @manager.merge_password_options(fullname, options)
          expect( merged_options[:length] ).to eq(options[:default_length])
        end
      end

      context 'input :length option set' do
        it 'returns options with input :length when it exists and is valid' do
          allow(@manager).to receive(:current_password_info).with(fullname)
              .and_return({ 'value' => { 'password' => '1234568'} })

          new_options = options.dup
          new_options[:length] = 48
          merged_options = @manager.merge_password_options(fullname, new_options)
          expect( merged_options[:length] ).to eq(new_options[:length])
        end

        it 'returns options with :length=:default_length when input options :length is too short' do
          allow(@manager).to receive(:current_password_info).with(fullname)
              .and_return({ 'value' => { 'password' => '1234568'} })

          new_options = options.dup
          new_options[:length] = 6
          merged_options = @manager.merge_password_options(fullname, new_options)
          expect( merged_options[:length] ).to eq(new_options[:default_length])
        end
      end
    end

    context ':complexity option' do
      context 'input :complexity option unset' do
        it 'returns options with :complexity=:default_complexity when password does not exist' do
          allow(@manager).to receive(:current_password_info).with(fullname)
            .and_return({})

          merged_options = @manager.merge_password_options(fullname, options)
          expect( merged_options[:complexity] ).to eq(options[:default_complexity])
        end

        it 'returns options with :complexity=:default_complexity when password exists but does not have complexity stored' do
          allow(@manager).to receive(:current_password_info).with(fullname)
            .and_return({ 'value' => { 'password' => '1234568'} })

          merged_options = @manager.merge_password_options(fullname, options)
          expect( merged_options[:complexity] ).to eq(options[:default_complexity])
        end

        it 'returns options with :complexity=existing password complexity' do
          allow(@manager).to receive(:current_password_info).with(fullname)
            .and_return(
            { 'value' => { 'password' => '1234568'},
              'metadata' => { 'complexity' => 2 }
            })

          merged_options = @manager.merge_password_options(fullname, options)
          expect( merged_options[:complexity] ).to eq(2)
        end
      end

      context 'input :complexity option set' do
        it 'returns options with input :complexity when it exists' do
          allow(@manager).to receive(:current_password_info).with(fullname)
            .and_return(
            { 'value' => { 'password' => '1234568'},
              'metadata' => { 'complexity' => 2 }
            })

          new_options = options.dup
          new_options[:complexity] = 1
          merged_options = @manager.merge_password_options(fullname, new_options)
          expect( merged_options[:complexity] ).to eq(new_options[:complexity])
        end
      end
    end

    context ':complex_only option' do
      context 'input :complex_only option unset' do
        it 'returns options with :complex_only=:default_complex_only when password does not exist' do
          allow(@manager).to receive(:current_password_info).with(fullname)
            .and_return({})
          merged_options = @manager.merge_password_options(fullname, options)
          expect( merged_options[:complex_only] ).to eq(options[:default_complex_only])
        end

        it 'returns options with :complex_only=:default_complex_only when password exists but does not have complex_only stored' do
          allow(@manager).to receive(:current_password_info).with(fullname)
            .and_return(
            { 'value' => { 'password' => '1234568'},
            })

          merged_options = @manager.merge_password_options(fullname, options)
          expect( merged_options[:complex_only] ).to eq(options[:default_complex_only])
        end

        it 'returns options with :complex_only=existing password complex_only' do
          allow(@manager).to receive(:current_password_info).with(fullname)
            .and_return(
            { 'value' => { 'password' => '1234568'},
              'metadata' => { 'complex_only' => true }
            })

          merged_options = @manager.merge_password_options(fullname, options)
          expect( merged_options[:complex_only] ).to be true
        end
      end

      context 'input :complex_only option set' do
        it 'returns options with input :complex_only when it exists' do
          allow(@manager).to receive(:current_password_info).with(fullname)
            .and_return(
            { 'value' => { 'password' => '1234568'},
              'metadata' => { 'complex_only' => false }
            })

          new_options = options.dup
          new_options[:complex_only] = true
          merged_options = @manager.merge_password_options(fullname, new_options)
          expect( merged_options[:complex_only] ).to eq(new_options[:complex_only])
        end
      end
    end

    context 'errors' do
      it 'fails if it puppet apply to get current password fails' do
        allow(@manager).to receive(:current_password_info).with(fullname)
          .and_raise(Simp::Cli::ProcessingError, 'Password retrieve failed')

        expect { @manager.merge_password_options(fullname, options) }.to \
          raise_error(Simp::Cli::ProcessingError, 'Password retrieve failed')
      end
    end
  end

  describe '#password_list' do
    let(:password_list) { {
      'keys' => {
        'name1' => {
          'value'    => { 'password' => 'password1', 'salt' => 'salt1'},
          'metadata' => {
            'complex'      => 1,
            'complex_only' => false,
            'history'      => [
              ['password1_old', 'salt1_old'],
              ['password1_old_old', 'salt1_old_old']
            ]
          }
        },
        'name2' => {
          'value' => { 'password' => 'password2', 'salt' => 'salt2'},
          'metadata' => {
            'complex'      => 1,
            'complex_only' => false,
            'history'      => []
          }
        }
      }
    } }

    it 'applies manifest to retrieve password list and then returns it' do
      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_return({}) # don't care about return

      allow(Simp::Cli::Passgen::Utils).to receive(:load_yaml)
        .and_return(password_list)

      expect( @manager.password_list ).to eq(password_list)
    end

    it 'fails when manifest apply fails' do
      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_raise(Simp::Cli::ProcessingError, 'Password list retrieve failed')

      expect{ @manager_custom.password_list }.to raise_error(
        Simp::Cli::ProcessingError, 'Password list retrieve failed')
    end

    it 'fails when interim password list YAML fails to load' do
      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_return({}) # don't care about return

      allow(Simp::Cli::Passgen::Utils).to receive(:load_yaml).and_raise(
        Simp::Cli::ProcessingError, 'Failed to load password list YAML')

      expect{ @manager_custom.password_list }.to raise_error(
        Simp::Cli::ProcessingError, 'Failed to load password list YAML')
    end

    it 'fails when retrieved password list is missing required keys' do
      allow(Simp::Cli::Passgen::Utils).to receive(:apply_manifest)
        .and_return({}) # don't care about return

      invalid_password_list = { 'oops' => {} }
      allow(Simp::Cli::Passgen::Utils).to receive(:load_yaml)
        .and_return(invalid_password_list)

      expect{ @manager_custom.password_list }.to raise_error(
        Simp::Cli::ProcessingError,
        "Invalid result returned from simplib::passgen::list:\n\n#{invalid_password_list}")
    end
  end

  describe '#valid_password_list?' do
    it 'returns true if list hash is empty' do
      expect( @manager.valid_password_list?({}) ).to be true
    end

    it "returns true if list hash has required 'keys' key with an empty sub-hash" do
      list = { 'keys' => {} }
      expect( @manager.valid_password_list?(list) ).to be true
    end

    it "returns true if list hash has required 'keys' key with a valid sub-hash" do
      password_info = {
        'value'    => { 'password' => 'password1' },
        'metadata' => { 'history'  => [] }
      }

      list = { 'keys' => { 'name1' => password_info } }
      expect( @manager.valid_password_list?(list) ).to be true
    end

    it "returns false if list hash is missing required 'keys' key" do
      list = { 'folders' => [ 'app1', 'app2' ] }
      expect( @manager.valid_password_list?(list) ).to be false
    end

    it "returns false if list hash and invalid entry in the 'keys' sub-hash" do
      list = { 'keys' => { 'name1' => {} } }
      expect( @manager.valid_password_list?(list) ).to be false
    end
  end

  describe '#valid_password_info?' do
    it 'returns true if password info hash has required keys' do
      password_info = {
        'value'    => { 'password' => 'password1' },
        'metadata' => { 'history'  => [] }
      }

      expect( @manager.valid_password_info?(password_info) ).to be true
    end

    it "returns false if password info hash is missing 'value' key" do
      password_info = {
        'metadata' => { 'history' => [] }
      }

      expect( @manager.valid_password_info?(password_info) ).to be false
    end

    it "returns false if password info hash is missing 'password' sub-key of 'value'" do
      password_info = {
        'value'    => { 'salt'    => 'salt1' },
        'metadata' => { 'history' => [] }
      }

      expect( @manager.valid_password_info?(password_info) ).to be false
    end

    it "returns false if 'password' sub-key of 'value' is not a String" do
      password_info = {
        'value'    => { 'password' => ['password1'] },
        'metadata' => { 'history'  => [] }
      }

      expect( @manager.valid_password_info?(password_info) ).to be false
    end

    it "returns false if password info hash is missing 'metadata' key" do
      password_info = {
        'value'    => { 'password' => 'password1' }
      }

      expect( @manager.valid_password_info?(password_info) ).to be false
    end

    it "returns false if password info hash is missing 'history' sub-key of 'metadata'" do
      password_info = {
        'value'    => { 'password'   => 'password1' },
        'metadata' => { 'complexity' => 0 }
      }

      expect( @manager.valid_password_info?(password_info) ).to be false
    end

    it "returns false if 'history' sub-key of 'metadata' is not an Array" do
      password_info = {
        'value'    => { 'password' => 'password1' },
        'metadata' => { 'history' => { 'password' => 'old_password1' } }
      }

      expect( @manager.valid_password_info?(password_info) ).to be false
    end

  end

  describe '#validate_set_config' do
    it 'fails when :auto_gen option missing' do
      bad_options = {
        :validate             => false,
        :default_length       => 32,
        :minimum_length       => 8,
        :default_complexity   => 0,
        :default_complex_only => false
      }

      expect { @manager.validate_set_config(bad_options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'Missing :auto_gen option')
    end

    it 'fails when :validate option missing' do
      bad_options = {
        :auto_gen             => false,
        :default_length       => 32,
        :default_complexity   => 0,
        :default_complex_only => false,
        :minimum_length       => 8
      }

      expect { @manager.validate_set_config(bad_options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'Missing :validate option')
    end

    it 'fails when :default_length option missing' do
      bad_options = {
        :auto_gen             => false,
        :validate             => false,
        :minimum_length       => 8,
        :default_complexity   => 0,
        :default_complex_only => false
      }

      expect { @manager.validate_set_config(bad_options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'Missing :default_length option')
    end

    it 'fails when :minimum_length option missing' do
      bad_options = {
        :auto_gen             => false,
        :validate             => false,
        :default_length       => 32,
        :default_complexity   => 0,
        :default_complex_only => false
      }

      expect { @manager.validate_set_config(bad_options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'Missing :minimum_length option')
    end

    it 'fails when :default_complexity option missing' do
      bad_options = {
        :auto_gen             => false,
        :validate             => false,
        :minimum_length       => 8,
        :default_length       => 32,
        :default_complex_only => false
      }

      expect { @manager.validate_set_config(bad_options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'Missing :default_complexity option')
    end

    it 'fails when :default_complex_only option missing' do
      bad_options = {
        :auto_gen           => false,
        :validate           => false,
        :minimum_length     => 8,
        :default_length     => 32,
        :default_complexity => 0,
      }

      expect { @manager.validate_set_config(bad_options) }.to raise_error(
        Simp::Cli::ProcessingError,
        'Missing :default_complex_only option')
    end
  end
end
