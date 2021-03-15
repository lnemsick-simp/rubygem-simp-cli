require 'spec_helper_acceptance'
require 'yaml'

test_name 'simp config with customization for non-ISO install'

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
describe 'simp config with customization for non-ISO install' do
  context "without setting grub password on #{host} and --force-config" do
    hosts.each do |host|
      options = {
        :description        => 'without setting grub password and --force-config',
        :set_grub_password  => false,
        :config_opts_to_add => [ '--force-config' ]
      }

      include_examples 'simp config operation', host, options
    end
  end

  context "without use of SIMP internet repos on #{host}" do
    hosts.each do |host|
      include_examples 'remove SIMP omni environment', host, 'production'

      options = {
        :description             => 'without use of SIMP internet repos',
        :use_simp_internet_repos => false
      }
      include_examples 'simp config operation', host, options
    end
  end

  context "when not LDAP server on #{host}" do
    hosts.each do |host|
      include_examples 'remove SIMP omni environment', host, 'production'

      options = {
        :description => 'when not LDAP server',
        :ldap_server => false
      }
      include_examples 'simp config operation', host, options
    end
  end

  context "with logservers but without failover logservers on #{host}" do
    hosts.each do |host|
      include_examples 'remove SIMP omni environment', host, 'production'

      options = {
        :description => 'with logservers but without failover logservers',
        :logservers  => [ '1.2.3.4', '1.2.3.5']
      }
      include_examples 'simp config operation', host, options
    end
  end

  context "with logservers and failover logservers on #{host}" do
    hosts.each do |host|
      include_examples 'remove SIMP omni environment', host, 'production'

      options = {
        :description         => 'with logservers and failover logservers',
        :logservers          => [ '1.2.3.4', '1.2.3.5'],
        :failover_logservers => [ '1.2.3.6', '1.2.3.7']
      }
      include_examples 'simp config operation', host, options
    end
  end

  context 'when local priv user exists without ssh authorized keys' do
    hosts.each do |host|
      include_examples 'remove SIMP omni environment', host, 'production'

      options = {
        :description => 'when local priv user exists without ssh authorized keys',
        :priv_user   =>  {
          :name     => 'simpadmin',
          :exists   => true, # ASSUMES user already exists
          :has_keys => false
        }
      }
      include_examples 'simp config operation', host, options
    end
  end

  context 'when local priv user exists with authorized keys' do
    hosts.each do |host|
      include_examples 'remove SIMP omni environment', host, 'production'

      options = {
        :description => 'when local priv user exists with ssh authorized keys',
        :priv_user   =>  {
          :name     => 'vagrant',
          :exists   => true, # ASSUMES user already exists
          :has_keys => true  # ASSUMES authorized_key file exists
        }
      }
      include_examples 'simp config operation', host, options
    end
  end

  context "when do not want to ensure local priv user on #{host}" do
    hosts.each do |host|
      include_examples 'remove SIMP omni environment', host, 'production'

      options = {
        :description => 'when do not want to ensure local priv user',
        :priv_user   => nil
      }
      include_examples 'simp config operation', host, options
    end
  end

  # simp_lite scenario is nearly identical to simp scenario, so only need
  # to test with defaults
  context "when simp_lite scenario using defaults on #{host}" do
    hosts.each do |host|
      include_examples 'remove SIMP omni environment', host, 'production'

      options = {
        :description => 'when simp_lite_scenario using defaults',
        :scenario    => 'simp_lite'
      }
      include_examples 'simp config operation', host, options
    end
  end

  context 'when poss scenario' do
    context 'using defaults' do
      hosts.each do |host|
        include_examples 'remove SIMP omni environment', host, 'production'

        options = {
          :description  => 'when poss scenario using defaults'
        }
        include_examples 'simp config operation', host, options
      end
    end

    context 'without LDAP but with SSSD' do
      hosts.each do |host|
        include_examples 'remove SIMP omni environment', host, 'production'

        options = {
          :description => 'with poss scenario without LDAP but with SSSD',
          :ldap_server => false
        }
        include_examples 'simp config operation', host, options
      end
    end

    context 'without either LDAP or SSSD' do
      hosts.each do |host|
        include_examples 'remove SIMP omni environment', host, 'production'

        options = {
          :description => 'with poss scenario without either LDAP or SSSD',
          :ldap_server => false,
          :sssd        => false
        }
        include_examples 'simp config operation', host, options
      end
    end
  end

  context 'with Puppet environment set by ENV' do
    hosts.each do |host|
      options = {
        :description => 'using SIMP_ENVIRONMENT',
        :puppet_env  => 'dev',
        :env_vars    => [ 'SIMP_ENVIRONMENT=dev' ]
      }
      include_examples 'simp config operation', host, options
    end
  end
end

#
# other paths in decision tree, mock ISO
# - has simp_filesystem.repo
# should have different global hieradata (?)
# should have different SIMP server hieradata (disable SIMP server repos in favor of filesystem repos)
#    it 'should disable CentOS yum repos'
