# encoding: utf-8

## This is the rakegem gemspec template. Make sure you read and understand
## all of the comments. Some sections require modification, and others can
## be deleted if you don't need them. Once you understand the contents of
## this file, feel free to delete any comments that begin with two hash marks.
## You can find comprehensive Gem::Specification documentation, at
## http://docs.rubygems.org/read/chapter/20
Gem::Specification.new do |s|

  ## Leave these as is they will be modified for you by the rake gemspec task.
  ## If your rubyforge_project name is different, then edit it and comment out
  ## the sub! line in the Rakefile
  s.name              = 'rtiss_acts_as_versioned'
  s.version           = '0.7.4'
  s.date              = '2014-06-11'
  s.rubyforge_project = 'rtiss_acts_as_versioned'
  s.summary     = "Add simple versioning to ActiveRecord models (TISS version)."
  s.description = "Add simple versioning to ActiveRecord models (TISS version).

Each model has a to-many model named mymodel_h which records all changes 
(including destroys but not deletes) made to the model. This is the version
used by http://tiss.tuwien.ac.at and substantially differs from the original
version. If you want to use acts_as_versioned in your project we recommend
to use technoweenie's version (can be found also on github)"

  s.authors  = ["Rick Olson", "Johannes Thoma", "Igor Jancev"]
  s.email    = 'igor.jancev@tuwien.ac.at'
  s.homepage = 'http://github.com/rtiss/rtiss_acts_as_versioned'
  s.require_paths = ["lib"]
  s.rdoc_options = ["--charset=UTF-8"]
  s.extra_rdoc_files = %w[README MIT-LICENSE CHANGELOG]

  s.add_dependency 'activerecord', ">= 3.0.9"
  s.add_development_dependency 'sqlite3-ruby', "~> 1.3.1"
  s.add_development_dependency 'rails', "~> 3.0.20"
  s.add_development_dependency 'mysql', "~> 2.8.1"

  ## Leave this section as-is. It will be automatically generated from the
  ## contents of your Git repository via the gemspec task. DO NOT REMOVE
  ## THE MANIFEST COMMENTS, they are used as delimiters by the task.
  # = MANIFEST =
  s.files = %w[
    CHANGELOG
    Gemfile
    MIT-LICENSE
    README
    RUNNING_UNIT_TESTS
    Rakefile
    init.rb
    lib/rtiss_acts_as_versioned.rb
    rtiss_acts_as_versioned.gemspec
    test/abstract_unit.rb
    test/database.yml
    test/fixtures/authors.yml
    test/fixtures/landmark.rb
    test/fixtures/landmark_h.yml
    test/fixtures/landmarks.yml
    test/fixtures/locked_pages.yml
    test/fixtures/locked_pages_revisions.yml
    test/fixtures/locked_rolle.rb
    test/fixtures/migrations/1_add_versioned_tables.rb
    test/fixtures/page.rb
    test/fixtures/pages.yml
    test/fixtures/pages_h.yml
    test/fixtures/rolle.rb
    test/fixtures/widget.rb
    test/migration_test.rb
    test/schema.rb
    test/tiss_test.rb
    test/versioned_test.rb
  ]
  # = MANIFEST =

  ## Test files will be grabbed from the file list. Make sure the path glob
  ## matches what you actually use.
  s.test_files = s.files.select { |path| path =~ /^test\/test_.*\.rb/ }
end
