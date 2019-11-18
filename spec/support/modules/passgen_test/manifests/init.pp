class passgen_test(
  String $test_dir = '/var/passgen_test',
  Hash   $keys     = {
    'passgen_test_default' =>
      {}, # <==> complexity=0, complex_only=false, length=32
    'passgen_test_c0_8'    =>
      {'complexity' => 0, 'complex_only' => false, 'length' => 8},
    'passgen_test_c1_1024' =>
      {'complexity' => 1, 'complex_only' => false, 'length' => 1024},
    'passgen_test_c2_20'   =>
      {'complexity' => 2, 'complex_only' => false, 'length' => 20},
    'passgen_test_c2_only' =>
      {'complexity' => 2, 'complex_only' => true,  'length' => 32}
    }
) {

  file { $test_dir:
    ensure => directory
  }

  $keys.each |String $name, Hash $settings| {
    file { "${test_dir}/${::environment}-${name}":
      ensure  => present,
      content => simplib::passgen($name, $settings)
    }
  }
}
