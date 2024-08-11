Gem::Specification.new { |s|
  s.name                  = 'excadg'
  s.version               = '0.4.0'
  s.summary               = 'Execute Acyclic Directed Graph'
  s.authors               = ['skorobogatydmitry']
  s.description           = File.read('README.md')[/(?<=# Description)[^#]+/].chomp
  s.files                 = Dir['lib/**/*.rb', 'README.md']
  s.executables           = %w[excadg adgen]
  s.email                 = 'skorobogaty.dmitry@gmail.com'
  s.homepage              = 'https://github.com/skorobogatydmitry/excadg'
  s.license               = 'LGPL-3.0-only'
  s.required_ruby_version = ">= #{File.read('.ruby-version').chomp}"
  s.metadata              = {
    'source_code_uri' => 'https://github.com/skorobogatydmitry/excadg'
  }
  # keep in sync with Gemfile
  s.add_dependency 'rgl', '~>0.6'
}
