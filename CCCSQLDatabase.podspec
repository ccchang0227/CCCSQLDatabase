Pod::Spec.new do |s|
  s.name             = 'CCCSQLDatabase'
  s.version          = '1.5.1'
  s.summary          = 'SQLite Database for saving data.'

  s.homepage         = 'https://github.com/ccchang0227/CCCSQLDatabase'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.authors          = { 'Chih-chieh Chang' => 'ccch.realtouch@gmail.com' }
  s.source           = { :git => 'https://github.com/ccchang0227/CCCSQLDatabase.git', :tag => s.version.to_s }

  s.requires_arc = false
  s.ios.deployment_target = '6.0'
  s.tvos.deployment_target = '9.0'

  s.source_files = 'Classes/**/*.{h,m}'

  s.dependency 'FMDB', '~> 2.6.2'
end
