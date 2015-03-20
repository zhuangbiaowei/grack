#!/usr/bin/env rake
require "bundler/gem_tasks"

task :default => :test

desc "Run the tests."
task :test do
  system "git clone --bare git://github.com/schacon/simplegit.git tests/example.git"
  # We could put this in a chdir block but we should keep it consistent with Travis
  system "cd tests/example.git && git repack && cd ../.."
  Dir.glob("tests/*_test.rb").each do |f|
  	system "ruby #{f}"
  end
  system "rm -rf tests/example.git"
end

desc "Run test coverage."
task :rcov do
  system "rcov tests/*_test.rb -i lib/git_http.rb -x rack -x Library -x tests"
  system "open coverage/index.html"
end

namespace :grack do
  desc "Start Grack"
  task :start do
    system('./bin/testserver')
  end
end

desc "Start everything."
multitask :start => [ 'grack:start' ]
