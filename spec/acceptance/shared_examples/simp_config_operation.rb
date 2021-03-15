require 'yaml'
shared_examples 'simp config operation' do |host,options|

 opts = {
  :description           => '',

  # Puppet environment
  :puppet_env            => 'production',

  :scenario              => 'simp',

  # `simp config` command line options/args to add to default_config_opts
  :config_opts_to_add    => [],

  # `simp config` command line options/args to remove from default_config_opts
  :config_opts_to_remove => [],

  # environment variables to set when running simp config
  :env_vars              => [],

  # Interface to configure for puppetserver communication
  :interface             => 'eth1'
 }.merge(options)

  let(:grub_pwd_hash) {
    'grub.pbkdf2.sha512.10000.DE78658C8482E4F3752B61942622345CB22BF23FECDDDCA41D9891FF7569376D3177D11945AF344267B04B44227475BDD520367D5A492EEADCBAB6AA76718AFA.2B08D03310E1514F517A59D9F1B174C73DC15B9C02010F88DC6E6FC8C869D16B9B38E9004CB6382AFE3A68BFC29E14B49C48360ED829D6EDC25E05F5609069F8'
  }

  let(:ldap_rootpw_hash) { "{SSHA}oIQoj6htrx7TnXwhTOY57ThnklOJkD8m" }
  let(:priv_user_pwd_hash) {
    '$6$l69r7t36$WZxDVhvdMZeuL0vRvOrSLMKWxxQbuK1j8t0vaEq3BW913hjOJhRNTxqlKzDflPW7ULPwkBa6xdfcca2BlGoq/.'
  }

  let(:default_config_opts) {
    config = [
      # `simp config` command line options

      # Force defaults if not otherwised specified and do not allow queries.
      # This means `simp config` will fail if it encounters any unspecified
      # item that was not preassigned and could not be set by a default.
      '-f -D',

      # Subsequent <key=value> command line parameters preassign item values
      # (just like an answers file). Some are for items that don't have
      # defaults and some are for items for which we don't want to use their
      # defaults.

      'cli::network::set_up_nic=false', # Do NOT mess with the network!
      "cli::network::interface=#{opts[:interface]}",

      # Set password (hashes) for passwords that must be preassigned when
      # queries are disabled.
      # - All hashes correspond to 'P@ssw0rdP@ssw0rd'
      # - Be sure to put <key=value> in single quotes to prevent any bash
      #   interpretation.
      "'grub::password=#{grub_pwd_hash}'",
      "'simp_openldap::server::conf::rootpw=#{ldap_rootpw_hash}'",
      "'cli::local_priv_user_password=#{priv_user_pwd_hash}'"
    ]

    config << "simp::cli::scenario=#{opts[:scenario]}" if opts[:scenario] != 'simp'
    config
  }

  let(:config_opts) {
    conf_opts = default_config_opts.dup
    conf_opts += opts[:config_opts_to_add]
    conf_opts -= opts[:config_opts_to_remove]
    conf_opts
  }

  let(:puppet_env_dir) { "/etc/puppetlabs/code/environments/#{opts[:puppet_env]}" }
  let(:secondary_env_dir) { "/var/simp/environments/#{opts[:puppet_env]}" }
  let(:fqdn) { fact_on(host, 'fqdn') }
  let(:domain) { fact_on(host, 'domain') }
  let(:fips) { fips_enabled(host) }
  let(:modules) { on(host, 'ls /usr/share/simp/modules').stdout.split("\n") }

  it "should run `simp config` to configure server for bootstrap #{opts[:description]}" do
    result = on(host, "#{opts[:env_vars].join(' ')} simp config #{config_opts.join(' ')}")
  end

  it "should create the #{opts[:puppet_env]} Puppet environment" do
    expect( directory_exists_on(host, puppet_env_dir) ).to be true
  end

  it 'should create a pair of Puppetfiles configured for SIMP' do
    expect( file_exists_on(host, "#{puppet_env_dir}/Puppetfile") ).to be true
    on(host, "grep 'Puppetfile.simp' #{puppet_env_dir}/Puppetfile | grep ^instance_eval")

    expect( file_exists_on(host, "#{puppet_env_dir}/Puppetfile.simp") ).to be true
    modules.each do |name|
      result = on(host, "grep name /usr/share/simp/modules/#{name}/metadata.json | grep #{name}")
      repo_name = result.stdout.match( /(\w+\-\w*)/ )[1]
      on(host, "grep '/usr/share/simp/git/puppet_modules/#{repo_name}.git' #{puppet_env_dir}/Puppetfile.simp")
    end
  end

  it 'should create a environment.conf with secondary env in modulepath' do
    expect( file_exists_on(host, "#{puppet_env_dir}/environment.conf") ).to be true
    custom_mod_path = 'modulepath = site:modules:/var/simp/environments/production/site_files:$basemodulepath'
    on(host, "grep '#{custom_mod_path}' #{puppet_env_dir}/environment.conf")
  end

  it 'should create a hiera.yaml.conf that matches enviroment-skeleton' do
    expect( file_exists_on(host, "#{puppet_env_dir}/hiera.yaml") ).to be true
    on(host, "diff /usr/share/simp/environment-skeleton/puppet/hiera.yaml #{puppet_env_dir}/hiera.yaml")
  end

  it 'should populate modules dir with modules from local git repos' do
    modules.each do |name|
      expect( directory_exists_on(host, "#{puppet_env_dir}/modules/#{name}") ).to be true
    end
  end

  it 'should create a simp_config_settings.yaml global hiera file' do
    yaml_file = "#{puppet_env_dir}/data/simp_config_settings.yaml"
    expect( file_exists_on(host, yaml_file) ).to be true

    actual = YAML.load( file_contents_on(host, yaml_file) )

    # any value that is 'SKIP' can vary based on virtual host or `simp config` run
    expected = {
      'chrony::servers'                  =>"%{alias('simp_options::ntp::servers')}",

      # FIXME The grub password shouldn't be stored in global hieradata,
      # as it is not used by Puppet, yet. See SIMP-6527 and SIMP-9411.
      'grub::password'                   => grub_pwd_hash,

      'simp::runlevel'                   => 3,
      'simp_options::dns::search'        => [ domain ],

      # Skip this because it is depends upon the host network
      'simp_options::dns::servers'        => 'SKIP',
      'simp_options::fips'                => fips,
      'simp_options::ldap'                => true,
      'simp_options::ldap::base_dn'       => domain.split('.').map { |x| "dc=#{x}" }.join(','),
      'simp_options::ldap::bind_hash'     => 'SKIP',
      'simp_options::ldap::bind_pw'       => 'SKIP',
      'simp_options::ldap::sync_hash'     => 'SKIP',
      'simp_options::ldap::sync_pw'       => 'SKIP',

      # Skip this because it is depends upon existing host ntp config
      'simp_options::ntp::servers'        => 'SKIP',
      'simp_options::puppet::ca'          => fqdn,
      'simp_options::puppet::ca_port'     => 8141,
      'simp_options::puppet::server'      => fqdn,
      'simp_options::syslog::log_servers' => [],

      # Skip this because it is depends upon the host network
      'simp_options::trusted_nets'        => 'SKIP',

      'sssd::domains'                     => [ 'LDAP' ],
      'svckill::mode'                     => 'warning',
      'useradd::securetty'                => [],
      'simp::classes'                     => ['simp::yum::repo::internet_simp']
    }

    expect( actual.keys.sort ).to eq(expected.keys.sort)
    normalized_exp = expected.delete_if { |key,value| value == 'SKIP' }
    normalized_exp.each do |key,value|
      expect( actual[key] ).to eq(value)
    end
  end

  it 'should create a <SIMP server fqdn>.yaml hiera file' do
    yaml_file = "#{puppet_env_dir}/data/hosts/#{fqdn}.yaml"
    actual = YAML.load( file_contents_on(host, yaml_file) )

    # load in template and then merge with adjustments that
    # `simp config` should make
    template = '/usr/share/simp/environment-skeleton/puppet/data/hosts/puppet.your.domain.yaml'
    expected = YAML.load( file_contents_on(host, template) )
    adjustments = {
      'simp::server::allow_simp_user'              => false,
       'puppetdb::master::config::puppetdb_server' => "%{hiera('simp_options::puppet::server')}",
       'puppetdb::master::config::puppetdb_port'   => 8139,
       'simp_openldap::server::conf::rootpw'       => ldap_rootpw_hash,
       'pam::access::users'                        => {
         'simpadmin' => { 'origins' => [ 'ALL' ] }
       },
       'selinux::login_resources'                  => {
         'simpadmin' => { 'seuser' => 'staff_u', 'mls_range' => 's0-s0:c0.c1023' }
       },
       'sudo::user_specifications'                 => {
         'simpadmin_su' => {
           'user_list' => [ 'simpadmin' ],
           'cmnd'      => [ 'ALL' ],
           'passwd'    => true,
           'options'   => { 'role' => 'unconfined_r' }
         }
       },
       'simp::server::classes'                     => [ 'simp::server::ldap', 'simp::puppetdb' ]
    }
    expected.merge!(adjustments)
    expect( actual ).to eq(expected)
  end


  it "should set $simp_scenario to #{opts[:scenario]} in site.pp" do
    site_pp = File.join(puppet_env_dir, 'manifests', 'site.pp')
    expect( file_exists_on(host, site_pp) ).to be true
    actual = file_contents_on(host, site_pp)
    expect( actual ).to match(/^\$simp_scenario\s*=\s*'#{opts[:scenario]}'/)
  end

  it "should create a #{opts[:puppet_env]} secondary environment" do
    expect( directory_exists_on(host, secondary_env_dir) ).to be true
    expect( directory_exists_on(host, "#{secondary_env_dir}/FakeCA") ).to be true
    expect( directory_exists_on(host, "#{secondary_env_dir}/rsync") ).to be true
    expect( directory_exists_on(host, "#{secondary_env_dir}/site_files") ).to be true
  end

  it 'should create cacerts and host cert files in the secondary env' do
    keydist_dir = "#{secondary_env_dir}/site_files/pki_files/files/keydist"
    on(host, "ls #{keydist_dir}/cacerts/cacert_*.pem")
    on(host, "ls #{keydist_dir}/#{fqdn}/#{fqdn}.pem")
    on(host, "ls #{keydist_dir}/#{fqdn}/#{fqdn}.pub")
  end

  it 'should minimally configure Puppet' do
    expected_keylength = fips ? '2048' : '4096'
    expect( on(host, 'puppet config print keylength').stdout.strip ).to eq(expected_keylength)
    expect( on(host, 'puppet config print server').stdout.strip ).to eq(fqdn)
    expect( on(host, 'puppet config print ca_server').stdout.strip ).to eq(fqdn)
    expect( on(host, 'puppet config print ca_port').stdout.strip ).to eq('8141')

    autosign_conf = on(host, 'puppet config print autosign').stdout.strip
    actual = file_contents_on(host, autosign_conf)
    expect( actual ).to match(%r(^#{fqdn}$))
  end

  it 'should create privileged user' do
    on(host, 'grep simpadmin /etc/passwd')
    on(host, 'grep simpadmin /etc/group')
    expect( directory_exists_on(host, '/var/local/simpadmin') ).to be true

  # TODO make sure can login with password?
  # sshd_config PasswordAuthentication yes
  end

  it 'should ensure puppet server entry is in /etc/hosts' do
    actual = file_contents_on(host, '/etc/hosts')
    ip = fact_on(host, "ipaddress_#{opts[:interface]}")
    expected = <<~EOM
      127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4
      ::1 localhost localhost.localdomain localhost6 localhost6.localdomain6
      #{ip} #{fqdn} #{fqdn.split('.').first}
    EOM
  end

  it 'should set grub password'
end
