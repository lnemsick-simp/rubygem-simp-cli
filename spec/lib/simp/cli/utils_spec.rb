require 'simp/cli/utils'
require 'rspec/its'
require 'spec_helper'
require 'tmpdir'

describe Simp::Cli::Utils do

  describe '.validate_password' do
    it 'validates good passwords' do
      expect{ Simp::Cli::Utils.validate_password 'A=V3ry=Go0d=P@ssw0r!' }
        .to_not raise_error
    end

    it 'raises an PasswordError on short passwords' do
      expect{ Simp::Cli::Utils.validate_password 'a@1X' }.to raise_error( Simp::Cli::PasswordError )
    end

    it 'raises an PasswordError on simple passwords' do
      expect{ Simp::Cli::Utils.validate_password 'aaaaaaaaaaaaaaa' }.to raise_error( Simp::Cli::PasswordError )
    end
  end

  describe '.validate_password_with_cracklib' do
    it 'validates good passwords' do
      expect{ Simp::Cli::Utils.validate_password 'A=V3ry=Go0d=P@ssw0r!' }
        .to_not raise_error
    end

    it 'raises an PasswordError on short passwords' do
      expect{ Simp::Cli::Utils.validate_password 'a@1X' }.to raise_error( Simp::Cli::PasswordError )
    end

    it 'raises an PasswordError on simple passwords' do
      expect{ Simp::Cli::Utils.validate_password '012345678901234' }.to raise_error( Simp::Cli::PasswordError )
    end
  end

  describe '.generate_password' do
    let(:default_chars) do
      (("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a).map do|x|
          x = Regexp.escape(x)
      end
    end

    let(:safe_special_chars) do
      ['@','%','-','_','+','=','~'].map do |x|
        x = Regexp.escape(x)
      end
    end

    let(:unsafe_special_chars) do
      (((' '..'/').to_a + ('['..'`').to_a + ('{'..'~').to_a)).map do |x|
        x = Regexp.escape(x)
      end - safe_special_chars
    end

    context 'with defaults' do
      it 'should return a password of the default length' do
        expect( Simp::Cli::Utils.generate_password.size ).to \
          eq Simp::Cli::Utils::DEFAULT_PASSWORD_LENGTH
      end

      it 'should return a password with default and safe special characters' do
        result = Simp::Cli::Utils.generate_password
        expect(result).to match(/(#{default_chars.join('|')})/)
        expect(result).to match(/(#{(safe_special_chars).join('|')})/)
        expect(result).not_to match(/(#{(unsafe_special_chars).join('|')})/)
      end

      it 'should return a password that does not start or end with a special character' do
        expect( Simp::Cli::Utils.generate_password ).to_not match /^[@%\-_+=~]|[@%\-_+=~]$/
      end
    end

    context 'with custom settings that validate' do
      it 'should return a password of the specified length' do
        expect( Simp::Cli::Utils.generate_password( 73 ).size ).to eq 73
      end

      it 'should return a password that contains all special characters if complexity is 2' do
        result = Simp::Cli::Utils.generate_password(32, 2)
        expect(result.length).to eql(32)
        expect(result).to match(/(#{default_chars.join('|')})/)
        expect(result).to match(/(#{(unsafe_special_chars).join('|')})/)
      end
    end

    # these cases require validation to be turned off
    context 'with custom settings that do not validate' do
      it 'should return a password that contains no special chars if complexity is 0' do
        result = Simp::Cli::Utils.generate_password(32, 0, false, 10, false)
        expect(result).to match(/(#{default_chars.join('|')})/)
        expect(result).not_to match(/(#{(safe_special_chars).join('|')})/)
        expect(result).not_to match(/(#{(unsafe_special_chars).join('|')})/)
      end

      it 'should return a password that only contains "safe" special characters if complexity is 1 and complex_only is true' do
        result = Simp::Cli::Utils.generate_password(32, 1, true, 10, false)
        expect(result.length).to eql(32)
        expect(result).not_to match(/(#{default_chars.join('|')})/)
        expect(result).to match(/(#{(safe_special_chars).join('|')})/)
        expect(result).not_to match(/(#{(unsafe_special_chars).join('|')})/)
      end

      it 'should return a password that only contains all special characters if complexity is 2 and complex_only is true' do
        result = Simp::Cli::Utils.generate_password(32, 2, true, 10, false)
        expect(result.length).to eql(32)
        expect(result).to_not match(/(#{default_chars.join('|')})/)
        expect(result).to match(/(#{(unsafe_special_chars).join('|')})/)
      end
    end
  end
end
