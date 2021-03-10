require 'simp/cli/config/yaml_utils'
require 'tmpdir'

class YamlUtilsTester
  include Simp::Cli::Config::YamlUtils
end

describe 'Simp::Cli::Config::YamlUtils API' do
  before :each do
    @files_dir = File.expand_path( 'files', File.dirname( __FILE__ ) )
    @tmp_dir   = Dir.mktmpdir( File.basename(__FILE__) )
    @test_file = File.join(@tmp_dir, 'test.yaml')
    @tester = YamlUtilsTester.new
  end

  after :each do
    FileUtils.remove_entry_secure @tmp_dir
  end

  describe '#merge_required?' do
    it 'returns false when either argument is not an Array or Hash' do
      expect( @tester.merge_required?(false, {}) ).to be false
      expect( @tester.merge_required?(nil, {}) ).to be false
      expect( @tester.merge_required?([], 1) ).to be false
      expect( @tester.merge_required?([], nil) ).to be false
    end

    it 'returns false when arguments are not both either Arrays or Hashes' do
      expect( @tester.merge_required?([],{}) ).to be false
      expect( @tester.merge_required?({},[]) ).to be false
    end

    it 'returns true when new Array has elements not found in old Array' do
      expect( @tester.merge_required?([1, 2, 3], [1, 4, 5]) ).to be true
      expect( @tester.merge_required?([], [1, 4, 5]) ).to be true
    end

    it 'returns false when new Array does not new elements' do
      expect( @tester.merge_required?([1, 2, 3], [1]) ).to be false
      expect( @tester.merge_required?([1, 2, 3], []) ).to be false
    end

    it 'returns true when new Hash has a new primary key' do
      old = { 'a' => 1, 'b' => { 'c' => 2 } }
      new = { 'd' => 3 }
      expect( @tester.merge_required?(old, new) ).to be true
    end

    it 'returns true when new Hash has a changed value for same primary key' do
      old = { 'a' => 1, 'b' => { 'c' => 2 } }
      new = { 'b' => 10 }
      expect( @tester.merge_required?(old, new) ).to be true
    end

    it 'returns false when new Hash matches old Hash' do
      old = { 'a' => 1, 'b' => { 'c' => 2 } }
      expect( @tester.merge_required?(old, old) ).to be false
    end

    it 'returns false when new Hash has a key whose value matches old Hash' do
      old = { 'a' => 1, 'b' => { 'c' => 2 } }
      new = { 'b' => { 'c' => 2 } }
      expect( @tester.merge_required?(old, new) ).to be false
    end
  end

  describe '#pair_to_yaml_tag' do
    {
      'boolean'        => { :value => true, :exp => "key: true\n" },
      'integer'        => { :value => 1, :exp => "key: 1\n" },
      'float'          => { :value => 1.5, :exp => "key: 1.5\n" },
      'simple string'  => { :value => 'simple', :exp => "key: simple\n" },
      'complex string' => { :value => "%{alias('simp_options::trusted_nets')}",
        :exp => "key: \"%{alias('simp_options::trusted_nets')}\"\n" },
      'array'          => { :value => [1,2], :exp => <<~EOM
        key:
        - 1
        - 2
      EOM
      },
      'hash'           => { :value => {'a' => {'b' => [1,2]}}, :exp => <<~EOM
        key:
          a:
            b:
            - 1
            - 2
        EOM
      }
    }.each do |type, attr|
      it "returns a valid YAML tag for a #{type} value" do
        expect( @tester.pair_to_yaml_tag('key', attr[:value]) ).to eq(attr[:exp])
      end
    end
  end

  describe '#load_yaml_with_comment_blocks' do
    it 'should load YAML and comment blocks before primary keys' do
      file = File.join(@files_dir, 'yaml_with_comments.yaml')
      FileUtils.copy_file file, @test_file
    end
  end

  describe '#add_yaml_tag_directive' do
=begin
      file = File.join(@files_dir, 'puppet.your.domain.yaml')
      FileUtils.copy_file file, @host_file
      @ci.apply
      expect( @ci.applied_status ).to eq :succeeded
      expected = File.join(@files_dir, 'host_with_ldap_server_config_added.yaml')
      expect( IO.read(@host_file) ).to eq IO.read(expected)
=end
  end

  describe '#replace_yaml_tag' do
  end

  describe '#merge_yaml_tag(' do
  end

  describe '#merge_or_replace_yaml_tag' do
  end
end
