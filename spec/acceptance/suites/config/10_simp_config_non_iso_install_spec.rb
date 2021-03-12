require 'spec_helper_acceptance'
require 'yaml'

test_name 'simp config for non-ISO install'

# Tests `simp config`, alone, in a server configuration that is akin to
# installation from RPM.
#
# - The minimal server set up only has modules and assets required for
#   the limited `simp config` testing done here.
# - Does NOT support network configuration via `simp config`.
# - Does NOT support `simp bootstrap` testing. Bootstrap tests must install
#   most of the components in one of simp-core's Puppetfiles in order to
#   have everything needed for bootstrap testing. See simp-core acceptance
#   tests for bootstrap tests.
#
describe 'simp config for non-ISO install' do
  let(:grub_pwd_hash) {
    'grub.pbkdf2.sha512.10000.DE78658C8482E4F3752B61942622345CB22BF23FECDDDCA41D9891FF7569376D3177D11945AF344267B04B44227475BDD520367D5A492EEADCBAB6AA76718AFA.2B08D03310E1514F517A59D9F1B174C73DC15B9C02010F88DC6E6FC8C869D16B9B38E9004CB6382AFE3A68BFC29E14B49C48360ED829D6EDC25E05F5609069F8'
  }

  let(:ldap_rootpw_hash) { "{SSHA}oIQoj6htrx7TnXwhTOY57ThnklOJkD8m" }
  let(:priv_user_pwd_hash) {
    '$6$l69r7t36$WZxDVhvdMZeuL0vRvOrSLMKWxxQbuK1j8t0vaEq3BW913hjOJhRNTxqlKzDflPW7ULPwkBa6xdfcca2BlGoq/.'
  }

  let(:config_opts) { [
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
    'cli::network::interface=eth1',   # FIXME: ASSUMES eth1 is the private network

     # Set password (hashes) for passwords that must be preassigned when
     # queries are disabled.
     # - All hashes correspond to 'P@ssw0rdP@ssw0rd'
     # - Be sure to put <key=value> in single quotes to prevent any bash
     #   interpretation.
    "'grub::password=#{grub_pwd_hash}'",
    "'simp_openldap::server::conf::rootpw=#{ldap_rootpw_hash}'",
    "'cli::local_priv_user_password=#{priv_user_pwd_hash}'"
  ] }

  let(:prod_puppet_env) { '/etc/puppetlabs/code/environments/production' }
  let(:prod_secondary_env) { '/var/simp/environments/production' }

  hosts.each do |host|
    context "using defaults on #{host}" do
      let(:fqdn) { fact_on(host, 'fqdn') }
      let(:domain) { fact_on(host, 'domain') }
      let(:fips) { fips_enabled(host) }

      it 'should create and configure production env primarily using defaults' do
         result = on(host, "simp config #{config_opts.join(' ')}")
      end

      it 'should create a production Puppet environment' do
        expect( directory_exists_on(host, prod_puppet_env) ).to be true
        expect( file_exists_on(host, "#{prod_puppet_env}/Puppetfile") ).to be true
        on(host, "grep 'Puppetfile.simp' #{prod_puppet_env}/Puppetfile | grep ^instance_eval")

        expect( file_exists_on(host, "#{prod_puppet_env}/Puppetfile.simp") ).to be true
        modules = on(host, 'ls /usr/share/simp/modules').stdout.split("\n")
        modules.each do |name|
          result = on(host, "grep name /usr/share/simp/modules/#{name}/metadata.json | grep #{name}")
          repo_name = result.stdout.match( /(\w+\-\w*)/ )[1]
          on(host, "grep '/usr/share/simp/git/puppet_modules/#{repo_name}.git' #{prod_puppet_env}/Puppetfile.simp")
        end

        expect( file_exists_on(host, "#{prod_puppet_env}/environment.conf") ).to be true
        custom_mod_path = 'modulepath = site:modules:/var/simp/environments/production/site_files:$basemodulepath'
        on(host, "grep '#{custom_mod_path}' #{prod_puppet_env}/environment.conf")

        expect( file_exists_on(host, "#{prod_puppet_env}/hiera.yaml") ).to be true
        on(host, "diff /usr/share/simp/environment-skeleton/puppet/hiera.yaml #{prod_puppet_env}/hiera.yaml")

        modules.each do |name|
          expect( directory_exists_on(host, "#{prod_puppet_env}/modules/#{name}") ).to be true
        end
      end

      it 'should create a simp_config_settings.yaml global hiera file' do
        yaml_file = "#{prod_puppet_env}/data/simp_config_settings.yaml"
        expect( file_exists_on(host, yaml_file) ).to be true

        # FIXME validate file content not just keys. Only validation done
        # in unit tests is answers file content.
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
        yaml_file = "#{prod_puppet_env}/data/hosts/#{fqdn}.yaml"
        actual = YAML.load( file_contents_on(host, yaml_file) )

        # load in template and then merge with adjustments that
        # `simp config` should make
        template = '/usr/share/simp/environment-skeleton/puppet/data/hosts/puppet.your.domain.yaml'
        expected = YAML.load( file_contents_on(host, template) )
        adjustments = {
          'simp::server::allow_simp_user'              => false,
           'puppetdb::master::config::puppetdb_server' => "%{hiera('simp_options::puppet::server')}",
           'puppetdb::master::config::puppetdb_port'   => 8139,
           'simp_openldap::server::conf::rootpw'       => '{SSHA}oIQoj6htrx7TnXwhTOY57ThnklOJkD8m',
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


      it 'should set SIMP scenario in site.pp' do
        site_pp = File.join(prod_puppet_env, 'manifests', 'site.pp')
        expect( file_exists_on(host, site_pp) ).to be true
        actual = file_contents_on(host, site_pp)
        expect( actual ).to match(/^\$simp_scenario\s*=\s*'simp'/)
      end

      it 'should create a production secondary environment' do
        expect( directory_exists_on(host, prod_secondary_env) ).to be true
        expect( directory_exists_on(host, "#{prod_secondary_env}/FakeCA") ).to be true
        expect( directory_exists_on(host, "#{prod_secondary_env}/rsync") ).to be true
        expect( directory_exists_on(host, "#{prod_secondary_env}/site_files") ).to be true
      end

      it 'should create cacerts and host cert files in the secondary env' do
        keydist_dir = "#{prod_secondary_env}/site_files/pki_files/files/keydist"
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
        ip = fact_on(host, 'ipaddress_eth1')
        expected = <<~EOM
          127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4
          ::1 localhost localhost.localdomain localhost6 localhost6.localdomain6
          #{ip} #{fqdn} #{fqdn.split('.').first}
        EOM
      end

      it 'should set grub password'
    end
  end

  context 'with customization' do

    context 'without setting of grub password' do
    end

    context 'without use of SIMP internet repos' do
    end

    context 'when not LDAP server' do
    end

    context 'with logservers but without failover logservers' do
    end

    context 'with logservers and failover logservers' do
    end

    context 'when local priv user exists without ssh authorized keys' do
    end

    context 'when local priv user exists without authorized keys' do
    end

    context 'when do not want to ensure local priv user' do
    end

    # simp_lite scenario is nearly identical to simp scenario, so only need
    # to test with defaults
    context 'when simp_lite scenario using defaults' do
    end

    context 'when poss scenario' do
      context 'using defaults' do
      end

      context 'without LDAP' do
      end
    end
  end

  context 'with Puppet environment set by ENV' do
  end
end

#
# other paths in decision tree
# - has simp_filesystem.repo
#    it 'should disable CentOS yum repos'
# - has simp user from ISo
