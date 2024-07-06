Gem::Specification.new { |s|
  s.name                  = 'excadg'
  s.version               = '0.1.3'
  s.summary               = 'Execute Acyclic Directed Graph'
  s.authors               = ['skorobogatydmitry']
  s.description           = File.read('README.md')[/(?<=# Description)[^#]+/].chomp
  s.files                 = Dir['lib/**/*.rb', 'README.md']
  s.executables           << 'excadg'
  s.email                 = 'skorobogaty.dmitry@gmail.com'
  s.homepage              = 'https://rubygems.org/gems/excadg'
  s.license               = 'LGPL-3.0-only'
  s.required_ruby_version = ">= #{File.read('.ruby-version').chomp}"
  s.metadata              = {
    'source_code' => 'https://github.com/skorobogatydmitry/excadg'
  }
  # keep in sync with Gemfile
  s.add_dependency 'rgl', '~>0.6'
}