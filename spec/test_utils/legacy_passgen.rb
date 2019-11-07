module TestUtils
  module LegacyPassgen

    def create_password_files(password_dir, names_with_backup, names_without_backup=[])
      names_with_backup.each do |name|
        name_file = File.join(password_dir, name)
        File.open(name_file, 'w') { |file| file.puts "#{name}_password" }
        File.open("#{name_file}.salt", 'w') { |file| file.puts "salt for #{name}" }
        File.open("#{name_file}.last", 'w') { |file| file.puts "#{name}_backup_password" }
        File.open("#{name_file}.salt.last", 'w') { |file| file.puts "salt for #{name} backup" }
      end

      names_without_backup.each do |name|
        name_file = File.join(password_dir, name)
        File.open(name_file, 'w') { |file| file.puts "#{name}_password" }
        File.open("#{name_file}.salt", 'w') { |file| file.puts "salt for #{name}" }
      end
    end

    def validate_files(expected_file_info)
      expected_file_info.each do |file,expected_contents|
        if expected_contents.nil?
          expect( File.exist?(file) ).to be false
        else
          expect( File.exist?(file) ).to be true
          expect( IO.read(file).chomp ).to eq expected_contents
        end
      end
    end
  end
end
