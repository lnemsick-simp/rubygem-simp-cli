require 'highline/import'
require 'simp/cli/exec_utils'
require 'simp/cli/passgen/utils'
#require 'simp/cli/utils'
require 'tmpdir'

class Simp::Cli::Passgen::PasswordManager

  def initialize(environment, backend, folder)
    @environment = environment
    @backend = backend
    @folder = folder
    @puppet_info = Simp::Cli::Utils.puppet_info(@environment)

    @location = "#{@environment} Environment"
    @location += " in #{@backend} backend" unless @backend.nil?
    @custom_options = @backend.nil? ? nil : "{ 'backend' => '#{@backend}' }"

    @list = nil
  end

  #####################################################
  # Operations
  #####################################################

  # Remove a list of passwords
  #
  # Removes the listed passwords in the key/value store.
  #
  # @param names Array of names(keys) of passwords to remove
  # @param force_remove Whether to remove password files without prompting
  #   the user to verify the removal operation
  #
  def remove_passwords(names, force_remove=false)
    return if names.empty?

    errors = []
    names.sort.each do |name|
      remove = force_remove
      unless remove
        prompt = "Are you sure you want to remove all entries for '#{name}'?".bold
        remove = Simp::Cli::Passgen::Utils::yes_or_no(prompt, false)
      end

      fullname = @folder.nil? ? name : "#{@folder}/#{name}"
      if remove
        args = "'#{fullname}'"
        args += ", #{@custom_options}" if @custom_options
        manifest = <<-EOM
          if empty(simplib::passgen::get(#{args})) {
            fail('password not found')
          } else {
            simplib::passgen::remove(#{args})
          }
        EOM
        result = apply_manifest(manifest, 'remove')
        if result[:status]
          puts "Deleted #{fullname} in the #{@location}"
        else
          errors << "'#{fullname}': #{extract_manifest_error(result[:stderr])}"
        end
      else
        puts "Skipping #{fullname}"
      end
    end

    unless errors.empty?
      err_msg = "Failed to delete the following password keys in the #{@location}:\n  #{errors.join("\n  ")}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

  # Set a list of passwords to values selected by the user
  #
  #
  # @param names Array of names of passwords to set
  # @param options Hash of password generation options.
  #   * Required keys:
  #     * :auto_gen - whether to auto-generate new passwords
  #     * :force_value - whether to accept passwords entered by user without
  #       validation
  #     * :default_length - default password length of auto-generated passwords.
  #     * :minimum_length - minimum password length
  #
  #   * Optional keys:
  #     * :length - requested length of auto-generated passwords.
  #       * When nil, the password exists, and the existing password length
  #         >='minimum_length', use the length of the existing password
  #       * When nil, the password exists, and the existing password length
  #         < 'minimum_length', use the 'default_length'
  #       * When nil and the password does not exist, use 'default_length'
  #
  def set_passwords(names, options)
    validate_set_config(names, options)

    errors = []
    names.sort.each do |name|
      next if name.strip.empty?

      fullname = @folder.nil? ? name : "#{@folder}/#{name}"
      puts "Processing Name '#{fullname}' in the #{@location}"
      begin
        password_options = merge_password_options(fullname, options)
        password = nil
        if options[:auto_gen]
          password = generate_and_set_password(fullname, password_options)
        else
          password = get_and_set_password(fullname, password_options)
        end

        puts "  Password set to '#{password}'"

     # Will report all problems at end.
      rescue Exception => err
        errors << "'#{name}': #{err.message}"
      end

    end

    unless errors.empty?
      err_msg = "Failed to set #{errors.length} out of #{names.length} passwords:\n  #{errors.join("\n  ")}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

  # Prints the list of password names for the environment to the console
  def show_name_list
    if password_list.key?('keys')
      title = nil
      if @folder
        title = "#{@folder}/ #{@location} Names"
      else
        title = "#{@location} Names"
      end

      puts "#{title}:\n  #{password_list['keys'].keys.sort.join("\n  ")}"
    else
      if @folder
        puts "No passwords found in #{@folder}/ in the #{@location}"
      else
        puts "No passwords found in the #{@location}"
      end
    end

    puts
  end

  # Prints password info for the environment to the console.
  #
  # For each password name, prints its current value, and when present, its
  # previous value.
  #
  # TODO:  Print out all other available information.
  #
  def show_passwords(names)
    return if names.empty?

    # Load in available password info
# FIXME Do we really want to do this if it is not needed?
#  For large number of passwords, this may be expensive.  Need to figure
#  out what is more expensive...applying manifest for each name or applying
#  manifest once for all.  See remove_passwords for example of applying individual
#  manifests that fail if a name does not exist.
#
    list = password_list

    title = nil
    if @folder
      title = "#{@folder}/ #{@location} Passwords"
    else
      title = "#{@location} Passwords"
    end

    puts title
    puts '='*title.length
    errors = []
    names.each do |name|
      puts "Name: #{name}"
      if list['keys'].key?(name)
        info = list['keys'][name]
        puts "  Current:  #{info['value']['password']}"
        unless info['metadata']['history'].empty?
          puts "  Previous: #{info['metadata']['history'][0][0]}"
        end
      else
        puts '  UNKNOWN'
        errors << name
      end
      puts
    end

    unless errors.empty?
      err_msg = "Failed to fetch password info for the following:\n  #{errors.join("\n  ")}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

  #####################################################
  # Helpers
  #####################################################

  # @param manifest Contents of the manifest to be applied
  # @param name Basename of the manifest file
  # @param fail_on_error Whether to raise upon manifest failure.
  #
  # @raise if manifest apply fails and fail_on_error is true
  #
  def apply_manifest(manifest, name = 'passgen', fail_on_error = false)
    result = {}
    cmd = nil
    Dir.mktmpdir( File.basename( __FILE__ ) ) do |dir|
      manifest_file = File.join(dir, "#{name}.pp")
      File.open(manifest_file, 'w') { |file| file.puts manifest }
      puppet_apply = [
        'puppet apply',
        '--color=false',
        "--environment=#{@environment}",
        # this is required for finding the correct vardir when either legacy
        # password files or files from the auto-default key/value store are
        # being processed
        "--vardir=#{@puppet_info[:config]['vardir']}",
        manifest_file
      ].join(' ')

      # umask and sg only needed for operations that modify/remove files
      # (i.e., legacy passgen and libkv-enabled passgen using the file plugin)
      # FIXME: Need to figure out how to handle 'group' when the manifest apply
      #        is not run as root
      cmd = "umask 0027 && sg #{@puppet_info[:config]['group']} -c '#{puppet_apply}'"
      result = Simp::Cli::ExecUtils.run_command(cmd)
      result[:cmd] = cmd
    end

    if !result[:status] && fail_on_error
      err_msg = [
        "#{cmd} failed:",
        '-'*20,
        manifest,
        '-'*20,
        result[:stderr]
      ].join("\n")
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    result
  end

  def current_password_info(fullname)
    args = "'#{fullname}'"
    args += ", #{@custom_options}" if @custom_options
    manifest = "notice(to_yaml(simplib::passgen::get(#{args})))"
    result = apply_manifest(manifest, 'get_current', true)
    extract_yaml_from_log(result[:stdout])
  end

#Error: Evaluation Error: Error while evaluating a Function Call, 'liztest' password not found (file: /root/remove.pp, line: 4, column: 3) on node puppet.simp.test
#Error: Evaluation Error: Error while evaluating a Function Call, libkv Configuration Error for libkv::put with key='key': No libkv backend 'oops' with 'id' and 'type' attributes has been configured: {"backends"=>{"default"=>{"type"=>"file", "id"=>"default"}}, "backend"=>"oops", "softfail"=>false, "environment"=>"production"} (file: /root/tmp.pp, line: 1, column: 1) on node puppet.simp.test
#
  def extract_manifest_error(errlog)
    err_lines = errlog.split("\n").delete_if { |line| !line.start_with?('Error: ') }

    # Expecting only 1 'Function Call' error from a fail() or a simplib::passgen::xxx call
    # FIXME This is fragile... use PAL for puppet manifest operations instead
    err_msg = nil

    if err_lines.empty?
     err_msg = 'Unknown error'
    else
      match = err_lines[0].match(/.*?Function Call, (.*?) \(file: .*?, line: .*/)
      if match
        err_msg = match[1]
      else
        err_msg = err_lines[0]
      end
    end

    err_msg
  end

  def extract_yaml_from_log(log)
    # get rid of initial Notice text
    yaml_string = log.gsub(/^.*?\-\-\-/m,'---')

    # get rid of trailing Notice text
    yaml_lines = yaml_string.split("\n").delete_if { |line| line =~ /^Notice:/ }
    yaml_string = yaml_lines.join("\n")
    begin
      yaml = YAML.load(yaml_string)
      return yaml
    rescue Exception =>e
      err_msg = "Failed to extract YAML: #{e}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

  def generate_and_set_password(fullname, options)
    manifest =<<-EOM
      [ $password, $salt ] = simplib::passgen::gen_password_and_salt(
        #{options[:length]},
        #{options[:complexity]},
        #{options[:complex_only]},
        30) # generate timeout seconds

      $password_options = {
      'complexity'   => #{options[:complexity]},
      'complex_only' => #{options[:complex_only]},
      'user'         => '#{@puppet_info[:config]['user']}'
      }

     simplib::passgen::set('#{fullname}', $password, $salt, $password_options)
     $for_log = { 'password' => $password }
     notice(to_yaml($for_log))
    EOM
    result = apply_manifest(manifest, 'get_current', true)
    extract_yaml_from_log(result[:stdout])['password']
  end

  # get a password from user and then generate a salt for it
  # and set both the password and salt
  def get_and_set_password(fullname, options)
    password = Simp::Cli::Passgen::Utils::get_password(5, !options[:force_value])
    # NOTES:
    # - 'complexity' and 'complex_only' are required in libkv mode, and ignored
    #   in legacy mode
    # - 'user' is used in legacy mode to make sure generated password files are
    #   owned by the required user, is required when this code is run as root,
    #   and is ignored in libkv mode
    #   - Legacy passgen directories/files are owned by the user compiling
    #     the manifest (puppet:puppet for the puppetserver) and have 750 and 640
    #     permissions, respectively.
    #   - Legacy passgen code has a sanity check that fails if any of its
    #     directories/files are not owned by the user:group compiling the manifest.
    #   - libkv's file plugin directories/files are owned by the user compiling
    #     the manifest (puppet:puppet for the puppetserver) with 770 and
    #     660 permissions, respectively ==> root can create directories/files
    #     with puppet applies within 'sg puppet'.
    # - Odd looking escape of single quotes below is required because
    #   \' is a back reference in gsub.
    # FIXME: Need to figure out how to handle 'user' when the manifest apply
    #        is not run as root
    manifest = <<-EOM
      $salt = simplib::passgen::gen_salt(30)  # 30 second generate timeout
      $password_options = {
      'complexity'   => #{options[:complexity]},
      'complex_only' => #{options[:complex_only]},
      'user'         => '#{@puppet_info[:config]['user']}'
      }

      simplib::passgen::set('#{fullname}', '#{password.gsub("'", "\\\\'")}',
        $salt, $password_options)
    EOM

    apply_manifest(manifest, name = 'set_user_password', true)
    password
  end

  def merge_password_options(fullname, options)
    password_options = options.dup
    current = current_password_info(fullname)

    if options[:length].nil?
      if current.key?('value')
        password_options[:length] = current['value']['password'].length
      else
        password_options[:length] = options[:default_length]
      end
    end

    if options[:complexity].nil?
      if ( current.key?('metadata') && current['metadata'].key?('complexity') )
        password_options[:complexity] = current['metadata']['complexity']
      else
        password_options[:complexity] = options[:default_complexity]
      end
    end

    if options[:complex_only].nil?
      if ( current.key?('metadata') && current['metadata'].key?('complex_only') )
        password_options[:complex_only] = current['metadata']['complex_only']
      else
        password_options[:complex_only] = options[:default_complex_only]
      end
    end

    if password_options[:length] < options[:minimum_length]
      password_options[:length] = options[:default_length]
    end

    password_options
  end


  # Retrieve and validate a list of a password folder
  #
  # @raise if manifest apply to retrieve the list fails, the manifest result
  #   cannot be parsed as YAML, or the result does not have the required keys
  def password_list
    return @password_list unless @password_list.nil?

    args = ''
    folder = @folder.nil? ? '/' : @folder
    if @custom_options
      args = "'#{folder}', #{@custom_options}"
    else
      args = "'#{folder}'"
    end

    # simplib::passgen::list only fails with real problems, so be sure to
    # raise if it fails!
    manifest = "notice(to_yaml(simplib::passgen::list(#{args})))"
    result = apply_manifest(manifest, 'list', true)
    list = extract_yaml_from_log(result[:stdout])

    # make sure results are something we can process...should only have a problem
    # if simplib::passgen::list changes and this software was not updated
    unless valid_password_list?(list)
      err_msg = "Invalid result returned from simplib::passgen::list:\n\n#{list}"
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    @password_list = list
  end

  def valid_password_list?(list)
    valid = true
    unless list.empty?
      if list.key?('keys')
        list['keys'].each do |name, info|
          unless (
              info.key?('value') && info['value'].key?('password') &&
              info.key?('metadata') && info['metadata'].key?('history') )
            valid = false
            break
          end
        end
      else
        valid = false
      end
    end

    valid
  end

  def validate_set_config(names, options)
    unless options.key?(:auto_gen)
      err_msg = 'Missing :auto_gen option'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    unless options.key?(:force_value)
      err_msg = 'Missing :force_value option'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    unless options.key?(:default_length)
      err_msg = 'Missing :default_length option'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    unless options.key?(:minimum_length)
      err_msg = 'Missing :minimum_length option'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    unless options.key?(:default_complexity)
      err_msg = 'Missing :default_complexity option'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end

    unless options.key?(:default_complex_only)
      err_msg = 'Missing :default_complex_only option'
      raise Simp::Cli::ProcessingError.new(err_msg)
    end
  end

end
