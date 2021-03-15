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
describe 'simp config for non-ISO install' do
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
# other paths in decision tree, mock ISO
# - has simp_filesystem.repo
# should have different global hieradata (?)
# should have different SIMP server hieradata (disable SIMP server repos in favor of filesystem repos)
#    it 'should disable CentOS yum repos'
